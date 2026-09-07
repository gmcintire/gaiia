defmodule Gaiia.ClientTest do
  # async: false because a few tests mutate the application env to verify
  # config fallback behaviour.
  use ExUnit.Case, async: false

  alias Gaiia.Client
  alias Gaiia.Error
  alias Gaiia.ReqStub

  # Use a reserved TEST-NET-1 (RFC 5737) address that is guaranteed unroutable,
  # so that an unstubbed request would fail immediately rather than hang on DNS.
  @endpoint "http://192.0.2.1:1/graphql"

  # `ReqStub` is a module adapter (Req v0.7 deprecated function adapters) that
  # captures the inbound `%Req.Request{}` and returns either a canned
  # `%Req.Response{}` or a transport exception. Tests assert on the captured
  # request via `ReqStub.captured/0` and friends.
  defp client_with(response_fun, opts \\ []) do
    Client.new(Keyword.merge([endpoint: @endpoint, req_options: ReqStub.install(response_fun)], opts))
  end

  describe "new/1" do
    test "builds a client from explicit options" do
      client = Client.new(endpoint: @endpoint, api_key: "secret")

      assert %Client{endpoint: @endpoint, api_key: "secret"} = client
    end

    test "falls back to application config when options are omitted" do
      Application.put_env(:gaiia, :endpoint, @endpoint)
      Application.put_env(:gaiia, :api_key, "configured")
      on_exit(fn -> Application.delete_env(:gaiia, :endpoint) end)
      on_exit(fn -> Application.delete_env(:gaiia, :api_key) end)

      client = Client.new()

      assert client.endpoint == @endpoint
      assert client.api_key == "configured"
    end

    test "accepts custom headers" do
      client = Client.new(endpoint: @endpoint, headers: [{"x-trace-id", "abc"}])

      assert client.headers == [{"x-trace-id", "abc"}]
    end

    test "defaults to the public Gaiia endpoint when none is configured" do
      previous = Application.get_env(:gaiia, :endpoint)
      Application.delete_env(:gaiia, :endpoint)
      on_exit(fn -> Application.put_env(:gaiia, :endpoint, previous) end)

      assert Client.new().endpoint == "https://api.gaiia.com/api/v1"
    end
  end

  describe "query/3 success path" do
    setup do
      client =
        client_with(fn _req -> ReqStub.ok_response(%{"data" => %{"account" => %{"id" => "acct_1"}}}) end,
          api_key: "t"
        )

      {:ok, client: client}
    end

    test "returns the data payload on success", %{client: client} do
      assert {:ok, %{"account" => %{"id" => "acct_1"}}} = Client.query(client, "query { account { id } }")
    end

    test "sends the query in the request body", %{client: client} do
      Client.query(client, "query { account { id } }")

      assert ReqStub.captured_body() == %{"query" => "query { account { id } }", "variables" => %{}}
    end

    test "sends variables in the request body", %{client: client} do
      Client.query(client, "query($id: ID!) { account(id: $id) { id } }", %{"id" => "acct_1"})

      assert ReqStub.captured_body() == %{
               "query" => "query($id: ID!) { account(id: $id) { id } }",
               "variables" => %{"id" => "acct_1"}
             }
    end

    test "sends an operationName when provided", %{client: client} do
      Client.query(client, "query Foo { __typename }", %{}, operation_name: "Foo")

      assert %{"operationName" => "Foo"} = ReqStub.captured_body()
    end

    test "sends the API key in the X-Gaiia-Api-Key header", %{client: client} do
      Client.query(client, "{ __typename }")

      assert ["t"] = ReqStub.captured_headers()["x-gaiia-api-key"]
    end

    test "sends the content-type header", %{client: client} do
      Client.query(client, "{ __typename }")

      assert ["application/json"] = ReqStub.captured_headers()["content-type"]
    end

    test "includes custom headers from the client" do
      client =
        client_with(fn _req -> ReqStub.ok_response(%{"data" => %{}}) end, api_key: "t", headers: [{"x-trace-id", "abc"}])

      Client.query(client, "{ __typename }")

      assert ["abc"] = ReqStub.captured_headers()["x-trace-id"]
    end

    test "omits the API key header when no key is configured" do
      client = client_with(fn _req -> ReqStub.ok_response(%{"data" => %{}}) end, api_key: nil)

      Client.query(client, "{ __typename }")

      refute Map.has_key?(ReqStub.captured_headers(), "x-gaiia-api-key")
    end
  end

  describe "query/3 error paths" do
    test "returns {:error, %Error{kind: :graphql}} when the response contains errors" do
      errors = [%{"message" => "Forbidden", "path" => ["account"]}]

      client = client_with(fn _req -> ReqStub.ok_response(%{"errors" => errors}) end)

      assert {:error, %Error{kind: :graphql, errors: ^errors}} = Client.query(client, "{ x }")
    end

    test "returns {:error, %Error{kind: :http}} on non-2xx responses" do
      client = client_with(fn _req -> %Req.Response{status: 500, body: "boom", headers: %{}} end)

      assert {:error, %Error{kind: :http, status: 500, details: "boom"}} = Client.query(client, "{ x }")
    end

    test "returns {:error, %Error{kind: :network}} when the adapter raises a transport error" do
      exception = %RuntimeError{message: "econnrefused"}
      client = client_with(fn req -> {req, exception} end)

      assert {:error, %Error{kind: :network, details: ^exception}} = Client.query(client, "{ x }")
    end
  end

  describe "mutate/3" do
    test "delegates to query/3" do
      client = client_with(fn _req -> ReqStub.ok_response(%{"data" => %{"createAccount" => %{"id" => "acct_1"}}}) end)

      assert {:ok, %{"createAccount" => %{"id" => "acct_1"}}} =
               Client.mutate(client, "mutation { createAccount { id } }")
    end
  end

  describe "request/4 metadata" do
    defp rate_limited_response(body, headers) do
      %Req.Response{status: 200, body: body, headers: headers}
    end

    test "returns the rate-limit budget the API reported" do
      headers = %{
        "x-rate-limit-allowed" => ["true"],
        "x-rate-limit-cost" => ["8"],
        "x-rate-limit-limit" => ["500"],
        "x-rate-limit-used" => ["8"],
        "x-rate-limit-remaining" => ["492"]
      }

      client = client_with(fn _req -> rate_limited_response(%{"data" => %{"x" => 1}}, headers) end)

      assert {:ok, response} = Client.request(client, "{ x }")

      assert response.data == %{"x" => 1}
      assert response.status == 200

      assert response.rate_limit == %Gaiia.RateLimit{
               allowed: true,
               cost: 8,
               limit: 500,
               used: 8,
               remaining: 492,
               retry_at: nil
             }
    end

    test "reports no rate limit when the response carries no rate-limit headers" do
      client = client_with(fn _req -> ReqStub.ok_response(%{"data" => %{}}) end)

      assert {:ok, %{rate_limit: nil}} = Client.request(client, "{ x }")
    end

    test "surfaces the error code and rate-limit extensions of a RATE_LIMITED rejection" do
      errors = [
        %{
          "message" => "Rate limit exceeded",
          "extensions" => %{
            "code" => "RATE_LIMITED",
            "cost" => 138,
            "limit" => 500,
            "used" => 462,
            "remaining" => 38,
            "retryAt" => "2024-06-27T19:01:02.000Z"
          }
        }
      ]

      client = client_with(fn _req -> ReqStub.ok_response(%{"errors" => errors}) end)

      assert {:error, %Error{kind: :graphql, code: "RATE_LIMITED", status: 200} = error} = Client.query(client, "{ x }")
      assert error.rate_limit.allowed == false
      assert error.rate_limit.remaining == 38
      assert error.rate_limit.retry_at == ~U[2024-06-27 19:01:02.000Z]
    end

    test "surfaces the error code of an authentication failure" do
      errors = [%{"message" => "Invalid key", "extensions" => %{"code" => "UNAUTHENTICATED"}}]
      client = client_with(fn _req -> ReqStub.ok_response(%{"errors" => errors}) end)

      assert {:error, %Error{code: "UNAUTHENTICATED", rate_limit: nil}} = Client.query(client, "{ x }")
    end
  end

  describe "timezone" do
    test "sends the client's timezone as x-timezone" do
      client = client_with(fn _req -> ReqStub.ok_response(%{"data" => %{}}) end, timezone: "America/Toronto")

      Client.query(client, "{ x }")

      assert ["America/Toronto"] = ReqStub.captured_headers()["x-timezone"]
    end

    test "omits x-timezone when none is configured" do
      client = client_with(fn _req -> ReqStub.ok_response(%{"data" => %{}}) end)

      Client.query(client, "{ x }")

      refute Map.has_key?(ReqStub.captured_headers(), "x-timezone")
    end

    test "a per-call timezone overrides the client's" do
      client = client_with(fn _req -> ReqStub.ok_response(%{"data" => %{}}) end, timezone: "America/Toronto")

      Client.query(client, "{ x }", %{}, timezone: "America/Phoenix")

      assert ["America/Phoenix"] = ReqStub.captured_headers()["x-timezone"]
    end

    test "sends per-call headers" do
      client = client_with(fn _req -> ReqStub.ok_response(%{"data" => %{}}) end)

      Client.query(client, "{ x }", %{}, headers: [{"x-trace-id", "abc"}])

      assert ["abc"] = ReqStub.captured_headers()["x-trace-id"]
    end
  end
end
