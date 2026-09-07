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
end
