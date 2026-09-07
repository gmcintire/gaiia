defmodule Gaiia.RateLimit do
  @moduledoc """
  Rate-limit accounting reported by the Gaiia API.

  Limits are query-cost based, not request based: each API key has a point
  bucket, every operation removes its calculated cost, and points refill over
  time. Every response reports the bucket state in `x-rate-limit-*` headers,
  and a rejected operation additionally reports it in the `extensions` of a
  `RATE_LIMITED` GraphQL error.

  Read `remaining` and `retry_at` to throttle before being rejected — the
  documented limits are not fixed, so they cannot be hardcoded by a client.

  Both `Gaiia.Response` and `Gaiia.Error` carry this struct when the API
  reported it.
  """

  @type t :: %__MODULE__{
          allowed: boolean() | nil,
          cost: integer() | nil,
          limit: integer() | nil,
          used: integer() | nil,
          remaining: integer() | nil,
          retry_at: DateTime.t() | nil
        }

  defstruct [:allowed, :cost, :limit, :used, :remaining, :retry_at]

  @doc """
  Build a rate-limit struct from response headers.

  Returns `nil` when the response carries no `x-rate-limit-*` header, so
  callers can distinguish "not reported" from "reported as zero".
  """
  @spec from_headers(map() | [{String.t(), String.t()}]) :: t() | nil
  def from_headers(headers) do
    headers = normalize(headers)

    values = %{
      allowed: parse_boolean(headers["x-rate-limit-allowed"]),
      cost: parse_integer(headers["x-rate-limit-cost"]),
      limit: parse_integer(headers["x-rate-limit-limit"]),
      used: parse_integer(headers["x-rate-limit-used"]),
      remaining: parse_integer(headers["x-rate-limit-remaining"]),
      retry_at: parse_datetime(headers["x-rate-limit-retry-at"])
    }

    if Enum.all?(values, fn {_key, value} -> is_nil(value) end), do: nil, else: struct(__MODULE__, values)
  end

  @doc """
  Build a rate-limit struct from the `extensions` of a `RATE_LIMITED`
  GraphQL error.

  Such an operation was rejected, so `allowed` is `false`.
  """
  @spec from_extensions(map()) :: t() | nil
  def from_extensions(%{"code" => "RATE_LIMITED"} = extensions) do
    %__MODULE__{
      allowed: false,
      cost: parse_integer(extensions["cost"]),
      limit: parse_integer(extensions["limit"]),
      used: parse_integer(extensions["used"]),
      remaining: parse_integer(extensions["remaining"]),
      retry_at: parse_datetime(extensions["retryAt"])
    }
  end

  def from_extensions(_extensions), do: nil

  # Req normalizes headers to a `%{name => [value]}` map, but a hand-built
  # response or a raw adapter may still hand over a list of pairs.
  defp normalize(headers), do: Map.new(headers, fn {name, value} -> {String.downcase(name), first(value)} end)

  defp first([value | _rest]), do: value
  defp first(value), do: value

  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(value) when is_boolean(value), do: value
  defp parse_boolean(_value), do: nil

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, _rest} -> integer
      :error -> nil
    end
  end

  defp parse_integer(_value), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp parse_datetime(_value), do: nil
end
