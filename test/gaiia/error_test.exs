defmodule Gaiia.ErrorTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Gaiia.Error
  alias Gaiia.RateLimit

  describe "graphql/2" do
    test "joins messages, fills missing messages, and uses the first error's code" do
      errors = [
        %{
          "message" => "Rate limit exceeded",
          "extensions" => %{"code" => "RATE_LIMITED"}
        },
        %{"message" => "Try again later", "extensions" => %{"code" => "IGNORED"}},
        %{}
      ]

      error = Error.graphql(errors, status: 200)

      assert %Error{
               kind: :graphql,
               code: "RATE_LIMITED",
               status: 200,
               errors: ^errors
             } = error

      assert error.message ==
               "GraphQL error: Rate limit exceeded; Try again later; <no message>"
    end

    test "uses an explicit rate limit instead of the first error's extensions" do
      explicit_rate_limit = %RateLimit{allowed: true, remaining: 99}

      errors = [
        %{
          "message" => "Rate limit exceeded",
          "extensions" => %{
            "code" => "RATE_LIMITED",
            "remaining" => 0
          }
        }
      ]

      error = Error.graphql(errors, rate_limit: explicit_rate_limit)

      assert error.rate_limit == explicit_rate_limit
      assert Exception.message(error) == "GraphQL error: Rate limit exceeded"
    end

    test "derives the rate limit from RATE_LIMITED extensions when none is provided" do
      errors = [
        %{
          "message" => "Rate limit exceeded",
          "extensions" => %{
            "code" => "RATE_LIMITED",
            "cost" => 138,
            "limit" => 500,
            "used" => 462,
            "remaining" => 38,
            "retryAt" => "2024-06-27T19:01:02.000Z"
          }
        }
      ]

      error = Error.graphql(errors)

      assert error.rate_limit == %RateLimit{
               allowed: false,
               cost: 138,
               limit: 500,
               used: 462,
               remaining: 38,
               retry_at: ~U[2024-06-27 19:01:02.000Z]
             }
    end

    test "describes an empty GraphQL error list without inventing metadata" do
      error = Error.graphql([])

      assert %Error{
               kind: :graphql,
               message: "GraphQL error: <no message>",
               code: nil,
               rate_limit: nil,
               status: nil,
               errors: []
             } = error

      assert Exception.message(error) == "GraphQL error: <no message>"
    end
  end

  describe "http/3" do
    test "keeps the response body and reported rate limit" do
      body = %{"error" => "boom"}
      rate_limit = %RateLimit{remaining: 0}
      error = Error.http(503, body, rate_limit: rate_limit)

      assert %Error{
               kind: :http,
               message: "HTTP 503 from Gaiia API",
               status: 503,
               details: ^body,
               rate_limit: ^rate_limit
             } = error

      assert Exception.message(error) == "HTTP 503 from Gaiia API"
    end
  end

  describe "network/1" do
    test "uses the transport exception's message" do
      exception = %RuntimeError{message: "econnrefused"}
      error = Error.network(exception)

      assert %Error{
               kind: :network,
               message: "Network error: econnrefused",
               details: ^exception
             } = error

      assert Exception.message(error) == "Network error: econnrefused"
    end

    test "preserves and inspects a transport failure that is not an exception" do
      reason = {:shutdown, :econnrefused}
      error = Error.network(reason)

      assert %Error{
               kind: :network,
               message: "Network error: {:shutdown, :econnrefused}",
               details: ^reason
             } = error

      assert Exception.message(error) == "Network error: {:shutdown, :econnrefused}"
    end
  end

  describe "decode/1" do
    test "keeps the undecodable response body" do
      body = <<0, 255, 1>>
      error = Error.decode(body)

      assert %Error{
               kind: :decode,
               message: "Could not decode Gaiia response body",
               details: ^body
             } = error

      assert Exception.message(error) == "Could not decode Gaiia response body"
    end
  end

  describe "Exception protocol" do
    test "raises with the embedded message" do
      assert_raise Error, "GraphQL error: Forbidden", fn ->
        raise Error.graphql([%{"message" => "Forbidden"}])
      end
    end
  end

  defp assert_messages_in_order(formatted, messages) do
    Enum.reduce(messages, byte_size("GraphQL error: "), fn message, offset ->
      assert {position, length} =
               :binary.match(formatted, message, scope: {offset, byte_size(formatted) - offset})

      position + length
    end)
  end

  property "GraphQL messages remain present and ordered" do
    message =
      (Enum.map(?a..?z, &<<&1>>) ++ [";", " "])
      |> StreamData.member_of()
      |> StreamData.list_of(
        min_length: 1,
        max_length: 24
      )
      |> StreamData.map(&Enum.join/1)

    check all(messages <- StreamData.list_of(message, max_length: 11)) do
      errors = Enum.map(messages, &%{"message" => &1}) ++ [%{}]
      error = Error.graphql(errors)

      assert_messages_in_order(error.message, messages ++ ["<no message>"])
    end
  end
end
