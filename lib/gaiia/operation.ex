defmodule Gaiia.Operation do
  @moduledoc """
  Build GraphQL operation strings from introspection-style argument specs
  at runtime.

  Operations have shape:

      <op_type> <op_name>($a: T!, $b: U) { <op_name>(a: $a, b: $b) { <selection> } }

  Only variables that the caller actually supplies are declared and passed,
  so GraphQL doesn't reject the request for unused variables.
  """

  alias Gaiia.TypeRef

  @type op_type :: :query | :mutation
  @type arg_spec :: %{required(String.t()) => term()}

  @doc """
  Build a GraphQL operation string.

    * `op_type` — `:query` or `:mutation`
    * `name` — the operation/field name (e.g. `"account"`)
    * `args` — list of argument specs `[%{"name" => "id", "type" => type_ref}, ...]`
    * `variables` — variables map; only keys present here are declared/passed
    * `selection` — selection set body (without braces). Empty string means no selection.
  """
  @spec build(op_type(), String.t(), [arg_spec()], map(), String.t()) :: String.t()
  def build(op_type, name, args, variables, selection) do
    used = filter_used_args(args, variables)
    "#{keyword(op_type)} #{name}#{declarations(used)} { #{name}#{call_args(used)}#{selection_block(selection)} }"
  end

  defp keyword(:query), do: "query"
  defp keyword(:mutation), do: "mutation"

  defp filter_used_args(args, variables) do
    Enum.filter(args, fn %{"name" => name} -> Map.has_key?(variables, name) end)
  end

  defp declarations([]), do: ""

  defp declarations(args) do
    "(" <> Enum.map_join(args, ", ", fn %{"name" => n, "type" => t} -> "$#{n}: #{TypeRef.render(t)}" end) <> ")"
  end

  defp call_args([]), do: ""

  defp call_args(args) do
    "(" <> Enum.map_join(args, ", ", fn %{"name" => n} -> "#{n}: $#{n}" end) <> ")"
  end

  defp selection_block(""), do: ""
  defp selection_block(selection), do: " { " <> selection <> " }"
end
