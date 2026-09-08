defmodule GaiiaTest do
  use ExUnit.Case, async: false

  # Loopback port 1 refuses connections instantly if a request is not stubbed.
  @endpoint "http://127.0.0.1:1/graphql"

  setup do
    # `test_helper.exs` installs a global endpoint and stub transport; restore
    # whatever was there rather than deleting it, or later tests inherit an
    # empty `:req_options` and issue real requests.
    previous = Map.new([:endpoint, :api_key, :req_options], &{&1, Application.fetch_env(:gaiia, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:gaiia, key, value)
        {key, :error} -> Application.delete_env(:gaiia, key)
      end)
    end)

    Application.put_env(:gaiia, :endpoint, @endpoint)
    Application.put_env(:gaiia, :api_key, "configured")

    Application.put_env(
      :gaiia,
      :req_options,
      Gaiia.ReqStub.install(fn _req -> Gaiia.ReqStub.ok_response(%{"data" => %{"ping" => "pong"}}) end)
    )

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

  describe "request/3" do
    test "runs against the default client and retains transport metadata" do
      headers = %{
        "x-rate-limit-allowed" => ["true"],
        "x-rate-limit-cost" => ["3"],
        "x-rate-limit-limit" => ["500"],
        "x-rate-limit-used" => ["11"],
        "x-rate-limit-remaining" => ["489"]
      }

      req_options =
        Gaiia.ReqStub.install(fn _req ->
          %Req.Response{status: 200, body: %{"data" => %{"ping" => "pong"}}, headers: headers}
        end)

      Application.put_env(:gaiia, :req_options, req_options)

      assert {:ok,
              %Gaiia.Response{
                data: %{"ping" => "pong"},
                status: 200,
                rate_limit: %Gaiia.RateLimit{
                  allowed: true,
                  cost: 3,
                  limit: 500,
                  used: 11,
                  remaining: 489
                }
              }} = Gaiia.request("{ ping }")
    end
  end
end
