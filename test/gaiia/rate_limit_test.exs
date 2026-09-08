defmodule Gaiia.RateLimitTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Gaiia.RateLimit

  @fields [:allowed, :cost, :limit, :used, :remaining, :retry_at]

  describe "from_headers/1" do
    test "maps every rate-limit header into the corresponding field" do
      headers = %{
        "x-rate-limit-allowed" => ["true"],
        "x-rate-limit-cost" => ["8"],
        "x-rate-limit-limit" => ["500"],
        "x-rate-limit-used" => ["108"],
        "x-rate-limit-remaining" => ["392"],
        "x-rate-limit-retry-at" => ["2024-06-27T19:01:02.000Z"]
      }

      assert RateLimit.from_headers(headers) == %RateLimit{
               allowed: true,
               cost: 8,
               limit: 500,
               used: 108,
               remaining: 392,
               retry_at: ~U[2024-06-27 19:01:02.000Z]
             }
    end

    test "normalizes list and map containers with plain or wrapped values case-insensitively" do
      wrapped = %{
        "x-rate-limit-allowed" => ["true"],
        "x-rate-limit-cost" => ["8"],
        "x-rate-limit-limit" => ["500"]
      }

      plain_map = %{
        "X-RATE-LIMIT-ALLOWED" => "true",
        "X-Rate-Limit-Cost" => "8",
        "x-rate-limit-limit" => "500"
      }

      pairs = [
        {"X-Rate-Limit-Allowed", "true"},
        {"X-RATE-LIMIT-COST", "8"},
        {"x-rate-limit-limit", "500"}
      ]

      expected = RateLimit.from_headers(wrapped)

      assert expected == %RateLimit{allowed: true, cost: 8, limit: 500}
      assert RateLimit.from_headers(plain_map) == expected
      assert RateLimit.from_headers(pairs) == expected
    end

    test "parses false strings and already-decoded booleans" do
      assert %RateLimit{allowed: false} =
               RateLimit.from_headers(%{"x-rate-limit-allowed" => "false"})

      assert %RateLimit{allowed: true} =
               RateLimit.from_headers(%{"x-rate-limit-allowed" => true})

      assert %RateLimit{allowed: false} =
               RateLimit.from_headers(%{"x-rate-limit-allowed" => false})
    end

    test "keeps leading integer digits but rejects non-numeric integers and invalid datetimes" do
      assert RateLimit.from_headers(%{
               "x-rate-limit-allowed" => "false",
               "x-rate-limit-cost" => "abc",
               "x-rate-limit-limit" => "12abc",
               "x-rate-limit-retry-at" => "not-a-datetime"
             }) == %RateLimit{
               allowed: false,
               cost: nil,
               limit: 12,
               retry_at: nil
             }
    end

    test "distinguishes an absent report from a reported zero" do
      assert RateLimit.from_headers(%{"content-type" => ["application/json"]}) == nil
      assert RateLimit.from_headers([]) == nil

      assert RateLimit.from_headers(%{"x-rate-limit-remaining" => "0"}) == %RateLimit{
               remaining: 0
             }
    end
  end

  describe "from_extensions/1" do
    test "maps RATE_LIMITED extensions and marks the operation as rejected" do
      extensions = %{
        "code" => "RATE_LIMITED",
        "cost" => 138,
        "limit" => 500,
        "used" => 462,
        "remaining" => 38,
        "retryAt" => "2024-06-27T19:01:02.000Z"
      }

      assert RateLimit.from_extensions(extensions) == %RateLimit{
               allowed: false,
               cost: 138,
               limit: 500,
               used: 462,
               remaining: 38,
               retry_at: ~U[2024-06-27 19:01:02.000Z]
             }
    end

    test "ignores extensions that do not report rate limiting" do
      assert RateLimit.from_extensions(%{"code" => "UNAUTHENTICATED"}) == nil
      assert RateLimit.from_extensions(%{"remaining" => 0}) == nil
    end
  end

  property "header values round-trip across container shapes and header-name casing" do
    check all(
            allowed <- StreamData.boolean(),
            cost <- StreamData.non_negative_integer(),
            limit <- StreamData.non_negative_integer(),
            used <- StreamData.non_negative_integer(),
            remaining <- StreamData.non_negative_integer(),
            casing <- StreamData.member_of([:lower, :upper, :title])
          ) do
      pairs = [
        {"x-rate-limit-allowed", to_string(allowed)},
        {"x-rate-limit-cost", to_string(cost)},
        {"x-rate-limit-limit", to_string(limit)},
        {"x-rate-limit-used", to_string(used)},
        {"x-rate-limit-remaining", to_string(remaining)}
      ]

      expected = %RateLimit{
        allowed: allowed,
        cost: cost,
        limit: limit,
        used: used,
        remaining: remaining
      }

      cased_pairs = case_header_names(pairs, casing)

      for container_shape <- [:map_of_lists, :map_of_strings, :list_of_pairs] do
        assert cased_pairs |> header_container(container_shape) |> RateLimit.from_headers() == expected
      end
    end
  end

  property "a report exists exactly when at least one header is present" do
    check all(
            reported? <-
              StreamData.fixed_list(List.duplicate(StreamData.boolean(), length(@fields)))
          ) do
      reported_fields =
        @fields
        |> Enum.zip(reported?)
        |> Enum.filter(fn {_field, present?} -> present? end)
        |> Enum.map(fn {field, _present?} -> field end)

      values = %{
        allowed: "false",
        cost: "0",
        limit: "500",
        used: "17",
        remaining: "483",
        retry_at: "2024-06-27T19:01:02.000Z"
      }

      expected = %{
        allowed: false,
        cost: 0,
        limit: 500,
        used: 17,
        remaining: 483,
        retry_at: ~U[2024-06-27 19:01:02.000Z]
      }

      headers =
        Map.new(reported_fields, fn field ->
          {header_name(field), [Map.fetch!(values, field)]}
        end)

      rate_limit = RateLimit.from_headers(headers)

      assert is_nil(rate_limit) == Enum.empty?(reported_fields)

      if rate_limit do
        for field <- @fields do
          expected_value = if field in reported_fields, do: Map.fetch!(expected, field)
          assert Map.fetch!(rate_limit, field) == expected_value
        end
      end
    end
  end

  defp case_header_names(pairs, casing) do
    Enum.map(pairs, fn {name, value} -> {case_header_name(name, casing), value} end)
  end

  defp case_header_name(name, :lower), do: name
  defp case_header_name(name, :upper), do: String.upcase(name)

  defp case_header_name(name, :title) do
    name |> String.split("-") |> Enum.map_join("-", &String.capitalize/1)
  end

  defp header_container(pairs, :map_of_lists) do
    Map.new(pairs, fn {name, value} -> {name, [value]} end)
  end

  defp header_container(pairs, :map_of_strings), do: Map.new(pairs)
  defp header_container(pairs, :list_of_pairs), do: pairs

  defp header_name(:allowed), do: "x-rate-limit-allowed"
  defp header_name(:cost), do: "x-rate-limit-cost"
  defp header_name(:limit), do: "x-rate-limit-limit"
  defp header_name(:used), do: "x-rate-limit-used"
  defp header_name(:remaining), do: "x-rate-limit-remaining"
  defp header_name(:retry_at), do: "x-rate-limit-retry-at"
end
