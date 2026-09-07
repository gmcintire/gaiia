defmodule Gaiia.MutationsTest do
  use ExUnit.Case, async: true

  alias Gaiia.Client
  alias Gaiia.ReqStub

  @endpoint "http://192.0.2.1:1/graphql"

  defp capturing_client do
    Client.new(endpoint: @endpoint, req_options: ReqStub.install_ok())
  end

  describe "inventory mutations" do
    test "create_inventory_model/3 builds a createInventoryModel mutation" do
      client = capturing_client()

      assert {:ok, _} =
               Gaiia.Mutations.create_inventory_model(
                 client,
                 %{"input" => %{"name" => "Router"}},
                 "inventoryModel { id }"
               )

      body = ReqStub.captured_body()
      assert body["query"] =~ "mutation createInventoryModel"
      assert body["query"] =~ "createInventoryModel(input: $input)"
      assert body["variables"] == %{"input" => %{"name" => "Router"}}
    end

    test "create_inventory_role/3 exists" do
      client = capturing_client()
      assert {:ok, _} = Gaiia.Mutations.create_inventory_role(client, %{"input" => %{}}, "inventoryRole { id }")
    end

    test "archive_inventory_roles/3 exists" do
      client = capturing_client()
      assert {:ok, _} = Gaiia.Mutations.archive_inventory_roles(client, %{"input" => %{}}, "inventoryRoles { id }")
    end

    test "assign_inventory_item/3 exists" do
      client = capturing_client()
      assert {:ok, _} = Gaiia.Mutations.assign_inventory_item(client, %{"input" => %{}}, "inventoryItem { id }")
    end
  end

  describe "account mutations" do
    test "create_account/3 builds a createAccount mutation" do
      client = capturing_client()

      assert {:ok, _} = Gaiia.Mutations.create_account(client, %{"input" => %{}}, "account { id }")

      body = ReqStub.captured_body()
      assert body["query"] =~ "mutation createAccount"
      assert body["query"] =~ "$input: CreateAccountInput!"
    end
  end
end
