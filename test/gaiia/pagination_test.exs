defmodule Gaiia.PaginationTest do
  use ExUnit.Case, async: true

  alias Gaiia.Client
  alias Gaiia.Pagination
  alias Gaiia.ReqStub

  # Reserved TEST-NET-1 (RFC 5737) address — unroutable so an unstubbed
  # request would fail immediately rather than hang.
  @endpoint "http://192.0.2.1:1/graphql"

  defp page(nodes, has_next, end_cursor) do
    connection_page(%{
      "nodes" => nodes,
      "pageInfo" => %{"hasNextPage" => has_next, "endCursor" => end_cursor}
    })
  end

  defp edge_page(edges, has_next, end_cursor) do
    connection_page(%{
      "edges" => edges,
      "pageInfo" => %{"hasNextPage" => has_next, "endCursor" => end_cursor}
    })
  end

  defp backward_page(nodes, has_previous, start_cursor) do
    connection_page(%{
      "nodes" => nodes,
      "pageInfo" => %{"hasPreviousPage" => has_previous, "startCursor" => start_cursor}
    })
  end

  defp captured_variables do
    %{"variables" => vars} = ReqStub.captured_body()
    vars
  end

  defp connection_page(connection) do
    %{"data" => %{"accounts" => connection}}
  end

  # Installs a stub that replays `pages` in order, then keeps returning an
  # empty terminal page. Returns the `req_options` for the client.
  defp stub_pages(pages) do
    counter = :counters.new(1, [])

    ReqStub.install(fn _req ->
      idx = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)
      ReqStub.ok_response(Enum.at(pages, idx) || page([], false, nil))
    end)
  end

  describe "stream/4" do
    test "walks all pages until hasNextPage is false" do
      req_options =
        stub_pages([
          page([%{"id" => "1"}, %{"id" => "2"}], true, "c1"),
          page([%{"id" => "3"}], true, "c2"),
          page([%{"id" => "4"}], false, nil)
        ])

      client = Client.new(endpoint: @endpoint, req_options: req_options)

      ids =
        client
        |> Pagination.stream(
          "query($after: String) { accounts(after: $after) { nodes { id } pageInfo { hasNextPage endCursor } } }",
          %{},
          path: ["accounts"]
        )
        |> Enum.map(& &1["id"])

      assert ids == ["1", "2", "3", "4"]
    end

    test "returns an empty stream when the first page is empty" do
      client = Client.new(endpoint: @endpoint, req_options: stub_pages([page([], false, nil)]))

      result =
        client
        |> Pagination.stream("query { accounts { nodes { id } pageInfo { hasNextPage endCursor } } }", %{},
          path: ["accounts"]
        )
        |> Enum.to_list()

      assert result == []
    end

    test "propagates errors by raising" do
      req_options = ReqStub.install(fn _req -> %Req.Response{status: 500, body: "boom", headers: %{}} end)
      client = Client.new(endpoint: @endpoint, req_options: req_options)

      assert_raise Gaiia.Error, ~r/500/, fn ->
        client
        |> Pagination.stream("{ accounts { nodes { id } pageInfo { hasNextPage endCursor } } }", %{}, path: ["accounts"])
        |> Enum.to_list()
      end
    end
  end

  describe "stream/4 with direction: :backward" do
    test "walks newest-to-oldest following startCursor until hasPreviousPage is false" do
      req_options =
        stub_pages([
          backward_page([%{"id" => "3"}], true, "c2"),
          backward_page([%{"id" => "2"}], true, "c1"),
          backward_page([%{"id" => "1"}], false, nil)
        ])

      client = Client.new(endpoint: @endpoint, req_options: req_options)

      ids =
        client
        |> Pagination.stream(
          "query($last: Int, $before: String) { accounts(last: $last, before: $before) { nodes { id } pageInfo { hasPreviousPage startCursor } } }",
          %{"last" => 50},
          path: ["accounts"],
          direction: :backward
        )
        |> Enum.map(& &1["id"])

      assert ids == ["3", "2", "1"]
    end

    test "sends the cursor as the before variable" do
      req_options =
        stub_pages([
          backward_page([%{"id" => "2"}], true, "c1"),
          backward_page([%{"id" => "1"}], false, nil)
        ])

      client = Client.new(endpoint: @endpoint, req_options: req_options)

      client
      |> Pagination.stream(
        "query($last: Int, $before: String) { accounts(last: $last, before: $before) { nodes { id } pageInfo { hasPreviousPage startCursor } } }",
        %{},
        path: ["accounts"],
        direction: :backward
      )
      |> Enum.to_list()

      assert captured_variables() == %{"before" => "c1"}
    end

    test "cursor_variable overrides the variable name in backward mode" do
      req_options =
        stub_pages([
          backward_page([%{"id" => "2"}], true, "c1"),
          backward_page([%{"id" => "1"}], false, nil)
        ])

      client = Client.new(endpoint: @endpoint, req_options: req_options)

      client
      |> Pagination.stream(
        "query($last: Int, $older_than: String) { accounts(last: $last, before: $older_than) { nodes { id } pageInfo { hasPreviousPage startCursor } } }",
        %{},
        path: ["accounts"],
        direction: :backward,
        cursor_variable: "older_than"
      )
      |> Enum.to_list()

      assert captured_variables() == %{"older_than" => "c1"}
    end
  end

  describe "edges/4" do
    test "yields edges carrying server cursors so callers can resume from them" do
      edge = fn id, cursor -> %{"cursor" => cursor, "node" => %{"id" => id}} end

      req_options = stub_pages([edge_page([edge.("1", "c1")], true, "c1")])
      client = Client.new(endpoint: @endpoint, req_options: req_options)

      edges =
        client
        |> Pagination.edges(
          "query($first: Int, $after: String) { accounts(first: $first, after: $after) { edges { cursor node { id } } pageInfo { hasNextPage endCursor } } }",
          %{},
          path: ["accounts"]
        )
        |> Enum.to_list()

      assert edges == [edge.("1", "c1")]

      # Resuming from the item cursor: seed the after variable with it.
      resume_options = stub_pages([edge_page([edge.("2", "c2")], false, nil)])

      resumed =
        [endpoint: @endpoint, req_options: resume_options]
        |> Client.new()
        |> Pagination.edges(
          "query($first: Int, $after: String) { accounts(first: $first, after: $after) { edges { cursor node { id } } pageInfo { hasNextPage endCursor } } }",
          %{"after" => "c1"},
          path: ["accounts"]
        )
        |> Enum.map(& &1["node"]["id"])

      assert resumed == ["2"]
    end
  end
end
