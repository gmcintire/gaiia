defmodule GaiiaTest do
  use ExUnit.Case, async: false

  # Reserved TEST-NET-1 (RFC 5737) address — unroutable so an unstubbed
  # request would fail immediately rather than hang.
  @endpoint "http://192.0.2.1:1/graphql"

  setup do
    Application.put_env(:gaiia, :endpoint, @endpoint)
    Application.put_env(:gaiia, :api_key, "configured")

    Application.put_env(
      :gaiia,
      :req_options,
      Gaiia.ReqStub.install(fn _req -> Gaiia.ReqStub.ok_response(%{"data" => %{"ping" => "pong"}}) end)
    )

    on_exit(fn ->
      Application.delete_env(:gaiia, :endpoint)
      Application.delete_env(:gaiia, :api_key)
      Application.delete_env(:gaiia, :req_options)
    end)

    :ok
  end

  describe "default_client/0" do
    test "builds a client from application config" do
      client = Gaiia.default_client()
      assert client.endpoint == @endpoint
      assert client.api_key == "configured"
    end
  end

  describe "query/3" do
    test "runs against the default client" do
      assert {:ok, %{"ping" => "pong"}} = Gaiia.query("{ ping }")
    end
  end

  describe "mutate/3" do
    test "runs against the default client" do
      assert {:ok, %{"ping" => "pong"}} = Gaiia.mutate("mutation { ping }")
    end
  end
end
