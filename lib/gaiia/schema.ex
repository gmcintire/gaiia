defmodule Gaiia.Schema do
  @moduledoc """
  Compile-time access to the Gaiia GraphQL schema.

  At compile time this module loads the operation specs from
  `priv/queries.json` and `priv/mutations.json` (extracted from the
  full introspection schema) so generator modules can iterate over
  every operation.
  """

  alias Gaiia.TypeRef

  @queries_path :gaiia |> :code.priv_dir() |> to_string() |> Path.join("queries.json")
  @mutations_path :gaiia |> :code.priv_dir() |> to_string() |> Path.join("mutations.json")

  # The compile-time-loaded literals would force dialyzer to infer the
  # full nested map shape; we keep these specless so callers can treat
  # them as the opaque "introspection envelope" they are.

  @external_resource @queries_path
  @external_resource @mutations_path

  @queries @queries_path |> File.read!() |> Jason.decode!()
  @mutations @mutations_path |> File.read!() |> Jason.decode!()

  @doc "Return the list of all query operation specs."
  def queries, do: @queries

  @doc "Return the list of all mutation operation specs."
  def mutations, do: @mutations

  @doc "Convert a camelCase GraphQL name to an Elixir-friendly snake_case atom."
  @spec function_name(String.t()) :: atom()
  def function_name(camel_name), do: camel_name |> Macro.underscore() |> String.to_atom()

  @doc """
  Build the `@doc` body for a generated operation function.

  Carries the schema's own description, the GraphQL operation it wraps, and
  a table of every argument with its rendered GraphQL type and default.
  """
  @spec doc(map(), :query | :mutation) :: String.t()
  def doc(op, op_type) do
    name = op["name"]
    text = description(op["description"] || "GraphQL #{op_type} `#{name}`.")

    IO.iodata_to_binary([text, "\n\nGraphQL: `", to_string(op_type), " { ", name, " }`\n", args_doc(op["args"] || [])])
  end

  defp args_doc([]), do: "\nTakes no arguments.\n"

  defp args_doc(args), do: ["\n## Arguments\n\n", Enum.map(args, &arg_doc/1)]

  defp arg_doc(arg) do
    [
      "  * `",
      arg["name"],
      "` — `",
      TypeRef.render(arg["type"]),
      "`",
      default_doc(arg["defaultValue"]),
      arg_description(arg["description"]),
      "\n"
    ]
  end

  defp default_doc(nil), do: ""
  defp default_doc(default), do: [", default `", default, "`"]

  defp arg_description(nil), do: ""
  defp arg_description(text), do: [" — ", text |> description() |> String.replace(~r/\s+/, " ") |> String.trim()]

  @doc """
  Normalize a schema description for use in `@doc`.

  Descriptions are written for Gaiia's own documentation site and contain
  site-relative markdown links such as `[Files](../../files)`. Those targets
  do not exist here, so ExDoc resolves them as broken file references. Links
  with a relative target collapse to their label as inline code; absolute
  links are left intact.
  """
  @spec description(String.t()) :: String.t()
  def description(text), do: Regex.replace(~r/\[([^\]]+)\]\((?!https?:\/\/)[^)]*\)/, text, "`\\1`")
end
