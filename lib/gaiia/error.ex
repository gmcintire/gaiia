defmodule Gaiia.Error do
  @moduledoc """
  Structured error returned by `Gaiia.Client` calls.

  The `:kind` discriminates the failure mode so callers can pattern match
  rather than parse messages:

    * `:graphql` — the server returned a 200 with one or more entries in `errors`
    * `:http`    — the server returned a non-2xx HTTP response
    * `:network` — the request never reached the server (connection refused, DNS, etc.)
    * `:decode`  — the response was 2xx but the body was not a valid GraphQL envelope

  Most Gaiia failures are `:graphql` at HTTP 200 — authentication, validation,
  and rate limiting all arrive that way. `:code` carries the first error's
  `extensions.code` (e.g. `"UNAUTHENTICATED"`, `"RATE_LIMITED"`) so callers
  can branch without digging through `:errors`, and `:rate_limit` carries the
  budget the API reported.

  Expected mutation failures are *not* errors: they come back inside the
  mutation payload as `%{"errors" => [%{"code" => ..., "message" => ...}]}`
  in an `{:ok, data}` result, and callers must inspect them there.
  """

  alias Gaiia.RateLimit

  @type kind :: :graphql | :http | :network | :decode

  @type t :: %__MODULE__{
          kind: kind(),
          message: String.t(),
          code: String.t() | nil,
          status: pos_integer() | nil,
          errors: [map()] | nil,
          rate_limit: RateLimit.t() | nil,
          details: term()
        }

  @enforce_keys [:kind, :message]
  defexception [:kind, :message, :code, :status, :errors, :rate_limit, :details]

  @doc """
  Build a `:graphql` error from a list of GraphQL error maps.

  Options: `:status` and `:rate_limit`, both taken from the HTTP response.
  """
  @spec graphql([map()], keyword()) :: t()
  def graphql(errors, opts \\ []) when is_list(errors) do
    extensions = extensions(errors)

    %__MODULE__{
      kind: :graphql,
      message: "GraphQL error: " <> format_graphql_messages(errors),
      code: extensions["code"],
      status: Keyword.get(opts, :status),
      errors: errors,
      rate_limit: Keyword.get(opts, :rate_limit) || RateLimit.from_extensions(extensions)
    }
  end

  @doc """
  Build an `:http` error from a status code and response body.

  Options: `:rate_limit`, taken from the HTTP response.
  """
  @spec http(pos_integer(), term(), keyword()) :: t()
  def http(status, body, opts \\ []) when is_integer(status) do
    %__MODULE__{
      kind: :http,
      message: "HTTP #{status} from Gaiia API",
      status: status,
      rate_limit: Keyword.get(opts, :rate_limit),
      details: body
    }
  end

  @doc "Build a `:network` error from a transport-layer exception."
  @spec network(Exception.t() | term()) :: t()
  def network(%{__exception__: true} = exception) do
    %__MODULE__{
      kind: :network,
      message: "Network error: " <> Exception.message(exception),
      details: exception
    }
  end

  def network(other) do
    %__MODULE__{
      kind: :network,
      message: "Network error: " <> inspect(other),
      details: other
    }
  end

  @doc "Build a `:decode` error from an undecodable response body."
  @spec decode(term()) :: t()
  def decode(body) do
    %__MODULE__{
      kind: :decode,
      message: "Could not decode Gaiia response body",
      details: body
    }
  end

  defp format_graphql_messages([]), do: "<no message>"

  defp format_graphql_messages(errors) do
    Enum.map_join(errors, "; ", &Map.get(&1, "message", "<no message>"))
  end

  defp extensions([%{"extensions" => %{} = extensions} | _rest]), do: extensions
  defp extensions(_errors), do: %{}
end
