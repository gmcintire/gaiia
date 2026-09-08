defmodule Mix.Tasks.Gaiia.IntrospectTest do
  use ExUnit.Case, async: false

  alias Gaiia.Client
  alias Gaiia.ReqStub
  alias Mix.Tasks.Gaiia.Introspect

  @endpoint "http://127.0.0.1:1/graphql"
  @api_key_env ~w(GAIIA_API_KEY GAIIA_KEY)
  @dump_paths ~w(
    priv/queries.json
    priv/mutations.json
    docs/queries.json
    docs/mutations.json
    docs/objects.json
    docs/interfaces.json
    docs/inputs.json
    docs/enums.json
    docs/unions.json
    docs/scalars.json
  )

  setup do
    original_cwd = File.cwd!()
    original_shell = Mix.shell()
    original_env = Map.new(@api_key_env, &{&1, System.get_env(&1)})
    # The task builds its own client, so the stub transport can only be reached
    # through application config. Pin it here instead of relying on the value
    # `test_helper.exs` set, which another test may have replaced.
    original_req_options = Application.fetch_env(:gaiia, :req_options)
    tmp = Path.join(System.tmp_dir!(), "gaiia-introspect-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(tmp, "priv"))
    File.mkdir_p!(Path.join(tmp, "docs"))

    on_exit(fn ->
      File.cd!(original_cwd)
      File.rm_rf!(tmp)
      Mix.shell(original_shell)

      case original_req_options do
        {:ok, value} -> Application.put_env(:gaiia, :req_options, value)
        :error -> Application.delete_env(:gaiia, :req_options)
      end

      Enum.each(original_env, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    Enum.each(@api_key_env, &System.delete_env/1)
    Application.put_env(:gaiia, :req_options, ReqStub.options())
    Mix.shell(Mix.Shell.Process)
    File.cd!(tmp)

    %{tmp: tmp}
  end

  test "default run writes the complete shaped schema and sends the explicit API key" do
    System.put_env("GAIIA_API_KEY", "environment-key")
    System.put_env("GAIIA_KEY", "legacy-key")
    install_schema(schema())

    Introspect.run(["--endpoint", @endpoint, "--api-key", "cli-key"])

    request = ReqStub.captured()
    assert to_string(request.url) == @endpoint
    assert ReqStub.captured_headers()["x-gaiia-api-key"] == ["cli-key"]
    assert ReqStub.captured_query() =~ "query GaiiaIntrospection"
    assert ReqStub.captured_query() =~ "__schema"
    assert ReqStub.captured_query() =~ "fragment TypeRef on __Type"

    info = shell_messages(:info)
    summary = "2 queries, 1 mutations — recompile to regenerate the API surface"
    assert List.last(info) == summary

    assert info |> Enum.drop(-1) |> MapSet.new() ==
             MapSet.new(@dump_paths, &"wrote #{&1}")

    Enum.each(@dump_paths, fn path ->
      contents = File.read!(path)
      decoded = Jason.decode!(contents)

      assert contents == Jason.encode!(decoded, pretty: true) <> "\n"
      assert contents |> String.trim_trailing("\n") |> String.contains?("\n")
    end)

    queries = read_json("priv/queries.json")

    assert Enum.map(queries, & &1["name"]) == ["account", "viewer"]
    assert Enum.all?(queries, &(&1 |> Map.keys() |> Enum.sort() == operation_keys()))

    assert [account, viewer] = queries
    assert account["isDeprecated"] == false
    assert account["deprecationReason"] == nil

    assert account["type"] == %{
             "kind" => "OBJECT",
             "name" => "Account",
             "ofType" => nil
           }

    assert account["args"] == [
             %{
               "defaultValue" => nil,
               "description" => "Account identifier",
               "name" => "id",
               "type" => %{
                 "kind" => "NON_NULL",
                 "name" => nil,
                 "ofType" => %{"kind" => "SCALAR", "name" => "GlobalID", "ofType" => nil}
               }
             },
             %{
               "defaultValue" => "[]",
               "description" => nil,
               "name" => "labels",
               "type" => %{
                 "kind" => "LIST",
                 "name" => nil,
                 "ofType" => %{
                   "kind" => "NON_NULL",
                   "name" => nil,
                   "ofType" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil}
                 }
               }
             }
           ]

    assert viewer["args"] == []
    assert viewer["isDeprecated"] == false

    assert read_json("priv/mutations.json") == [
             %{
               "args" => [],
               "deprecationReason" => "Use updateAccount",
               "description" => nil,
               "isDeprecated" => true,
               "name" => "archiveAccount",
               "type" => %{"kind" => "OBJECT", "name" => "Account", "ofType" => nil}
             }
           ]

    assert read_json("docs/queries.json") == [
             %{
               "args" => [
                 %{"description" => "Account identifier", "name" => "id", "type" => "GlobalID!"},
                 %{"default" => "[]", "name" => "labels", "type" => "[String!]"}
               ],
               "description" => "Find an account",
               "name" => "account",
               "type" => "Account"
             },
             %{"name" => "viewer", "type" => "Account"}
           ]

    assert read_json("docs/mutations.json") == [
             %{
               "deprecationReason" => "Use updateAccount",
               "name" => "archiveAccount",
               "type" => "Account"
             }
           ]

    objects = read_json("docs/objects.json")
    assert Enum.map(objects, & &1["name"]) == ["Account", "Mutation", "Query"]

    assert hd(objects) == %{
             "description" => "Customer account",
             "fields" => [%{"name" => "id", "type" => "GlobalID!"}],
             "interfaces" => ["Node"],
             "name" => "Account"
           }

    assert objects |> List.last() |> Map.fetch!("fields") |> Enum.map(& &1["name"]) == [
             "viewer",
             "account"
           ]

    assert read_json("docs/interfaces.json") == [
             %{
               "description" => "An identifiable resource",
               "fields" => [%{"name" => "id", "type" => "GlobalID!"}],
               "name" => "Node"
             }
           ]

    assert read_json("docs/inputs.json") == [
             %{
               "fields" => [
                 %{
                   "default" => "ACTIVE",
                   "description" => "Status to match",
                   "name" => "status",
                   "type" => "Status"
                 }
               ],
               "name" => "AccountFilter"
             }
           ]

    assert read_json("docs/enums.json") == [
             %{
               "description" => "Account lifecycle",
               "name" => "Status",
               "values" => [
                 %{"description" => "Usable", "name" => "ACTIVE"},
                 %{
                   "deprecationReason" => "No longer assigned",
                   "description" => "Old status",
                   "name" => "LEGACY"
                 }
               ]
             }
           ]

    assert read_json("docs/unions.json") == [
             %{"name" => "SearchResult", "possibleTypes" => ["Account"]}
           ]

    scalars = read_json("docs/scalars.json")
    assert scalars == [%{"name" => "GlobalID"}, %{"description" => "Text", "name" => "String"}]
    refute Enum.any?(scalars, &String.starts_with?(&1["name"], "__"))
  end

  test "GAIIA_API_KEY is used before the legacy key and the endpoint defaults to the public endpoint" do
    System.put_env("GAIIA_API_KEY", "primary-key")
    System.put_env("GAIIA_KEY", "legacy-key")
    install_schema(schema())

    Introspect.run([])

    assert to_string(ReqStub.captured().url) == Client.default_endpoint()
    assert ReqStub.captured_headers()["x-gaiia-api-key"] == ["primary-key"]
  end

  test "GAIIA_KEY is used when GAIIA_API_KEY is absent" do
    System.put_env("GAIIA_KEY", "legacy-key")
    install_schema(schema())

    Introspect.run([])

    assert ReqStub.captured_headers()["x-gaiia-api-key"] == ["legacy-key"]
  end

  test "a missing API key raises before making a request" do
    install_schema(schema())

    assert_raise Mix.Error, ~r/no API key: pass --api-key or set GAIIA_API_KEY/, fn ->
      Introspect.run([])
    end

    assert ReqStub.captured() == nil
  end

  test "--raw writes and logs the untouched introspection envelope" do
    fixture = schema()
    install_schema(fixture)

    Introspect.run(["--api-key", "key", "--raw", "docs/raw-response.json"])

    expected = %{"data" => %{"__schema" => fixture}}

    assert File.read!("docs/raw-response.json") == Jason.encode!(expected, pretty: true) <> "\n"
    assert "wrote docs/raw-response.json" in shell_messages(:info)
  end

  test "--check reports matching read-only dumps as current without touching them" do
    install_schema(schema())
    Introspect.run(["--api-key", "key"])
    _ = shell_messages(:info)

    Enum.each(@dump_paths, &File.chmod!(&1, 0o444))
    before = Map.new(@dump_paths, &{&1, File.read!(&1)})

    Introspect.run(["--api-key", "key", "--check"])

    assert shell_messages(:info) == ["schema dumps are up to date"]
    assert Map.new(@dump_paths, &{&1, File.read!(&1)}) == before
  end

  test "--check raises with every stale dump path" do
    install_schema(schema())
    Introspect.run(["--api-key", "key"])
    File.write!("priv/queries.json", "stale\n")

    error =
      assert_raise Mix.Error, fn ->
        Introspect.run(["--api-key", "key", "--check"])
      end

    assert Exception.message(error) =~ "stale schema dumps: priv/queries.json"
    assert Exception.message(error) =~ "run mix gaiia.introspect"
    assert File.read!("priv/queries.json") == "stale\n"
  end

  test "a subscription root warns and a null mutation root produces no mutations" do
    fixture = %{schema() | "mutationType" => nil, "subscriptionType" => %{"name" => "Subscription"}}
    install_schema(fixture)

    Introspect.run(["--api-key", "key"])

    assert read_json("priv/mutations.json") == []

    assert shell_messages(:error) == [
             "warning: schema now declares a subscription root; the client has no subscription support"
           ]

    assert "2 queries, 0 mutations — recompile to regenerate the API surface" in shell_messages(:info)
  end

  test "an unexpected successful payload raises a Mix error" do
    ReqStub.install(fn _request -> ReqStub.ok_response(%{"data" => %{"version" => 1}}) end)

    assert_raise Mix.Error, ~r/unexpected introspection payload: .*version/, fn ->
      Introspect.run(["--api-key", "key"])
    end
  end

  test "a GraphQL failure raises a Mix error containing the Gaiia error message" do
    ReqStub.install(fn _request ->
      ReqStub.ok_response(%{"errors" => [%{"message" => "introspection denied"}]})
    end)

    assert_raise Mix.Error, ~r/introspection failed: .*introspection denied/, fn ->
      Introspect.run(["--api-key", "key"])
    end
  end

  defp schema do
    %{
      "queryType" => %{"name" => "Query"},
      "mutationType" => %{"name" => "Mutation"},
      "subscriptionType" => nil,
      "directives" => [%{"name" => "skip"}],
      "types" => [
        %{
          "kind" => "OBJECT",
          "name" => "Query",
          "description" => nil,
          "interfaces" => [],
          "fields" => [
            operation("viewer", named_ref("OBJECT", "Account"), args: nil),
            operation("account", named_ref("OBJECT", "Account"),
              description: "Find an account",
              args: [
                argument("id", non_null(named_ref("SCALAR", "GlobalID")), description: "Account identifier"),
                argument("labels", list(non_null(named_ref("SCALAR", "String"))), default: "[]")
              ]
            )
          ]
        },
        %{
          "kind" => "OBJECT",
          "name" => "Mutation",
          "description" => "Mutation root",
          "interfaces" => nil,
          "fields" => [
            operation("archiveAccount", named_ref("OBJECT", "Account"),
              deprecated: true,
              reason: "Use updateAccount"
            )
          ]
        },
        %{
          "kind" => "OBJECT",
          "name" => "Account",
          "description" => "Customer account",
          "interfaces" => [named_ref("INTERFACE", "Node")],
          "fields" => [operation("id", non_null(named_ref("SCALAR", "GlobalID")), args: nil)]
        },
        %{
          "kind" => "INTERFACE",
          "name" => "Node",
          "description" => "An identifiable resource",
          "interfaces" => nil,
          "fields" => [operation("id", non_null(named_ref("SCALAR", "GlobalID")))]
        },
        %{
          "kind" => "INPUT_OBJECT",
          "name" => "AccountFilter",
          "description" => nil,
          "inputFields" => [
            argument("status", named_ref("ENUM", "Status"),
              default: "ACTIVE",
              description: "Status to match"
            )
          ]
        },
        %{
          "kind" => "ENUM",
          "name" => "Status",
          "description" => "Account lifecycle",
          "enumValues" => [
            %{
              "name" => "ACTIVE",
              "description" => "Usable",
              "isDeprecated" => false,
              "deprecationReason" => nil
            },
            %{
              "name" => "LEGACY",
              "description" => "Old status",
              "isDeprecated" => true,
              "deprecationReason" => "No longer assigned"
            }
          ]
        },
        %{
          "kind" => "UNION",
          "name" => "SearchResult",
          "description" => nil,
          "possibleTypes" => [named_ref("OBJECT", "Account")]
        },
        %{"kind" => "SCALAR", "name" => "String", "description" => "Text"},
        %{"kind" => "SCALAR", "name" => "GlobalID", "description" => nil},
        %{"kind" => "SCALAR", "name" => "__Hidden", "description" => "Introspection metadata"}
      ]
    }
  end

  defp operation(name, type, opts \\ []) do
    field = %{
      "name" => name,
      "description" => Keyword.get(opts, :description),
      "deprecationReason" => Keyword.get(opts, :reason),
      "args" => Keyword.get(opts, :args, []),
      "type" => type,
      "ignored" => "not part of a dump"
    }

    if Keyword.has_key?(opts, :deprecated),
      do: Map.put(field, "isDeprecated", Keyword.fetch!(opts, :deprecated)),
      else: field
  end

  defp argument(name, type, opts) do
    %{
      "name" => name,
      "description" => Keyword.get(opts, :description),
      "defaultValue" => Keyword.get(opts, :default),
      "type" => type,
      "ignored" => "not part of a dump"
    }
  end

  defp named_ref(kind, name) do
    %{
      "kind" => kind,
      "name" => name,
      "ofType" => nil,
      "description" => "discarded from generated operation specs"
    }
  end

  defp non_null(inner) do
    %{"kind" => "NON_NULL", "name" => nil, "ofType" => inner, "__typename" => "__Type"}
  end

  defp list(inner) do
    %{"kind" => "LIST", "name" => nil, "ofType" => inner, "__typename" => "__Type"}
  end

  defp install_schema(fixture) do
    ReqStub.install(fn _request ->
      ReqStub.ok_response(%{"data" => %{"__schema" => fixture}})
    end)
  end

  defp read_json(path), do: path |> File.read!() |> Jason.decode!()

  defp shell_messages(level) do
    receive do
      {:mix_shell, ^level, [message]} -> [message | shell_messages(level)]
    after
      0 -> []
    end
  end

  defp operation_keys do
    ~w(args deprecationReason description isDeprecated name type)
  end
end
