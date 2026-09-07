defmodule Mix.Tasks.Gaiia.Introspect do
  @shortdoc "Refresh the bundled schema dumps from a live introspection query"

  @moduledoc """
  Regenerate the bundled Gaiia schema dumps from a live introspection query.

  The generated modules `Gaiia.Queries` and `Gaiia.Mutations` are built at
  compile time from `priv/queries.json` and `priv/mutations.json`, so the
  bundled dumps *are* the API surface: anything missing from them has no
  generated function. Run this task whenever Gaiia ships schema changes,
  then recompile.

      GAIIA_API_KEY=... mix gaiia.introspect

  ## Options

    * `--endpoint` — GraphQL endpoint (default `#{Gaiia.Client.default_endpoint()}`)
    * `--api-key` — API key; defaults to `$GAIIA_API_KEY`, then `$GAIIA_KEY`
    * `--raw PATH` — also write the untouched introspection response to `PATH`
    * `--check` — write nothing; exit non-zero if the dumps are out of date

  ## Output

    * `priv/queries.json`, `priv/mutations.json` — operation specs consumed at
      compile time. Only the keys the generators need, so the compiled literals
      stay small.
    * `docs/*.json` — flattened, human-readable dumps of every type in the
      schema (objects, input objects, enums, unions, interfaces, scalars) plus
      the root operations, with types rendered in GraphQL syntax.
  """

  use Mix.Task

  alias Gaiia.Client
  alias Gaiia.TypeRef

  @requirements ["app.start"]

  @type_ref """
  fragment TypeRef on __Type {
    kind
    name
    ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } }
  }
  """

  @query """
  query GaiiaIntrospection {
    __schema {
      queryType { name }
      mutationType { name }
      subscriptionType { name }
      directives { name description locations args { name description defaultValue type { ...TypeRef } } }
      types {
        kind
        name
        description
        fields(includeDeprecated: true) {
          name
          description
          isDeprecated
          deprecationReason
          args { name description defaultValue type { ...TypeRef } }
          type { ...TypeRef }
        }
        inputFields { name description defaultValue type { ...TypeRef } }
        interfaces { ...TypeRef }
        enumValues(includeDeprecated: true) { name description isDeprecated deprecationReason }
        possibleTypes { ...TypeRef }
      }
    }
  }
  #{@type_ref}
  """

  @impl Mix.Task
  def run(argv) do
    {opts, []} =
      OptionParser.parse!(argv,
        strict: [endpoint: :string, api_key: :string, raw: :string, check: :boolean]
      )

    schema = fetch_schema(opts)
    files = build_files(schema)

    if opts[:check], do: check(files), else: write(files, schema, opts)
  end

  ## ---- fetching ----

  defp fetch_schema(opts) do
    client =
      Client.new(
        endpoint: opts[:endpoint] || Client.default_endpoint(),
        api_key: api_key(opts)
      )

    case Client.query(client, @query) do
      {:ok, %{"__schema" => schema}} -> schema
      {:ok, other} -> Mix.raise("unexpected introspection payload: #{inspect(other)}")
      {:error, error} -> Mix.raise("introspection failed: " <> Exception.message(error))
    end
  end

  defp api_key(opts) do
    case opts[:api_key] || System.get_env("GAIIA_API_KEY") || System.get_env("GAIIA_KEY") do
      nil -> Mix.raise("no API key: pass --api-key or set GAIIA_API_KEY")
      key -> key
    end
  end

  ## ---- shaping ----

  defp build_files(schema) do
    types = Map.fetch!(schema, "types")
    by_name = Map.new(types, &{&1["name"], &1})
    root = fn key -> operations(by_name, schema[key]) end

    queries = root.("queryType")
    mutations = root.("mutationType")

    if schema["subscriptionType"] do
      Mix.shell().error("warning: schema now declares a subscription root; the client has no subscription support")
    end

    %{
      "priv/queries.json" => Enum.map(queries, &operation_spec/1),
      "priv/mutations.json" => Enum.map(mutations, &operation_spec/1),
      "docs/queries.json" => Enum.map(queries, &flat_operation/1),
      "docs/mutations.json" => Enum.map(mutations, &flat_operation/1),
      "docs/objects.json" => flat_fielded(types, "OBJECT"),
      "docs/interfaces.json" => flat_fielded(types, "INTERFACE"),
      "docs/inputs.json" => flat_inputs(types),
      "docs/enums.json" => flat_enums(types),
      "docs/unions.json" => flat_unions(types),
      "docs/scalars.json" => flat_scalars(types)
    }
  end

  defp operations(_by_name, nil), do: []

  defp operations(by_name, %{"name" => name}) do
    by_name |> Map.fetch!(name) |> Map.fetch!("fields") |> Enum.sort_by(& &1["name"])
  end

  # Keys the generators actually read, and nothing else: these become
  # compile-time literals in Gaiia.Queries/Gaiia.Mutations.
  defp operation_spec(field) do
    %{
      "name" => field["name"],
      "description" => field["description"],
      "isDeprecated" => field["isDeprecated"] || false,
      "deprecationReason" => field["deprecationReason"],
      "args" => Enum.map(field["args"] || [], &arg_spec/1),
      "type" => TypeRef.prune(field["type"])
    }
  end

  defp arg_spec(arg) do
    %{
      "name" => arg["name"],
      "description" => arg["description"],
      "defaultValue" => arg["defaultValue"],
      "type" => TypeRef.prune(arg["type"])
    }
  end

  ## ---- flattened human-readable dumps ----

  defp flat_operation(field) do
    drop_empty(%{
      "name" => field["name"],
      "description" => field["description"],
      "type" => TypeRef.render(field["type"]),
      "deprecationReason" => field["deprecationReason"],
      "args" => Enum.map(field["args"] || [], &flat_arg/1)
    })
  end

  defp flat_arg(arg) do
    drop_empty(%{
      "name" => arg["name"],
      "type" => TypeRef.render(arg["type"]),
      "default" => arg["defaultValue"],
      "description" => arg["description"]
    })
  end

  defp flat_fielded(types, kind) do
    types
    |> named(kind)
    |> Enum.map(fn type ->
      drop_empty(%{
        "name" => type["name"],
        "description" => type["description"],
        "interfaces" => Enum.map(type["interfaces"] || [], & &1["name"]),
        "fields" => Enum.map(type["fields"] || [], &flat_operation/1)
      })
    end)
  end

  defp flat_inputs(types) do
    types
    |> named("INPUT_OBJECT")
    |> Enum.map(fn type ->
      drop_empty(%{
        "name" => type["name"],
        "description" => type["description"],
        "fields" => Enum.map(type["inputFields"] || [], &flat_arg/1)
      })
    end)
  end

  defp flat_enums(types) do
    types
    |> named("ENUM")
    |> Enum.map(fn type ->
      drop_empty(%{
        "name" => type["name"],
        "description" => type["description"],
        "values" =>
          Enum.map(type["enumValues"] || [], fn value ->
            drop_empty(%{
              "name" => value["name"],
              "description" => value["description"],
              "deprecationReason" => value["deprecationReason"]
            })
          end)
      })
    end)
  end

  defp flat_unions(types) do
    types
    |> named("UNION")
    |> Enum.map(fn type ->
      drop_empty(%{
        "name" => type["name"],
        "description" => type["description"],
        "possibleTypes" => Enum.map(type["possibleTypes"] || [], & &1["name"])
      })
    end)
  end

  defp flat_scalars(types) do
    types
    |> named("SCALAR")
    |> Enum.map(&drop_empty(%{"name" => &1["name"], "description" => &1["description"]}))
  end

  defp named(types, kind) do
    types
    |> Enum.filter(&(&1["kind"] == kind and not String.starts_with?(&1["name"], "__")))
    |> Enum.sort_by(& &1["name"])
  end

  defp drop_empty(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) or value == [] end)
  end

  ## ---- writing ----

  defp write(files, schema, opts) do
    Enum.each(files, fn {path, contents} ->
      File.write!(path, encode(contents))
      Mix.shell().info("wrote #{path}")
    end)

    if raw = opts[:raw] do
      File.write!(raw, encode(%{"data" => %{"__schema" => schema}}))
      Mix.shell().info("wrote #{raw}")
    end

    Mix.shell().info(
      "#{length(files["priv/queries.json"])} queries, #{length(files["priv/mutations.json"])} mutations — recompile to regenerate the API surface"
    )
  end

  defp check(files) do
    stale = for {path, contents} <- files, File.read!(path) != encode(contents), do: path

    if stale == [] do
      Mix.shell().info("schema dumps are up to date")
    else
      Mix.raise("stale schema dumps: #{Enum.join(stale, ", ")} — run mix gaiia.introspect")
    end
  end

  defp encode(contents), do: Jason.encode!(contents, pretty: true) <> "\n"
end
