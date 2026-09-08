defmodule Gaiia.SchemaTest do
  use ExUnit.Case, async: true

  alias Gaiia.Schema

  doctest Schema

  describe "doc/2" do
    test "uses and normalizes the schema description and documents argument-free operations" do
      operation = %{"name" => "accounts", "description" => "See [Accounts](../../accounts)."}

      assert Schema.doc(operation, :query) ==
               "See `Accounts`.\n\nGraphQL: `query { accounts }`\n\nTakes no arguments.\n"

      assert Schema.doc(Map.put(operation, "args", []), :query) ==
               "See `Accounts`.\n\nGraphQL: `query { accounts }`\n\nTakes no arguments.\n"
    end

    test "falls back to operation-specific text for queries and mutations" do
      assert Schema.doc(%{"name" => "viewer", "description" => nil}, :query) ==
               "GraphQL query `viewer`.\n\nGraphQL: `query { viewer }`\n\nTakes no arguments.\n"

      assert Schema.doc(%{"name" => "archiveAccount", "description" => nil}, :mutation) ==
               "GraphQL mutation `archiveAccount`.\n\nGraphQL: `mutation { archiveAccount }`\n\nTakes no arguments.\n"
    end

    test "renders argument types, defaults, and normalized descriptions" do
      global_id = %{"kind" => "NON_NULL", "name" => nil, "ofType" => %{"kind" => "SCALAR", "name" => "GlobalID"}}

      string_list = %{
        "kind" => "NON_NULL",
        "name" => nil,
        "ofType" => %{
          "kind" => "LIST",
          "name" => nil,
          "ofType" => %{
            "kind" => "NON_NULL",
            "name" => nil,
            "ofType" => %{"kind" => "SCALAR", "name" => "String"}
          }
        }
      }

      operation = %{
        "name" => "accounts",
        "description" => "List accounts.",
        "args" => [
          %{
            "name" => "id",
            "type" => global_id,
            "defaultValue" => "acct_default",
            "description" => "  Find\n    [Accounts](../../accounts)\t by identifier.  "
          },
          %{"name" => "tags", "type" => string_list, "defaultValue" => nil, "description" => nil}
        ]
      }

      assert Schema.doc(operation, :query) ==
               "List accounts.\n\nGraphQL: `query { accounts }`\n\n## Arguments\n\n" <>
                 "  * `id` — `GlobalID!`, default `acct_default` — Find `Accounts` by identifier.\n" <>
                 "  * `tags` — `[String!]!`\n"
    end
  end

  describe "function_name/1" do
    test "converts camelCase GraphQL names to snake_case atoms" do
      assert Schema.function_name("createInternalTicket") == :create_internal_ticket
    end
  end

  describe "description/1" do
    test "collapses site-relative links to their label" do
      assert Schema.description("See [Files](../../files) for details.") == "See `Files` for details."
    end

    test "preserves absolute links" do
      assert Schema.description("See [docs](https://gaiia.com/docs).") == "See [docs](https://gaiia.com/docs)."
    end

    test "leaves descriptions without links untouched" do
      assert Schema.description("Create a new internal ticket.") == "Create a new internal ticket."
    end
  end

  describe "generated coverage" do
    # A GraphQL field whose Macro.underscore collides with another one would
    # silently redefine the same function and drop an operation, so parity is
    # asserted per operation rather than by count alone.
    test "every query in the schema has exactly one generated function" do
      assert_generated(Schema.queries(), Gaiia.Queries)
    end

    test "every mutation in the schema has exactly one generated function" do
      assert_generated(Schema.mutations(), Gaiia.Mutations)
    end

    test "the schema dumps carry the operations the API documents" do
      names = MapSet.new(Schema.queries(), & &1["name"])

      assert MapSet.subset?(MapSet.new(~w[account accounts products roles technicianTeams webhooks]), names)
    end

    defp assert_generated(operations, module) do
      expected = MapSet.new(operations, &Schema.function_name(&1["name"]))
      generated = MapSet.new(module.__info__(:functions), &elem(&1, 0))

      assert MapSet.size(expected) == length(operations)
      assert expected |> MapSet.difference(generated) |> Enum.to_list() == []
    end
  end
end
