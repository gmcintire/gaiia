defmodule Gaiia.Webhook do
  @moduledoc """
  Signs and verifies Gaiia webhook deliveries.

  Verification requires the exact raw request body bytes. Parsing JSON and then
  re-encoding it can change those bytes and break the signature. In Phoenix,
  cache the raw body with a custom body reader before `Plug.Parsers` decodes it.

  ## Subscriptions

  Endpoints are managed with the generated operations — `Gaiia.Queries.webhooks/4`,
  `Gaiia.Mutations.create_webhook/4`, `Gaiia.Mutations.delete_webhook/4` — and
  deliveries are auditable through `Gaiia.Queries.webhook_execution/4`.

  `CreateWebhookInput.eventNames` is `[String!]!`: the schema does not enumerate
  event names, so this library cannot check them and no list is bundled here to
  go stale. The catalog (85 events as of 2026-09-07, from `account.created` to
  `work_order.updated`) is at <https://app.gaiia.com/docs/webhooks/overview>, and
  a live endpoint's current subscriptions read back from `webhook.eventNames`.
  A misspelled name is accepted and simply never fires.
  """

  @typedoc "Reason a webhook signature could not be verified."
  @type error_reason :: :malformed_signature | :expired | :invalid_signature

  @typedoc "Options for `verify/4`."
  @type verify_option :: {:tolerance, non_neg_integer()} | {:now, integer()}

  @doc """
  Verify a webhook signature against the exact raw request body.

  The timestamp must be within `:tolerance` seconds of `:now`. The default
  tolerance is 300 seconds and the default time is the current Unix time.
  """
  @spec verify(binary(), String.t(), binary(), [verify_option()]) :: :ok | {:error, error_reason()}
  def verify(raw_body, signature_header, secret, opts \\ [])
      when is_binary(raw_body) and is_binary(signature_header) and is_binary(secret) and is_list(opts) do
    with {:ok, timestamp_string, timestamp, signatures} <- parse_header(signature_header),
         :ok <- verify_timestamp(timestamp, opts),
         true <- valid_signature?(signatures, raw_body, secret, timestamp_string) do
      :ok
    else
      false -> {:error, :invalid_signature}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Build a complete webhook signature header.

  This is useful when constructing webhook fixtures for tests.
  """
  @spec sign(binary(), binary(), integer()) :: String.t()
  def sign(raw_body, secret, timestamp) when is_binary(raw_body) and is_binary(secret) and is_integer(timestamp) do
    timestamp_string = Integer.to_string(timestamp)
    signature = raw_body |> digest(secret, timestamp_string) |> Base.encode16(case: :lower)

    "t=#{timestamp_string},v1=#{signature}"
  end

  defp parse_header(signature_header) do
    signature_header
    |> String.split(",", trim: true)
    |> Enum.reduce_while({:ok, nil, []}, &parse_component/2)
    |> validate_components()
  end

  defp parse_component(component, {:ok, timestamp, signatures}) do
    case component |> String.trim() |> String.split("=", parts: 2) do
      ["t", value] when timestamp == nil and value != "" ->
        {:cont, {:ok, String.trim(value), signatures}}

      ["t", _value] ->
        {:halt, {:error, :malformed_signature}}

      ["v1", value] when value != "" ->
        {:cont, {:ok, timestamp, [String.trim(value) | signatures]}}

      ["v1", _value] ->
        {:halt, {:error, :malformed_signature}}

      [prefix, _value] when prefix != "" ->
        {:cont, {:ok, timestamp, signatures}}

      _other ->
        {:halt, {:error, :malformed_signature}}
    end
  end

  defp validate_components({:ok, nil, _signatures}), do: {:error, :malformed_signature}
  defp validate_components({:ok, _timestamp, []}), do: {:error, :malformed_signature}

  defp validate_components({:ok, timestamp_string, signatures}) do
    case Integer.parse(timestamp_string) do
      {timestamp, ""} -> {:ok, timestamp_string, timestamp, signatures}
      _other -> {:error, :malformed_signature}
    end
  end

  defp validate_components(error), do: error

  defp verify_timestamp(timestamp, opts) do
    tolerance = Keyword.get(opts, :tolerance, 300)
    now = Keyword.get(opts, :now, System.system_time(:second))

    if abs(now - timestamp) <= tolerance do
      :ok
    else
      {:error, :expired}
    end
  end

  defp valid_signature?(signatures, raw_body, secret, timestamp_string) do
    expected = digest(raw_body, secret, timestamp_string)

    Enum.any?(signatures, fn signature ->
      case Base.decode16(signature, case: :mixed) do
        {:ok, candidate} when byte_size(candidate) == byte_size(expected) ->
          :crypto.hash_equals(candidate, expected)

        _other ->
          false
      end
    end)
  end

  defp digest(raw_body, secret, timestamp_string) do
    :crypto.mac(:hmac, :sha256, secret, [timestamp_string, ".", raw_body])
  end
end
