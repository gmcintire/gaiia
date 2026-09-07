defmodule Gaiia.SchemaTest do
  use ExUnit.Case, async: true

  alias Gaiia.Schema

  doctest Schema

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
