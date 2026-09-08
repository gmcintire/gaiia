defmodule Gaiia.OperationTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Gaiia.Operation

  defp arg(name, type_ref), do: %{"name" => name, "type" => type_ref}

  defp scalar(name), do: %{"kind" => "SCALAR", "name" => name, "ofType" => nil}
  defp non_null(inner), do: %{"kind" => "NON_NULL", "name" => nil, "ofType" => inner}
  defp list(inner), do: %{"kind" => "LIST", "name" => nil, "ofType" => inner}

  defp generated_args do
    0..20
    |> StreamData.integer()
    |> StreamData.uniq_list_of(min_length: 1, max_length: 6)
    |> StreamData.map(fn ids -> Enum.map(ids, &generated_arg/1) end)
  end

  defp args_and_subset do
    StreamData.bind(generated_args(), fn args ->
      masks = StreamData.integer(0..(Bitwise.bsl(1, length(args)) - 1))

      StreamData.map(masks, &{args, select_by_mask(args, &1)})
    end)
  end

  defp select_by_mask(args, mask) do
    args
    |> Enum.with_index()
    |> Enum.filter(fn {_arg, index} -> Bitwise.band(mask, Bitwise.bsl(1, index)) != 0 end)
    |> Enum.map(fn {%{name: name}, _index} -> name end)
  end

  defp generated_arg(id) do
    type =
      case rem(id, 4) do
        0 -> scalar("String")
        1 -> non_null(scalar("GlobalID"))
        2 -> list(scalar("Int"))
        3 -> non_null(list(non_null(scalar("String"))))
      end

    %{name: "arg#{id}", spec: arg("arg#{id}", type)}
  end

  defp assert_argument_names_in_order(operation, names, list) do
    Enum.reduce(names, -1, fn name, previous_offset ->
      start = previous_offset + 1
      scope = {start, byte_size(operation) - start}

      assert {offset, _length} = :binary.match(operation, argument_token(name, list), scope: scope)
      assert offset > previous_offset
      offset
    end)
  end

  defp argument_token(name, :declaration), do: "$#{name}:"
  defp argument_token(name, :call), do: "#{name}: $#{name}"

  defp selection_generator do
    ~w[id name status]
    |> StreamData.member_of()
    |> StreamData.list_of(max_length: 5)
    |> StreamData.map(&Enum.join(&1, " "))
  end

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

  describe "build/5 properties" do
    property "declares exactly the supplied arguments in schema order" do
      check all({args, selected_names} <- args_and_subset()) do
        argument_names = Enum.map(args, & &1.name)
        specs = Enum.map(args, & &1.spec)
        variables = Map.new(selected_names, &{&1, "supplied"})

        operation = Operation.build(:query, "resource", specs, variables, "id")

        assert_argument_names_in_order(operation, selected_names, :declaration)
        assert_argument_names_in_order(operation, selected_names, :call)

        operation_identifiers =
          operation
          |> String.split(~r/[^[:alnum:]_]+/, trim: true)
          |> MapSet.new()

        omitted_names = MapSet.difference(MapSet.new(argument_names), MapSet.new(selected_names))
        assert MapSet.disjoint?(omitted_names, operation_identifiers)
      end
    end

    property "wraps exactly non-empty selection bodies in a selection block" do
      check all(selection <- selection_generator()) do
        expected =
          case selection do
            "" -> "query resource { resource }"
            body -> "query resource { resource { #{body} } }"
          end

        assert Operation.build(:query, "resource", [], %{}, selection) == expected
      end
    end

    property "uses the requested operation keyword and ignores undeclared variable keys" do
      check all(
              op_type <- StreamData.member_of([:query, :mutation]),
              args <- generated_args(),
              extra_value <- StreamData.integer()
            ) do
        operation =
          Operation.build(
            op_type,
            "resource",
            Enum.map(args, & &1.spec),
            %{"unknown" => extra_value},
            ""
          )

        assert operation == "#{op_type} resource { resource }"
      end
    end
  end
end
