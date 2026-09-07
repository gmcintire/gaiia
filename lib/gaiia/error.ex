defmodule Gaiia.Error do
  @moduledoc """
  Structured error returned by `Gaiia.Client` calls.

  The `:kind` discriminates the failure mode so callers can pattern match
  rather than parse messages:

    * `:graphql` — the server returned a 200 with one or more entries in `errors`
    * `:http`    — the server returned a non-2xx HTTP response
    * `:network` — the request never reached the server (connection refused, DNS, etc.)
    * `:decode`  — the response was 2xx but the body was not a valid GraphQL envelope
  """

  @type kind :: :graphql | :http | :network | :decode

  @type t :: %__MODULE__{
          kind: kind(),
          message: String.t(),
          status: pos_integer() | nil,
          errors: [map()] | nil,
          details: term()
        }

  @enforce_keys [:kind, :message]
  defexception [:kind, :message, :status, :errors, :details]

  @doc "Build a `:graphql` error from a list of GraphQL error maps."
  @spec graphql([map()]) :: t()
  def graphql(errors) when is_list(errors) do
    %__MODULE__{
      kind: :graphql,
      message: "GraphQL error: " <> format_graphql_messages(errors),
      errors: errors
    }
  end

  @doc "Build an `:http` error from a status code and response body."
  @spec http(pos_integer(), term()) :: t()
  def http(status, body) when is_integer(status) do
    %__MODULE__{
      kind: :http,
      message: "HTTP #{status} from Gaiia API",
      status: status,
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
end
