defmodule Gaiia do
  @moduledoc """
  Elixir client for the [Gaiia](https://gaiia.com) GraphQL API.

  The top-level `Gaiia` module is a thin convenience wrapper that
  builds an implicit client from application config:

      config :gaiia,
        endpoint: "https://api.gaiia.com/api/v1",
        api_key: System.get_env("GAIIA_API_KEY")

      Gaiia.query("query { account(id: $id) { id name } }", %{"id" => "..."})

  For per-call control over headers, request options, or to use multiple
  endpoints simultaneously, build a `Gaiia.Client` explicitly:

      client = Gaiia.Client.new(api_key: "...", headers: [{"x-trace-id", "abc"}])
      Gaiia.Client.query(client, "{ __typename }")
  """

  alias Gaiia.Client

  @doc "Run a GraphQL query using the default client built from app config."
  @spec query(String.t(), map(), keyword()) :: {:ok, map()} | {:error, Gaiia.Error.t()}
  def query(query, variables \\ %{}, opts \\ []), do: Client.query(default_client(), query, variables, opts)

  @doc "Run a GraphQL mutation using the default client built from app config."
  @spec mutate(String.t(), map(), keyword()) :: {:ok, map()} | {:error, Gaiia.Error.t()}
  def mutate(mutation, variables \\ %{}, opts \\ []), do: Client.mutate(default_client(), mutation, variables, opts)

  @doc """
  Run a GraphQL operation with the default client, keeping the transport
  metadata (rate-limit budget, status, headers) in a `Gaiia.Response`.
  """
  @spec request(String.t(), map(), keyword()) :: {:ok, Gaiia.Response.t()} | {:error, Gaiia.Error.t()}
  def request(query, variables \\ %{}, opts \\ []), do: Client.request(default_client(), query, variables, opts)

  @doc "Build a default client from application config."
  @spec default_client() :: Client.t()
  def default_client, do: Client.new()
end
