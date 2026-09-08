defmodule Gaiia.WebhookTest do
  use ExUnit.Case, async: true

  alias Gaiia.Webhook

  @body ~s({"event":"account.updated","id":"account_123"})
  @secret "whsec_test_secret"
  @timestamp 1_492_774_577

  describe "sign/3 and verify/4" do
    test "match the documented HMAC-SHA-256 algorithm" do
      expected_signature =
        :hmac
        |> :crypto.mac(:sha256, @secret, "#{@timestamp}.#{@body}")
        |> Base.encode16(case: :lower)

      header = "t=#{@timestamp},v1=#{expected_signature}"

      assert Webhook.sign(@body, @secret, @timestamp) == header
      assert :ok == Webhook.verify(@body, header, @secret, now: @timestamp)
    end

    test "rejects a body mutated by one byte" do
      header = Webhook.sign(@body, @secret, @timestamp)
      mutated_body = String.replace(@body, "3", "4")

      assert {:error, :invalid_signature} ==
               Webhook.verify(mutated_body, header, @secret, now: @timestamp)
    end

    test "rejects the wrong secret" do
      header = Webhook.sign(@body, @secret, @timestamp)

      assert {:error, :invalid_signature} ==
               Webhook.verify(@body, header, "wrong_secret", now: @timestamp)
    end

    test "accepts any matching v1 signature" do
      "t=" <> rest = Webhook.sign(@body, @secret, @timestamp)
      header = "t=#{rest},v1=#{String.duplicate("0", 64)}"

      assert :ok == Webhook.verify(@body, header, @secret, now: @timestamp)
    end

    test "ignores unknown signature schemes" do
      header = Webhook.sign(@body, @secret, @timestamp) <> ",v2=unknown-future-signature"

      assert :ok == Webhook.verify(@body, header, @secret, now: @timestamp)
    end
  end

  describe "timestamp tolerance" do
    test "rejects a timestamp older than the tolerance" do
      header = Webhook.sign(@body, @secret, @timestamp)

      assert {:error, :expired} ==
               Webhook.verify(@body, header, @secret, now: @timestamp + 301, tolerance: 300)
    end

    test "rejects a future timestamp beyond the tolerance" do
      header = Webhook.sign(@body, @secret, @timestamp)

      assert {:error, :expired} ==
               Webhook.verify(@body, header, @secret, now: @timestamp - 301, tolerance: 300)
    end

    test "accepts timestamps at either tolerance boundary" do
      header = Webhook.sign(@body, @secret, @timestamp)

      assert :ok == Webhook.verify(@body, header, @secret, now: @timestamp - 300)
      assert :ok == Webhook.verify(@body, header, @secret, now: @timestamp + 300)
    end
  end

  describe "timestamp unit" do
    test "accepts the milliseconds Gaiia actually sends" do
      header = Webhook.sign(@body, @secret, @timestamp * 1000)

      assert :ok == Webhook.verify(@body, header, @secret, now: @timestamp)
    end

    test "measures tolerance in seconds for a millisecond timestamp" do
      header = Webhook.sign(@body, @secret, @timestamp * 1000)

      assert :ok == Webhook.verify(@body, header, @secret, now: @timestamp + 300)

      assert {:error, :expired} ==
               Webhook.verify(@body, header, @secret, now: @timestamp + 301)
    end

    test "still accepts seconds, which the header format usually carries" do
      header = Webhook.sign(@body, @secret, @timestamp)

      assert :ok == Webhook.verify(@body, header, @secret, now: @timestamp)
    end

    test "rejects the other scale when the unit is pinned" do
      milliseconds = Webhook.sign(@body, @secret, @timestamp * 1000)
      seconds = Webhook.sign(@body, @secret, @timestamp)

      assert {:error, :expired} ==
               Webhook.verify(@body, milliseconds, @secret, now: @timestamp, unit: :second)

      assert {:error, :expired} ==
               Webhook.verify(@body, seconds, @secret, now: @timestamp, unit: :millisecond)
    end

    test "signs and verifies the timestamp bytes as they arrived" do
      milliseconds = @timestamp * 1000

      expected =
        :hmac
        |> :crypto.mac(:sha256, @secret, "#{milliseconds}.#{@body}")
        |> Base.encode16(case: :lower)

      assert Webhook.sign(@body, @secret, milliseconds) == "t=#{milliseconds},v1=#{expected}"
    end
  end

  describe "malformed headers" do
    test "rejects garbage" do
      assert {:error, :malformed_signature} ==
               Webhook.verify(@body, "not-a-signature", @secret, now: @timestamp)
    end

    test "rejects a header without a timestamp" do
      signature = String.duplicate("0", 64)

      assert {:error, :malformed_signature} ==
               Webhook.verify(@body, "v1=#{signature}", @secret, now: @timestamp)
    end

    test "rejects a malformed v1 value without raising" do
      assert {:error, :invalid_signature} ==
               Webhook.verify(@body, "t=#{@timestamp},v1=not-hex", @secret, now: @timestamp)
    end
  end
end
