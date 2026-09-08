defmodule Gaiia.GlobalIDTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Gaiia.GlobalID

  doctest GlobalID

  # Example from docs: "Account" + "3c3b1978-6a68-4a13-bdc2-2d51c8ef7519"
  # → "account_8rnXNuR5sKP5uNwoPL41Zp"
  @doc_uuid "3c3b1978-6a68-4a13-bdc2-2d51c8ef7519"
  @doc_global_id "account_8rnXNuR5sKP5uNwoPL41Zp"

  @base58_alphabet "123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ"
  @max_uuid_integer 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF

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

    test "left-pads small UUID values and round-trips them" do
      for uuid <- [
            "00000000-0000-0000-0000-000000000001",
            "00000000-0000-0000-0001-000000000000"
          ] do
        short = GlobalID.short_uuid(uuid)

        assert String.length(short) == 22
        assert String.starts_with?(short, "1")
        assert GlobalID.short_to_uuid(short) == uuid
      end
    end

    test "encodes the all-zero UUID as 22 pad characters" do
      uuid = "00000000-0000-0000-0000-000000000000"
      short = GlobalID.short_uuid(uuid)

      assert short == String.duplicate("1", 22)
      assert GlobalID.short_to_uuid(short) == uuid
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

  describe "properties" do
    property "short UUID encoding round-trips every 128-bit UUID" do
      check all(uuid <- uuid_generator()) do
        assert uuid |> GlobalID.short_uuid() |> GlobalID.short_to_uuid() == uuid
      end
    end

    property "short UUIDs have fixed width and use only Base58 characters" do
      check all(uuid <- uuid_generator()) do
        short = GlobalID.short_uuid(uuid)

        assert String.length(short) == 22
        assert Enum.all?(String.to_charlist(short), &(&1 in String.to_charlist(@base58_alphabet)))
      end
    end

    property "global IDs preserve the normalized type and UUID" do
      check all(
              {type_name, snake_cased_type} <- type_name_generator(),
              uuid <- uuid_generator()
            ) do
        global_id = GlobalID.encode(type_name, uuid)

        assert GlobalID.decode(global_id) == {snake_cased_type, uuid}
        assert GlobalID.type(global_id) == snake_cased_type
        assert GlobalID.to_uuid(global_id) == uuid
        assert GlobalID.from_uuid(type_name, uuid) == global_id
      end
    end

    property "UUID encoding is case-insensitive" do
      check all(
              {type_name, _snake_cased_type} <- type_name_generator(),
              uuid <- uuid_generator()
            ) do
        assert GlobalID.encode(type_name, String.upcase(uuid)) == GlobalID.encode(type_name, uuid)
      end
    end
  end

  defp uuid_generator do
    StreamData.map(StreamData.integer(0..@max_uuid_integer), &format_uuid/1)
  end

  defp format_uuid(integer) do
    hex = integer |> Integer.to_string(16) |> String.pad_leading(32, "0") |> String.downcase()
    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4), e::binary-size(12)>> = hex
    Enum.join([a, b, c, d, e], "-")
  end

  defp type_name_generator do
    StreamData.bind({lowercase_word_generator(), lowercase_word_generator()}, fn {first, second} ->
      StreamData.member_of([
        {first, first},
        {String.capitalize(first), first},
        {first <> String.capitalize(second), first <> "_" <> second},
        {String.capitalize(first) <> String.capitalize(second), first <> "_" <> second}
      ])
    end)
  end

  defp lowercase_word_generator do
    StreamData.map(
      StreamData.list_of(StreamData.integer(?a..?z), min_length: 2, max_length: 8),
      &List.to_string/1
    )
  end
end
