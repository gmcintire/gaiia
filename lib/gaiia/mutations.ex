defmodule Gaiia.Mutations do
  @moduledoc """
  Auto-generated functions for every mutation operation in the Gaiia
  GraphQL API.

  Signature, semantics, and return-value handling are identical to
  `Gaiia.Queries` — see that module for details.
  """

  alias Gaiia.Client
  alias Gaiia.Operation
  alias Gaiia.Schema

  for op <- Schema.mutations() do
    @name op["name"]
    @fun_name Schema.function_name(@name)
    @args op["args"]

    @doc Schema.doc(op, :mutation)

    if op["isDeprecated"] do
      @deprecated Schema.description(op["deprecationReason"] || "Deprecated in the Gaiia schema.")
    end

    @spec unquote(@fun_name)(Client.t(), map(), String.t(), keyword()) ::
            {:ok, term()} | {:error, Gaiia.Error.t()}
    def unquote(@fun_name)(client, variables \\ %{}, selection \\ "", opts \\ []) do
      operation = Operation.build(:mutation, unquote(@name), unquote(Macro.escape(@args)), variables, selection)

      with {:ok, data} <- Client.mutate(client, operation, variables, opts) do
        {:ok, Map.get(data, unquote(@name))}
      end
    end
  end
end
