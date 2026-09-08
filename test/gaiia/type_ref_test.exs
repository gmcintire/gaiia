defmodule Gaiia.TypeRefTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

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

  describe "prune/1" do
    test "preserves nil at the end of a type reference" do
      assert TypeRef.prune(nil) == nil
    end

    test "recursively removes introspection metadata without changing rendering" do
      type = %{
        "__typename" => "__Type",
        "description" => "required collection",
        "kind" => "NON_NULL",
        "name" => nil,
        "ofType" => %{
          "__typename" => "__Type",
          "kind" => "LIST",
          "name" => nil,
          "ofType" => %{
            "__typename" => "__Type",
            "description" => "required item",
            "kind" => "NON_NULL",
            "name" => nil,
            "ofType" => %{
              "__typename" => "__Type",
              "description" => "an account",
              "kind" => "OBJECT",
              "name" => "Account",
              "ofType" => nil,
              "specifiedByURL" => "https://example.test/account"
            },
            "specifiedByURL" => nil
          }
        },
        "specifiedByURL" => nil
      }

      assert TypeRef.prune(type) == %{
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

      assert TypeRef.render(TypeRef.prune(type)) == TypeRef.render(type)
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

  describe "properties" do
    property "pruning is idempotent and retains only type-reference keys" do
      check all({type, _leaf, _layers} <- type_ref_generator()) do
        pruned = TypeRef.prune(type)

        assert TypeRef.prune(pruned) == pruned
        assert only_type_reference_keys?(pruned)
      end
    end

    property "pruning preserves the rendered GraphQL type" do
      check all({type, _leaf, _layers} <- type_ref_generator()) do
        assert TypeRef.render(TypeRef.prune(type)) == TypeRef.render(type)
      end
    end

    property "named_type unwraps every modifier to a suffix-free named leaf" do
      check all({type, leaf, _layers} <- type_ref_generator()) do
        named_type = TypeRef.named_type(type)
        rendered = TypeRef.render(named_type)

        assert named_type == leaf
        assert rendered == leaf["name"]
      end
    end

    property "render decoration exactly mirrors the wrapper stack" do
      check all({type, leaf, layers} <- type_ref_generator()) do
        assert TypeRef.render(type) == expected_render(leaf["name"], layers)
      end
    end
  end

  defp type_ref_generator do
    leaf_generator =
      StreamData.map(
        {StreamData.member_of(["SCALAR", "OBJECT", "ENUM", "INPUT_OBJECT"]), named_type_name_generator()},
        fn {kind, name} ->
          leaf = %{
            "__typename" => "__Type",
            "description" => "generated named type",
            "kind" => kind,
            "name" => name,
            "ofType" => nil,
            "specifiedByURL" => nil
          }

          {leaf, leaf, []}
        end
      )

    leaf_generator
    |> StreamData.tree(fn child_generator ->
      StreamData.map(
        {StreamData.member_of(["NON_NULL", "LIST"]), child_generator},
        fn {kind, {child, leaf, layers}} ->
          wrapper = %{
            "__typename" => "__Type",
            "description" => "generated wrapper",
            "kind" => kind,
            "name" => nil,
            "ofType" => child
          }

          {wrapper, leaf, [kind | layers]}
        end
      )
    end)
    |> StreamData.resize(8)
  end

  defp named_type_name_generator do
    StreamData.map(
      StreamData.list_of(StreamData.integer(?a..?z), min_length: 1, max_length: 8),
      &(&1 |> List.to_string() |> String.capitalize())
    )
  end

  defp only_type_reference_keys?(nil), do: true

  defp only_type_reference_keys?(type) do
    Enum.sort(Map.keys(type)) == ["kind", "name", "ofType"] and
      only_type_reference_keys?(type["ofType"])
  end

  defp expected_render(name, layers) do
    layers
    |> Enum.reverse()
    |> Enum.reduce(name, fn
      "NON_NULL", rendered -> rendered <> "!"
      "LIST", rendered -> "[" <> rendered <> "]"
    end)
  end
end
