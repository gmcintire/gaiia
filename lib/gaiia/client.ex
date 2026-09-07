defmodule Gaiia.Client do
  @moduledoc """
  HTTP client for the Gaiia GraphQL API.

  A `Gaiia.Client` is a lightweight, immutable struct holding the endpoint,
  optional API key, custom headers, and pass-through options forwarded
  to `Req`.

  Requests are `POST`ed to the endpoint with the key in the
  `X-Gaiia-Api-Key` header, as the API requires.

  ## Configuration

  Defaults can be supplied through application config:

      config :gaiia,
        endpoint: "https://api.gaiia.com/api/v1",
        api_key: System.get_env("GAIIA_API_KEY")

  ## Example

      client = Gaiia.Client.new()

      {:ok, %{"account" => account}} =
        Gaiia.Client.query(client, ~S\"""
        query($id: GlobalID!) {
          account(id: $id) { id name }
        }
        \""", %{"id" => "account_8rnXNuR5sKP5uNwoPL41Zp"})
  """

  alias Gaiia.Error
  alias Gaiia.RateLimit
  alias Gaiia.Response

  @default_endpoint "https://api.gaiia.com/api/v1"
  @api_key_header "x-gaiia-api-key"
  @timezone_header "x-timezone"

  @type t :: %__MODULE__{
          endpoint: String.t(),
          api_key: String.t() | nil,
          timezone: String.t() | nil,
          headers: [{String.t(), String.t()}],
          req_options: keyword()
        }

  @enforce_keys [:endpoint]
  defstruct endpoint: nil, api_key: nil, timezone: nil, headers: [], req_options: []

  @doc "The public Gaiia GraphQL endpoint, used when none is configured."
  @spec default_endpoint() :: String.t()
  def default_endpoint, do: @default_endpoint

  @doc """
  Build a new client.

  ## Options

    * `:endpoint`     — GraphQL endpoint URL. Defaults to the `:gaiia`
                         application env, then `default_endpoint/0`.
    * `:api_key`      — API key sent in the `X-Gaiia-Api-Key` header.
                         Defaults to the `:gaiia` application env. Without
                         one, the API answers every operation with an
                         `UNAUTHENTICATED` GraphQL error.
    * `:timezone`     — IANA identifier (e.g. `"America/Toronto"`) sent as
                         `x-timezone`. Scheduling, availability, and
                         work-order assignment operations resolve local day
                         boundaries with it; browsers send it automatically,
                         API integrations must set it. Defaults to the
                         `:gaiia` application env.
    * `:headers`      — Extra headers as `[{name, value}]`.
    * `:req_options`  — Keyword list of options forwarded to `Req.request/1`.
                         Useful for testing (`:adapter`, `:plug`) and tuning
                         (`:retry`, `:receive_timeout`, etc.).
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      endpoint: Keyword.get(opts, :endpoint) || Application.get_env(:gaiia, :endpoint) || @default_endpoint,
      api_key: Keyword.get(opts, :api_key, Application.get_env(:gaiia, :api_key)),
      timezone: Keyword.get(opts, :timezone, Application.get_env(:gaiia, :timezone)),
      headers: Keyword.get(opts, :headers, []),
      req_options: Keyword.get(opts, :req_options, Application.get_env(:gaiia, :req_options, []))
    }
  end

  @doc """
  Run a GraphQL query.

  Returns `{:ok, data}` on success, where `data` is the value of the
  `data` field in the GraphQL response. Returns `{:error, %Gaiia.Error{}}`
  on any failure mode.

  ## Options

    * `:operation_name` — GraphQL operation name to send (`operationName`).
    * `:timezone` — IANA identifier sent as `x-timezone`, overriding the
      client's own. Scheduling, availability, and work-order assignment
      operations resolve local day boundaries with it.
    * `:headers` — extra headers for this call only, as `[{name, value}]`.
  """
  @spec query(t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def query(%__MODULE__{} = client, query, variables \\ %{}, opts \\ []) do
    with {:ok, %Response{data: data}} <- request(client, query, variables, opts), do: {:ok, data}
  end

  @doc """
  Run a GraphQL mutation. Mechanically identical to `query/4` — provided
  for readability at call sites.
  """
  @spec mutate(t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def mutate(client, mutation, variables \\ %{}, opts \\ []), do: query(client, mutation, variables, opts)

  @doc """
  Run a GraphQL operation and keep the transport metadata.

  Same options as `query/4`, but returns a `Gaiia.Response` holding the
  data, the HTTP status, the response headers, and the rate-limit budget the
  API reported. Use this to throttle bulk work before the API rejects it.
  """
  @spec request(t(), String.t(), map(), keyword()) :: {:ok, Response.t()} | {:error, Error.t()}
  def request(%__MODULE__{} = client, query, variables \\ %{}, opts \\ []) do
    body = build_body(query, variables, opts)

    client
    |> build_request(body, opts)
    |> Req.request()
    |> handle_response()
  end

  ## ---- request construction ----

  @spec build_body(String.t(), map(), keyword()) :: map()
  defp build_body(query, variables, opts) do
    put_operation_name(%{"query" => query, "variables" => variables}, Keyword.get(opts, :operation_name))
  end

  defp put_operation_name(body, nil), do: body
  defp put_operation_name(body, name), do: Map.put(body, "operationName", name)

  @spec build_request(t(), map(), keyword()) :: Req.Request.t()
  defp build_request(%__MODULE__{} = client, body, opts) do
    [
      method: :post,
      url: client.endpoint,
      json: body,
      headers: headers_for(client, opts)
    ]
    |> Keyword.merge(client.req_options)
    |> Req.new()
  end

  defp headers_for(%__MODULE__{} = client, opts) do
    Keyword.get(opts, :headers, []) ++
      timezone_header(Keyword.get(opts, :timezone) || client.timezone) ++
      api_key_header(client.api_key) ++
      client.headers
  end

  defp api_key_header(nil), do: []
  defp api_key_header(key), do: [{@api_key_header, key}]

  defp timezone_header(nil), do: []
  defp timezone_header(timezone), do: [{@timezone_header, timezone}]

  ## ---- response handling ----

  @spec handle_response({:ok, Req.Response.t()} | {:error, Exception.t()}) ::
          {:ok, Response.t()} | {:error, Error.t()}
  defp handle_response({:ok, %Req.Response{status: status, body: body, headers: headers}}) when status in 200..299 do
    decode_graphql(body, status, headers)
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body, headers: headers}}) do
    {:error, Error.http(status, body, rate_limit: RateLimit.from_headers(headers))}
  end

  defp handle_response({:error, exception}), do: {:error, Error.network(exception)}

  defp decode_graphql(%{"errors" => [_ | _] = errors}, status, headers) do
    {:error, Error.graphql(errors, status: status, rate_limit: RateLimit.from_headers(headers))}
  end

  defp decode_graphql(%{"data" => data}, status, headers) do
    {:ok,
     %Response{
       data: data,
       status: status,
       rate_limit: RateLimit.from_headers(headers),
       headers: headers
     }}
  end

  defp decode_graphql(other, _status, _headers), do: {:error, Error.decode(other)}
end
