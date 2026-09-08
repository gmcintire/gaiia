defmodule Gaiia.RetryAndCollectTest do
  @moduledoc """
  The eager pagination pair and the retry-decision helpers.

  Both exist because the lazy stream and the raw `%Gaiia.Error{}` push the same
  two decisions onto every caller: what to do with a page that failed halfway
  through a traversal, and whether a failure is worth repeating.
  """
  use ExUnit.Case, async: true

  alias Gaiia.Client
  alias Gaiia.Error
  alias Gaiia.Pagination
  alias Gaiia.RateLimit
  alias Gaiia.ReqStub

  # Reserved TEST-NET-1 (RFC 5737) address — unroutable, so an unstubbed
  # request fails immediately rather than hanging.
  @endpoint "http://192.0.2.1:1/graphql"

  describe "Pagination.collect/4" do
    test "returns every node across every page" do
      client = client_replaying([page(["a", "b"], true, "cursor-1"), page(["c"], false, nil)])

      assert {:ok, ["a", "b", "c"]} = Pagination.collect(client, "query {}", %{}, path: ["accounts"])
    end

    test "sends the cursor the previous page ended on" do
      client = client_replaying([page(["a"], true, "cursor-1"), page(["b"], false, nil)])

      {:ok, _nodes} = Pagination.collect(client, "query {}", %{"first" => 1}, path: ["accounts"])

      assert %{"first" => 1, "after" => "cursor-1"} = ReqStub.captured_body()["variables"]
    end

    test "returns the failure of a page mid-traversal instead of raising" do
      client = client_replaying([page(["a"], true, "cursor-1"), %{"errors" => [%{"message" => "boom"}]}])

      assert {:error, %Error{kind: :graphql, message: message}} =
               Pagination.collect(client, "query {}", %{}, path: ["accounts"])

      assert message =~ "boom"
    end

    test "discards the pages collected before a failure" do
      client = client_replaying([%{"errors" => [%{"message" => "boom"}]}])

      assert {:error, %Error{}} = Pagination.collect(client, "query {}", %{}, path: ["accounts"])
    end

    test "returns an empty list for a connection with no nodes" do
      client = client_replaying([page([], false, nil)])

      assert {:ok, []} = Pagination.collect(client, "query {}", %{}, path: ["accounts"])
    end

    test "walks backward when asked" do
      client =
        client_replaying([
          %{
            "data" => %{
              "accounts" => %{
                "nodes" => ["newest"],
                "pageInfo" => %{"hasPreviousPage" => true, "startCursor" => "cursor-1"}
              }
            }
          },
          %{
            "data" => %{
              "accounts" => %{
                "nodes" => ["older"],
                "pageInfo" => %{"hasPreviousPage" => false, "startCursor" => nil}
              }
            }
          }
        ])

      assert {:ok, ["newest", "older"]} =
               Pagination.collect(client, "query {}", %{}, path: ["accounts"], direction: :backward)

      assert %{"before" => "cursor-1"} = ReqStub.captured_body()["variables"]
    end
  end

  describe "Pagination.collect_edges/4" do
    test "returns each edge with its own cursor" do
      edges = [%{"cursor" => "c1", "node" => %{"id" => "a"}}]

      client =
        client_replaying([
          %{
            "data" => %{
              "accounts" => %{
                "edges" => edges,
                "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
              }
            }
          }
        ])

      assert {:ok, ^edges} = Pagination.collect_edges(client, "query {}", %{}, path: ["accounts"])
    end

    test "surfaces a failure as an error tuple" do
      client = client_replaying([%{"errors" => [%{"message" => "boom"}]}])

      assert {:error, %Error{kind: :graphql}} =
               Pagination.collect_edges(client, "query {}", %{}, path: ["accounts"])
    end
  end

  describe "Error.retriable?/1" do
    test "a request that never reached the server is worth repeating" do
      assert Error.retriable?(Error.network(%Req.TransportError{reason: :econnrefused}))
    end

    test "a server-side failure is worth repeating" do
      assert Error.retriable?(Error.http(500, ""))
      assert Error.retriable?(Error.http(503, ""))
    end

    test "rate limiting is worth repeating in either form the API reports it" do
      assert Error.retriable?(Error.http(429, ""))

      assert Error.retriable?(Error.graphql([%{"message" => "slow down", "extensions" => %{"code" => "RATE_LIMITED"}}]))
    end

    test "a rejected request will be rejected again" do
      refute Error.retriable?(Error.http(400, ""))
      refute Error.retriable?(Error.http(404, ""))

      refute Error.retriable?(Error.graphql([%{"message" => "no key", "extensions" => %{"code" => "UNAUTHENTICATED"}}]))

      refute Error.retriable?(Error.graphql([%{"message" => "unknown argument"}]))
      refute Error.retriable?(Error.decode("<html>"))
    end
  end

  describe "retry_after" do
    test "reports whole seconds until the API's retry time, rounding up" do
      now = ~U[2026-09-08 12:00:00Z]
      budget = %RateLimit{retry_at: ~U[2026-09-08 12:00:29.100Z]}

      assert RateLimit.retry_after(budget, now) == 30
    end

    test "reports zero for a retry time already past" do
      now = ~U[2026-09-08 12:00:00Z]

      assert RateLimit.retry_after(%RateLimit{retry_at: ~U[2026-09-08 11:59:00Z]}, now) == 0
    end

    test "reports nil when the API named no retry time" do
      assert RateLimit.retry_after(%RateLimit{remaining: 0}, DateTime.utc_now()) == nil
      assert RateLimit.retry_after(nil, DateTime.utc_now()) == nil
    end

    test "reads the budget off the error the API rejected the operation with" do
      now = ~U[2026-09-08 12:00:00Z]

      error =
        Error.graphql(
          [
            %{
              "message" => "slow down",
              "extensions" => %{"code" => "RATE_LIMITED", "retryAt" => "2026-09-08T12:00:15Z"}
            }
          ],
          status: 200
        )

      assert Error.retry_after(error, now) == 15
    end

    test "reports nil for an error that carried no budget" do
      assert Error.retry_after(Error.http(500, ""), DateTime.utc_now()) == nil
    end
  end

  describe "RateLimit.exhausted?/1" do
    test "a rejected operation leaves no room" do
      assert RateLimit.exhausted?(%RateLimit{allowed: false})
    end

    test "no points remaining leaves no room" do
      assert RateLimit.exhausted?(%RateLimit{remaining: 0})
      assert RateLimit.exhausted?(%RateLimit{remaining: -5})
    end

    test "points remaining leaves room" do
      refute RateLimit.exhausted?(%RateLimit{allowed: true, remaining: 1})
    end

    test "an unreported budget is not treated as exhausted" do
      refute RateLimit.exhausted?(%RateLimit{})
      refute RateLimit.exhausted?(nil)
    end
  end

  defp page(nodes, has_next, end_cursor) do
    %{
      "data" => %{
        "accounts" => %{
          "nodes" => nodes,
          "pageInfo" => %{"hasNextPage" => has_next, "endCursor" => end_cursor}
        }
      }
    }
  end

  # Replays `bodies` in order, then keeps answering with a terminal empty page.
  defp client_replaying(bodies) do
    counter = :counters.new(1, [])

    options =
      ReqStub.install(fn _request ->
        :counters.add(counter, 1, 1)
        index = :counters.get(counter, 1) - 1

        bodies
        |> Enum.at(index, page([], false, nil))
        |> ReqStub.ok_response()
      end)

    Client.new(endpoint: @endpoint, req_options: options)
  end
end
