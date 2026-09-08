defmodule Gaiia.WebhookTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

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

    test "verify/3 uses the current time, automatic units, and default tolerance" do
      timestamp = System.system_time(:millisecond)
      header = Webhook.sign(@body, @secret, timestamp)

      assert :ok == Webhook.verify(@body, header, @secret)
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

    test "accepts hexadecimal digests case-insensitively" do
      ["t=" <> timestamp, "v1=" <> signature] =
        @body
        |> Webhook.sign(@secret, @timestamp)
        |> String.split(",")

      header = "t=#{timestamp},v1=#{String.upcase(signature)}"

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

    test "rejects empty and duplicate timestamps" do
      signature = String.duplicate("0", 64)

      assert {:error, :malformed_signature} ==
               Webhook.verify(@body, "t=,v1=#{signature}", @secret, now: @timestamp)

      assert {:error, :malformed_signature} ==
               Webhook.verify(@body, "t=1,t=2,v1=#{signature}", @secret, now: @timestamp)
    end

    test "rejects an empty v1 signature" do
      assert {:error, :malformed_signature} ==
               Webhook.verify(@body, "t=#{@timestamp},v1=", @secret, now: @timestamp)
    end

    test "rejects headers without a v1 signature" do
      assert {:error, :malformed_signature} ==
               Webhook.verify(@body, "t=#{@timestamp}", @secret, now: @timestamp)

      assert {:error, :malformed_signature} ==
               Webhook.verify(@body, "t=#{@timestamp},v2=ignored", @secret, now: @timestamp)
    end

    test "rejects timestamps that are not entirely numeric" do
      signature = String.duplicate("0", 64)

      assert {:error, :malformed_signature} ==
               Webhook.verify(@body, "t=abc,v1=#{signature}", @secret, now: @timestamp)

      assert {:error, :malformed_signature} ==
               Webhook.verify(@body, "t=12x,v1=#{signature}", @secret, now: @timestamp)
    end

    test "rejects a malformed v1 value without raising" do
      assert {:error, :invalid_signature} ==
               Webhook.verify(@body, "t=#{@timestamp},v1=not-hex", @secret, now: @timestamp)
    end
  end

  describe "properties" do
    property "signing and verification round-trip for arbitrary binary inputs" do
      check all(
              body <- StreamData.binary(max_length: 48),
              secret <- StreamData.binary(min_length: 1, max_length: 32),
              timestamp <- StreamData.integer()
            ) do
        header = Webhook.sign(body, secret, timestamp)

        assert :ok == Webhook.verify(body, header, secret, now: timestamp, unit: :second)
      end
    end

    property "a signature is sensitive to every body change" do
      check all(
              [signed_body, different_body] <-
                StreamData.uniq_list_of(StreamData.binary(max_length: 32), length: 2),
              secret <- StreamData.binary(min_length: 1, max_length: 24),
              timestamp <- StreamData.integer(-10_000..10_000)
            ) do
        header = Webhook.sign(signed_body, secret, timestamp)

        assert {:error, :invalid_signature} ==
                 Webhook.verify(different_body, header, secret,
                   now: timestamp,
                   unit: :second
                 )
      end
    end

    property "a signature cannot be verified with a different secret" do
      check all(
              body <- StreamData.binary(max_length: 32),
              [signing_secret, different_secret] <-
                StreamData.uniq_list_of(
                  StreamData.binary(min_length: 1, max_length: 24),
                  length: 2
                ),
              timestamp <- StreamData.integer(-10_000..10_000)
            ) do
        header = Webhook.sign(body, signing_secret, timestamp)

        assert {:error, :invalid_signature} ==
                 Webhook.verify(body, header, different_secret,
                   now: timestamp,
                   unit: :second
                 )
      end
    end

    property "freshness is inclusive and symmetric around the tolerance" do
      check all(
              tolerance <- StreamData.integer(0..1_000),
              outside_offset <-
                StreamData.integer((tolerance + 1)..(tolerance + 1_000)),
              inside_offset <- StreamData.integer(0..tolerance),
              timestamp <- StreamData.integer(-10_000..10_000)
            ) do
        header = Webhook.sign(@body, @secret, timestamp)

        for direction <- [-1, 1] do
          assert {:error, :expired} ==
                   Webhook.verify(@body, header, @secret,
                     now: timestamp + direction * outside_offset,
                     tolerance: tolerance,
                     unit: :second
                   )

          assert :ok ==
                   Webhook.verify(@body, header, @secret,
                     now: timestamp + direction * inside_offset,
                     tolerance: tolerance,
                     unit: :second
                   )
        end
      end
    end

    property "automatic unit inference preserves the signed digest at the magnitude boundary" do
      second_timestamp =
        StreamData.one_of([
          StreamData.constant(100_000_000),
          StreamData.integer(100_000_001..2_000_000_000)
        ])

      check all(
              now <- second_timestamp,
              body <- StreamData.binary(max_length: 32),
              secret <- StreamData.binary(min_length: 1, max_length: 24)
            ) do
        seconds_header = Webhook.sign(body, secret, now)
        milliseconds_header = Webhook.sign(body, secret, now * 1_000)

        assert :ok == Webhook.verify(body, seconds_header, secret, now: now, unit: :auto)
        assert :ok == Webhook.verify(body, seconds_header, secret, now: now, unit: :second)
        assert :ok == Webhook.verify(body, milliseconds_header, secret, now: now, unit: :auto)

        assert :ok ==
                 Webhook.verify(body, milliseconds_header, secret,
                   now: now,
                   unit: :millisecond
                 )
      end
    end

    property "valid hexadecimal signatures of the wrong length are safely rejected" do
      wrong_length_digest =
        StreamData.one_of([
          StreamData.binary(min_length: 1, max_length: 31),
          StreamData.binary(min_length: 33, max_length: 40)
        ])

      check all(digest <- wrong_length_digest) do
        header = "t=#{@timestamp},v1=#{Base.encode16(digest, case: :lower)}"

        assert {:error, :invalid_signature} ==
                 Webhook.verify(@body, header, @secret, now: @timestamp)
      end
    end
  end
end
