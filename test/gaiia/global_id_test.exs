defmodule Gaiia.GlobalIDTest do
  use ExUnit.Case, async: true

  alias Gaiia.GlobalID

  doctest GlobalID

  # Example from docs: "Account" + "3c3b1978-6a68-4a13-bdc2-2d51c8ef7519"
  # → "account_8rnXNuR5sKP5uNwoPL41Zp"
  @doc_uuid "3c3b1978-6a68-4a13-bdc2-2d51c8ef7519"
  @doc_global_id "account_8rnXNuR5sKP5uNwoPL41Zp"

  describe "encode/2" do
    test "encodes UUID to GlobalID" do
      assert GlobalID.encode("Account", @doc_uuid) == @doc_global_id
    end

    test "snake_cases the type name" do
      assert GlobalID.encode("InventoryItem", @doc_uuid) =~ "inventory_item_"
      assert GlobalID.encode("WorkOrder", @doc_uuid) =~ "work_order_"
    end

    test "already-snakecased type names pass through" do
      result = GlobalID.encode("account", @doc_uuid)
      assert result =~ "account_"
    end
  end

  describe "decode/1" do
    test "decodes GlobalID to {type, uuid} tuple" do
      assert {"account", @doc_uuid} == GlobalID.decode(@doc_global_id)
    end

    test "decodes GlobalIDs with underscores in type name" do
      gid = "inventory_item_8rnXNuR5sKP5uNwoPL41Zp"
      assert {"inventory_item", @doc_uuid} == GlobalID.decode(gid)
    end
  end

  describe "to_uuid/1" do
    test "extracts UUID from GlobalID" do
      assert GlobalID.to_uuid(@doc_global_id) == @doc_uuid
    end
  end

  describe "from_uuid/2" do
    test "converts UUID + type to GlobalID" do
      assert GlobalID.from_uuid("Account", @doc_uuid) == @doc_global_id
    end
  end

  describe "short_uuid/1" do
    test "encodes UUID to 22-char base58 string" do
      short = GlobalID.short_uuid(@doc_uuid)
      assert String.length(short) == 22
      # All chars should be from the Flickr base58 alphabet
      alphabet = ~c"123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ"
      for <<c <- short>>, do: assert(c in alphabet)
    end

    test "handles UUIDs with all zeros" do
      short = GlobalID.short_uuid("00000000-0000-0000-0000-000000000000")
      assert String.length(short) == 22
    end
  end

  describe "roundtrip" do
    test "encode then decode returns original type and uuid" do
      type = "Account"
      uuid = "bccd1343-7f43-4768-932e-a596c06fb098"
      gid = GlobalID.encode(type, uuid)
      expected_type = String.downcase(type)
      assert {^expected_type, ^uuid} = GlobalID.decode(gid)
    end

    test "type/1 extracts the type" do
      gid = GlobalID.encode("Account", @doc_uuid)
      assert GlobalID.type(gid) == "account"
    end
  end
end
