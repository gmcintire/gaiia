defmodule Gaiia.QueriesTest do
  use ExUnit.Case, async: true

  alias Gaiia.Client
  alias Gaiia.ReqStub

  @endpoint "http://127.0.0.1:1/graphql"

  defp capturing_client do
    Client.new(endpoint: @endpoint, req_options: ReqStub.install_ok())
  end

  defp client_with(response_fun) do
    Client.new(endpoint: @endpoint, req_options: ReqStub.install(response_fun))
  end

  describe "inventory queries" do
    test "inventory_item/3 builds an inventoryItem query" do
      client = capturing_client()

      assert {:ok, _} = Gaiia.Queries.inventory_item(client, %{"id" => "x"}, "id")

      assert ReqStub.captured_query() =~ "inventoryItem(id: $id)"
      assert ReqStub.captured_query() =~ "$id: GlobalID!"
    end

    test "inventory_items/3 builds an inventoryItems query" do
      client = capturing_client()

      assert {:ok, _} = Gaiia.Queries.inventory_items(client, %{"first" => 10}, "nodes { id }")

      query = ReqStub.captured_query()
      assert query =~ "inventoryItems"
      assert query =~ "$first: Int"
      assert query =~ "first: $first"
    end

    test "inventory_locations/3 builds an inventoryLocations query" do
      client = capturing_client()

      assert {:ok, _} = Gaiia.Queries.inventory_locations(client, %{}, "nodes { id }")
      assert ReqStub.captured_query() =~ "inventoryLocations"
    end

    test "inventory_models/3 exists" do
      client = capturing_client()
      assert {:ok, _} = Gaiia.Queries.inventory_models(client, %{}, "nodes { id }")
    end

    test "inventory_roles/3 exists" do
      client = capturing_client()
      assert {:ok, _} = Gaiia.Queries.inventory_roles(client, %{}, "nodes { id }")
    end

    test "archived_inventory_roles/3 exists" do
      client = capturing_client()
      assert {:ok, _} = Gaiia.Queries.archived_inventory_roles(client, %{}, "nodes { id }")
    end
  end

  describe "account queries" do
    test "account/3 unwraps the data envelope" do
      client =
        client_with(fn _req ->
          ReqStub.ok_response(%{"data" => %{"account" => %{"id" => "acct_1", "name" => "Acme"}}})
        end)

      assert {:ok, %{"id" => "acct_1", "name" => "Acme"}} = Gaiia.Queries.account(client, %{"id" => "x"}, "id name")
    end

    test "accounts/3 returns the connection map" do
      client =
        client_with(fn _req -> ReqStub.ok_response(%{"data" => %{"accounts" => %{"nodes" => [%{"id" => "a"}]}}}) end)

      assert {:ok, %{"nodes" => [%{"id" => "a"}]}} = Gaiia.Queries.accounts(client, %{}, "nodes { id }")
    end

    test "propagates GraphQL errors" do
      client = client_with(fn _req -> ReqStub.ok_response(%{"errors" => [%{"message" => "Forbidden"}]}) end)

      assert {:error, %Gaiia.Error{kind: :graphql}} = Gaiia.Queries.account(client, %{"id" => "x"}, "id")
    end
  end
end
