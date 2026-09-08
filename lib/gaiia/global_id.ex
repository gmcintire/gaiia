defmodule Gaiia.GlobalID do
  @moduledoc """
  Encode and decode Gaiia Global IDs.

  Global IDs combine a snake_cased type name with a Base58-encoded UUID,
  separated by an underscore: `account_8rnXNuR5sKP5uNwoPL41Zp`.
  """

  @alphabet "123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ"
  @base 58
  @target_len 22

  @doc """
  Encodes a type name and UUID into a Global ID.

  ## Examples

      iex> Gaiia.GlobalID.encode("Account", "3c3b1978-6a68-4a13-bdc2-2d51c8ef7519")
      "account_8rnXNuR5sKP5uNwoPL41Zp"

  """
  @spec encode(String.t(), String.t()) :: String.t()
  def encode(type_name, uuid_str) do
    snake = snake_case(type_name)
    short = short_uuid(uuid_str)
    "#{snake}_#{short}"
  end

  @doc """
  Decodes a Global ID into a tuple of `{type, uuid}`.

  ## Examples

      iex> Gaiia.GlobalID.decode("account_8rnXNuR5sKP5uNwoPL41Zp")
      {"account", "3c3b1978-6a68-4a13-bdc2-2d51c8ef7519"}

  """
  @spec decode(String.t()) :: {String.t(), String.t()}
  def decode(global_id) do
    short_id = String.slice(global_id, -@target_len, @target_len)
    type = String.slice(global_id, 0, byte_size(global_id) - @target_len - 1)
    {type, short_to_uuid(short_id)}
  end

  @doc """
  Extracts the type name from a Global ID.

  ## Examples

      iex> Gaiia.GlobalID.type("account_8rnXNuR5sKP5uNwoPL41Zp")
      "account"

  """
  @spec type(String.t()) :: String.t()
  def type(global_id) do
    type_len = byte_size(global_id) - @target_len - 1
    String.slice(global_id, 0, type_len)
  end

  @doc """
  Extracts the UUID from a Global ID.

  ## Examples

      iex> Gaiia.GlobalID.to_uuid("account_8rnXNuR5sKP5uNwoPL41Zp")
      "3c3b1978-6a68-4a13-bdc2-2d51c8ef7519"

  """
  @spec to_uuid(String.t()) :: String.t()
  def to_uuid(global_id) do
    {_type, uuid} = decode(global_id)
    uuid
  end

  @doc """
  Converts a type name and UUID to a Global ID. Alias for `encode/2`.

  ## Examples

      iex> Gaiia.GlobalID.from_uuid("Account", "3c3b1978-6a68-4a13-bdc2-2d51c8ef7519")
      "account_8rnXNuR5sKP5uNwoPL41Zp"

  """
  @spec from_uuid(String.t(), String.t()) :: String.t()
  def from_uuid(type_name, uuid_str), do: encode(type_name, uuid_str)

  @doc """
  Encodes a UUID to a 22-character Base58 short UUID.

  ## Examples

      iex> Gaiia.GlobalID.short_uuid("3c3b1978-6a68-4a13-bdc2-2d51c8ef7519")
      "8rnXNuR5sKP5uNwoPL41Zp"

  """
  @spec short_uuid(String.t()) :: String.t()
  def short_uuid(uuid_str) do
    stripped = String.downcase(String.replace(uuid_str, "-", ""))
    num = String.to_integer(stripped, 16)
    encode_base58(num)
  end

  @doc """
  Decodes a short UUID back to a standard UUID string.

  ## Examples

      iex> Gaiia.GlobalID.short_to_uuid("8rnXNuR5sKP5uNwoPL41Zp")
      "3c3b1978-6a68-4a13-bdc2-2d51c8ef7519"

  """
  @spec short_to_uuid(String.t()) :: String.t()
  def short_to_uuid(short_id) do
    num = decode_base58(short_id)
    hex = num |> Integer.to_string(16) |> String.pad_leading(32, "0") |> String.downcase()
    format_uuid(hex)
  end

  # -- Private: encode --

  defp encode_base58(0), do: String.duplicate(<<:binary.at(@alphabet, 0)>>, @target_len)

  defp encode_base58(num) do
    chars = do_encode(num, [])
    first = <<:binary.at(@alphabet, 0)>>
    Enum.join(pad_list(chars, @target_len, first))
  end

  defp do_encode(0, acc), do: acc

  defp do_encode(n, acc) do
    idx = rem(n, @base)
    char = <<:binary.at(@alphabet, idx)>>
    do_encode(div(n, @base), [char | acc])
  end

  # -- Private: decode --

  defp decode_base58(short_id) do
    short_id
    |> String.to_charlist()
    |> Enum.reduce(0, fn char, acc -> acc * @base + alpha_index(char) end)
  end

  @alphabet_index_map for {ch, i} <- Enum.with_index(String.to_charlist(@alphabet)), into: %{}, do: {ch, i}

  defp alpha_index(char), do: Map.fetch!(@alphabet_index_map, char)

  # -- Private: helpers --

  defp pad_list(chars, target_len, pad_char) do
    if length(chars) < target_len do
      List.duplicate(pad_char, target_len - length(chars)) ++ chars
    else
      chars
    end
  end

  defp format_uuid(hex) do
    "#{String.slice(hex, 0, 8)}-#{String.slice(hex, 8, 4)}-#{String.slice(hex, 12, 4)}-#{String.slice(hex, 16, 4)}-#{String.slice(hex, 20, 12)}"
  end

  defp snake_case(type_name) do
    type_name |> String.replace(~r/([a-z])([A-Z])/, "\\1_\\2") |> String.downcase()
  end
end
