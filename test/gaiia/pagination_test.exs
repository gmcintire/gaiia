defmodule Gaiia.PaginationTest do
  use ExUnit.Case, async: true

  alias Gaiia.Client
  alias Gaiia.Pagination
  alias Gaiia.ReqStub

  # Reserved TEST-NET-1 (RFC 5737) address — unroutable so an unstubbed
  # request would fail immediately rather than hang.
  @endpoint "http://192.0.2.1:1/graphql"

  defp page(nodes, has_next, end_cursor) do
    %{
      "data" => %{
        "accounts" => %{
          "nodes" => nodes,
          "pageInfo" => %{
            "hasNextPage" => has_next,
            "endCursor" => end_cursor
          }
        }
      }
    }
  end

  # Installs a stub that replays `pages` in order, then keeps returning an
  # empty terminal page. Returns the `req_options` for the client.
  defp stub_pages(pages) do
    counter = :counters.new(1, [])

    ReqStub.install(fn _req ->
      idx = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)
      ReqStub.ok_response(Enum.at(pages, idx) || page([], false, nil))
    end)
  end

  describe "stream/4" do
    test "walks all pages until hasNextPage is false" do
      req_options =
        stub_pages([
          page([%{"id" => "1"}, %{"id" => "2"}], true, "c1"),
          page([%{"id" => "3"}], true, "c2"),
          page([%{"id" => "4"}], false, nil)
        ])

      client = Client.new(endpoint: @endpoint, req_options: req_options)

      ids =
        client
        |> Pagination.stream(
          "query($after: String) { accounts(after: $after) { nodes { id } pageInfo { hasNextPage endCursor } } }",
          %{},
          path: ["accounts"]
        )
        |> Enum.map(& &1["id"])

      assert ids == ["1", "2", "3", "4"]
    end

    test "returns an empty stream when the first page is empty" do
      client = Client.new(endpoint: @endpoint, req_options: stub_pages([page([], false, nil)]))

      result =
        client
        |> Pagination.stream("query { accounts { nodes { id } pageInfo { hasNextPage endCursor } } }", %{},
          path: ["accounts"]
        )
        |> Enum.to_list()

      assert result == []
    end

    test "propagates errors by raising" do
      req_options = ReqStub.install(fn _req -> %Req.Response{status: 500, body: "boom", headers: %{}} end)
      client = Client.new(endpoint: @endpoint, req_options: req_options)

      assert_raise Gaiia.Error, ~r/500/, fn ->
        client
        |> Pagination.stream("{ accounts { nodes { id } pageInfo { hasNextPage endCursor } } }", %{}, path: ["accounts"])
        |> Enum.to_list()
      end
    end
  end
end
