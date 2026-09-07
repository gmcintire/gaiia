defmodule Gaiia.Client do
  @moduledoc """
  HTTP client for the Gaiia GraphQL API.

  A `Gaiia.Client` is a lightweight, immutable struct holding the endpoint,
  optional bearer token, custom headers, and pass-through options forwarded
  to `Req`.

  ## Configuration

  Defaults can be supplied through application config:

      config :gaiia,
        endpoint: "https://api.gaiia.com/graphql",
        token: System.get_env("GAIIA_TOKEN")

  ## Example

      client = Gaiia.Client.new()

      {:ok, %{"account" => account}} =
        Gaiia.Client.query(client, ~S\"\"\"
        query($id: GlobalID!) {
          account(id: $id) { id name }
        }
        \"\"\", %{"id" => "account_8rnXNuR5sKP5uNwoPL41Zp"})
  """

  alias Gaiia.Error

  @type t :: %__MODULE__{
          endpoint: String.t(),
          token: String.t() | nil,
          headers: [{String.t(), String.t()}],
          req_options: keyword()
        }

  @enforce_keys [:endpoint]
  defstruct endpoint: nil, token: nil, headers: [], req_options: []

  @doc """
  Build a new client.

  ## Options

    * `:endpoint`     — Base GraphQL endpoint URL. Required unless set in app env.
    * `:token`        — Bearer token sent in the `Authorization` header.
    * `:headers`      — Extra headers as `[{name, value}]`.
    * `:req_options`  — Keyword list of options forwarded to `Req.request/1`.
                         Useful for testing (`:adapter`, `:plug`) and tuning
                         (`:retry`, `:receive_timeout`, etc.).

  Raises `ArgumentError` when no endpoint can be resolved.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    endpoint = fetch_required(opts, :endpoint)

    %__MODULE__{
      endpoint: endpoint,
      token: Keyword.get(opts, :token, Application.get_env(:gaiia, :token)),
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
  """
  @spec query(t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def query(%__MODULE__{} = client, query, variables \\ %{}, opts \\ []) do
    body = build_body(query, variables, opts)

    client
    |> build_request(body)
    |> Req.request()
    |> handle_response()
  end

  @doc """
  Run a GraphQL mutation. Mechanically identical to `query/4` — provided
  for readability at call sites.
  """
  @spec mutate(t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def mutate(client, mutation, variables \\ %{}, opts \\ []), do: query(client, mutation, variables, opts)

  ## ---- request construction ----

  @spec build_body(String.t(), map(), keyword()) :: map()
  defp build_body(query, variables, opts) do
    put_operation_name(%{"query" => query, "variables" => variables}, Keyword.get(opts, :operation_name))
  end

  defp put_operation_name(body, nil), do: body
  defp put_operation_name(body, name), do: Map.put(body, "operationName", name)

  @spec build_request(t(), map()) :: Req.Request.t()
  defp build_request(%__MODULE__{} = client, body) do
    [
      method: :post,
      url: client.endpoint,
      json: body,
      headers: headers_for(client)
    ]
    |> Keyword.merge(client.req_options)
    |> Req.new()
  end

  defp headers_for(%__MODULE__{token: nil, headers: extra}), do: extra
  defp headers_for(%__MODULE__{token: token, headers: extra}), do: [{"authorization", "Bearer " <> token} | extra]

  ## ---- response handling ----

  @spec handle_response({:ok, Req.Response.t()} | {:error, Exception.t()}) ::
          {:ok, map()} | {:error, Error.t()}
  defp handle_response({:ok, %Req.Response{status: status, body: body}}) when status in 200..299, do: decode_graphql(body)

  defp handle_response({:ok, %Req.Response{status: status, body: body}}), do: {:error, Error.http(status, body)}

  defp handle_response({:error, exception}), do: {:error, Error.network(exception)}

  defp decode_graphql(%{"errors" => [_ | _] = errors}), do: {:error, Error.graphql(errors)}
  defp decode_graphql(%{"data" => data}), do: {:ok, data}
  defp decode_graphql(other), do: {:error, Error.decode(other)}

  ## ---- option resolution ----

  defp fetch_required(opts, key) do
    case Keyword.get(opts, key, Application.get_env(:gaiia, key)) do
      nil -> raise ArgumentError, "missing required Gaiia.Client option: #{inspect(key)}"
      value -> value
    end
  end
end
