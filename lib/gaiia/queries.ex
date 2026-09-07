defmodule Gaiia.Queries do
  @moduledoc """
  Auto-generated functions for every query operation in the Gaiia
  GraphQL API.

  Each function has the signature:

      <name>(client, variables \\\\ %{}, selection \\\\ "", opts \\\\ [])
        :: {:ok, map() | term()} | {:error, Gaiia.Error.t()}

  Arguments:

    * `client` — a `Gaiia.Client` struct (build with `Gaiia.Client.new/1`)
    * `variables` — map of variables matching the GraphQL argument names
      (camelCase, string keys). Only keys present in this map are sent.
    * `selection` — selection-set body (no surrounding braces). Required
      for object return types; pass `""` for scalar return types.
    * `opts` — forwarded to `Gaiia.Client.query/4` (e.g. `:operation_name`)

  Return value is the contents of the named field, unwrapped from the
  `data` envelope — i.e. `Gaiia.Queries.account(client, %{"id" => id}, "id")`
  returns `{:ok, %{"id" => "..."}}`, not `{:ok, %{"account" => %{"id" => "..."}}}`.
  """

  alias Gaiia.Client
  alias Gaiia.Operation
  alias Gaiia.Schema

  for op <- Schema.queries() do
    @name op["name"]
    @fun_name Schema.function_name(@name)
    @args op["args"]
    @description Schema.description(op["description"] || "GraphQL query `#{@name}`.")

    @doc """
    #{@description}

    GraphQL: `query { #{@name} }`
    """
    @spec unquote(@fun_name)(Client.t(), map(), String.t(), keyword()) ::
            {:ok, term()} | {:error, Gaiia.Error.t()}
    def unquote(@fun_name)(client, variables \\ %{}, selection \\ "", opts \\ []) do
      operation = Operation.build(:query, unquote(@name), unquote(Macro.escape(@args)), variables, selection)

      with {:ok, data} <- Client.query(client, operation, variables, opts) do
        {:ok, Map.get(data, unquote(@name))}
      end
    end
  end
end
