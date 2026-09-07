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
      client = Client.new(endpoint: @endpoint, token: "secret")

      assert %Client{endpoint: @endpoint, token: "secret"} = client
    end

    test "falls back to application config when options are omitted" do
      Application.put_env(:gaiia, :endpoint, @endpoint)
      Application.put_env(:gaiia, :token, "configured")
      on_exit(fn -> Application.delete_env(:gaiia, :endpoint) end)
      on_exit(fn -> Application.delete_env(:gaiia, :token) end)

      client = Client.new()

      assert client.endpoint == @endpoint
      assert client.token == "configured"
    end

    test "accepts custom headers" do
      client = Client.new(endpoint: @endpoint, headers: [{"x-trace-id", "abc"}])

      assert client.headers == [{"x-trace-id", "abc"}]
    end

    test "raises a clear error when no endpoint is configured" do
      previous = Application.get_env(:gaiia, :endpoint)
      Application.delete_env(:gaiia, :endpoint)
      on_exit(fn -> Application.put_env(:gaiia, :endpoint, previous) end)

      assert_raise ArgumentError, ~r/endpoint/, fn -> Client.new() end
    end
  end

  describe "query/3 success path" do
    setup do
      client =
        client_with(fn _req -> ReqStub.ok_response(%{"data" => %{"account" => %{"id" => "acct_1"}}}) end,
          token: "t"
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

    test "sends the Authorization header", %{client: client} do
      Client.query(client, "{ __typename }")

      assert ["Bearer t"] = ReqStub.captured_headers()["authorization"]
    end

    test "sends the content-type header", %{client: client} do
      Client.query(client, "{ __typename }")

      assert ["application/json"] = ReqStub.captured_headers()["content-type"]
    end

    test "includes custom headers from the client" do
      client =
        client_with(fn _req -> ReqStub.ok_response(%{"data" => %{}}) end, token: "t", headers: [{"x-trace-id", "abc"}])

      Client.query(client, "{ __typename }")

      assert ["abc"] = ReqStub.captured_headers()["x-trace-id"]
    end

    test "omits Authorization header when no token is configured" do
      client = client_with(fn _req -> ReqStub.ok_response(%{"data" => %{}}) end, token: nil)

      Client.query(client, "{ __typename }")

      refute Map.has_key?(ReqStub.captured_headers(), "authorization")
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
end
