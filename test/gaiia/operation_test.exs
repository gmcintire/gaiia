defmodule Gaiia.OperationTest do
  use ExUnit.Case, async: true

  alias Gaiia.Operation

  defp arg(name, type_ref), do: %{"name" => name, "type" => type_ref}

  defp scalar(name), do: %{"kind" => "SCALAR", "name" => name, "ofType" => nil}
  defp non_null(inner), do: %{"kind" => "NON_NULL", "name" => nil, "ofType" => inner}
  defp list(inner), do: %{"kind" => "LIST", "name" => nil, "ofType" => inner}

  describe "build/5 — queries" do
    test "no args, no selection" do
      assert Operation.build(:query, "ping", [], %{}, "") == "query ping { ping }"
    end

    test "no args, with selection" do
      op = Operation.build(:query, "account", [], %{}, "id name")
      assert op == "query account { account { id name } }"
    end

    test "single required arg passed in variables" do
      args = [arg("id", non_null(scalar("GlobalID")))]
      op = Operation.build(:query, "account", args, %{"id" => "acct_1"}, "id name")
      assert op == "query account($id: GlobalID!) { account(id: $id) { id name } }"
    end

    test "omits variable declarations for args not present in variables" do
      args = [
        arg("first", scalar("Int")),
        arg("last", scalar("Int")),
        arg("after", scalar("String"))
      ]

      op = Operation.build(:query, "accounts", args, %{"first" => 10}, "nodes { id }")
      assert op == "query accounts($first: Int) { accounts(first: $first) { nodes { id } } }"
    end

    test "includes all declared variables when all are passed" do
      args = [arg("first", scalar("Int")), arg("after", scalar("String"))]

      op = Operation.build(:query, "accounts", args, %{"first" => 10, "after" => "c1"}, "nodes { id }")

      assert op =~ "$first: Int"
      assert op =~ "$after: String"
      assert op =~ "accounts(first: $first, after: $after)"
    end

    test "renders complex list/non-null arg types" do
      args = [arg("orderBy", list(non_null(%{"kind" => "INPUT_OBJECT", "name" => "AccountOrderBy", "ofType" => nil})))]

      op = Operation.build(:query, "accounts", args, %{"orderBy" => []}, "nodes { id }")
      assert op =~ "$orderBy: [AccountOrderBy!]"
    end
  end

  describe "build/5 — mutations" do
    test "renders a mutation with a required input arg" do
      args = [arg("input", non_null(%{"kind" => "INPUT_OBJECT", "name" => "CreateAccountInput", "ofType" => nil}))]

      op = Operation.build(:mutation, "createAccount", args, %{"input" => %{}}, "account { id }")

      assert op ==
               "mutation createAccount($input: CreateAccountInput!) { createAccount(input: $input) { account { id } } }"
    end

    test "renders a scalar-returning mutation with no selection" do
      args = [arg("id", non_null(scalar("GlobalID")))]
      op = Operation.build(:mutation, "archiveSomething", args, %{"id" => "x"}, "")
      assert op == "mutation archiveSomething($id: GlobalID!) { archiveSomething(id: $id) }"
    end
  end
end
