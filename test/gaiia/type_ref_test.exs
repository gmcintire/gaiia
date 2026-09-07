defmodule Gaiia.TypeRefTest do
  use ExUnit.Case, async: true

  alias Gaiia.TypeRef

  describe "render/1" do
    test "renders a scalar" do
      assert TypeRef.render(%{"kind" => "SCALAR", "name" => "Int", "ofType" => nil}) == "Int"
    end

    test "renders a non-null scalar" do
      type = %{"kind" => "NON_NULL", "name" => nil, "ofType" => %{"kind" => "SCALAR", "name" => "Int", "ofType" => nil}}
      assert TypeRef.render(type) == "Int!"
    end

    test "renders a list of scalars" do
      type = %{"kind" => "LIST", "name" => nil, "ofType" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil}}
      assert TypeRef.render(type) == "[String]"
    end

    test "renders a list of non-null scalars" do
      type = %{
        "kind" => "LIST",
        "name" => nil,
        "ofType" => %{
          "kind" => "NON_NULL",
          "name" => nil,
          "ofType" => %{"kind" => "SCALAR", "name" => "String", "ofType" => nil}
        }
      }

      assert TypeRef.render(type) == "[String!]"
    end

    test "renders a non-null list of non-null scalars" do
      type = %{
        "kind" => "NON_NULL",
        "name" => nil,
        "ofType" => %{
          "kind" => "LIST",
          "name" => nil,
          "ofType" => %{
            "kind" => "NON_NULL",
            "name" => nil,
            "ofType" => %{"kind" => "SCALAR", "name" => "Int", "ofType" => nil}
          }
        }
      }

      assert TypeRef.render(type) == "[Int!]!"
    end

    test "renders an input object" do
      type = %{"kind" => "INPUT_OBJECT", "name" => "AccountFilter", "ofType" => nil}
      assert TypeRef.render(type) == "AccountFilter"
    end

    test "renders an enum" do
      type = %{"kind" => "ENUM", "name" => "AccountStatus", "ofType" => nil}
      assert TypeRef.render(type) == "AccountStatus"
    end

    test "renders a non-null enum" do
      type = %{
        "kind" => "NON_NULL",
        "name" => nil,
        "ofType" => %{"kind" => "ENUM", "name" => "AccountStatus", "ofType" => nil}
      }

      assert TypeRef.render(type) == "AccountStatus!"
    end
  end

  describe "named_type/1" do
    test "unwraps to the innermost named type" do
      type = %{
        "kind" => "NON_NULL",
        "name" => nil,
        "ofType" => %{
          "kind" => "LIST",
          "name" => nil,
          "ofType" => %{
            "kind" => "NON_NULL",
            "name" => nil,
            "ofType" => %{"kind" => "OBJECT", "name" => "Account", "ofType" => nil}
          }
        }
      }

      assert TypeRef.named_type(type) == %{"kind" => "OBJECT", "name" => "Account", "ofType" => nil}
    end
  end
end
