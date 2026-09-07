defmodule Gaiia.ErrorTest do
  use ExUnit.Case, async: true

  alias Gaiia.Error

  describe "new/1" do
    test "builds a GraphQL error from a list of error maps" do
      errors = [%{"message" => "Forbidden", "path" => ["account"]}]
      error = Error.graphql(errors)

      assert %Error{kind: :graphql, errors: ^errors} = error
      assert error.message =~ "Forbidden"
    end

    test "builds an HTTP error with a status and body" do
      error = Error.http(500, %{"error" => "boom"})

      assert %Error{kind: :http, status: 500, details: %{"error" => "boom"}} = error
      assert error.message =~ "500"
    end

    test "builds a network error from a transport exception" do
      exception = %RuntimeError{message: "econnrefused"}
      error = Error.network(exception)

      assert %Error{kind: :network, details: ^exception} = error
      assert error.message =~ "econnrefused"
    end

    test "builds a decode error from an invalid body" do
      error = Error.decode("not-json")

      assert %Error{kind: :decode, details: "not-json"} = error
      assert error.message =~ "decode"
    end
  end

  describe "Exception protocol" do
    test "raises with the embedded message" do
      assert_raise Error, ~r/Forbidden/, fn ->
        raise Error.graphql([%{"message" => "Forbidden"}])
      end
    end
  end
end
