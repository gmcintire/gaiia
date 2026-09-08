defmodule Gaiia.PaginationTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Gaiia.Client
  alias Gaiia.Pagination
  alias Gaiia.ReqStub

  # Loopback port 1 refuses immediately if a test accidentally misses its stub.
  @endpoint "http://127.0.0.1:1/graphql"

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

  defp node_pages_generator(min_length \\ 1) do
    -100..100
    |> StreamData.integer()
    |> StreamData.list_of(max_length: 3)
    |> StreamData.list_of(
      min_length: min_length,
      max_length: 3
    )
    |> StreamData.map(fn pages ->
      Enum.map(pages, fn ids -> Enum.map(ids, &%{"id" => Integer.to_string(&1)}) end)
    end)
  end

  defp paginated_pages(node_pages, direction, include_edges \\ false) do
    last_index = length(node_pages) - 1

    node_pages
    |> Enum.with_index()
    |> Enum.map(&page_for(&1, direction, include_edges, last_index))
  end

  defp page_for({nodes, index}, direction, include_edges, last_index) do
    has_more = index < last_index
    cursor = if has_more, do: "page-#{index}"

    page_info =
      case direction do
        :forward -> %{"hasNextPage" => has_more, "endCursor" => cursor}
        :backward -> %{"hasPreviousPage" => has_more, "startCursor" => cursor}
      end

    %{"nodes" => nodes, "pageInfo" => page_info}
    |> put_edges(nodes, index, include_edges)
    |> connection_page()
  end

  defp put_edges(connection, _nodes, _index, false), do: connection

  defp put_edges(connection, nodes, index, true) do
    edges = Enum.with_index(nodes, &%{"cursor" => "edge-#{index}-#{&2}", "node" => &1})

    Map.put(connection, "edges", edges)
  end

  defp replay_and_capture(pages) do
    counter = :counters.new(1, [])
    owner = self()
    request_tag = make_ref()

    req_options =
      ReqStub.install(fn %Req.Request{body: body} ->
        index = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)
        send(owner, {request_tag, Jason.decode!(body)["variables"]})
        ReqStub.ok_response(Enum.at(pages, index) || page([], false, nil))
      end)

    {req_options, request_tag}
  end

  defp recorded_variables(request_tag), do: recorded_variables(request_tag, [])

  defp recorded_variables(request_tag, acc) do
    receive do
      {^request_tag, variables} -> recorded_variables(request_tag, [variables | acc])
    after
      0 -> Enum.reverse(acc)
    end
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

    test "raises a GraphQL error from the first page" do
      req_options = ReqStub.install_ok(%{"errors" => [%{"message" => "Forbidden"}]})
      client = Client.new(endpoint: @endpoint, req_options: req_options)

      error =
        assert_raise Gaiia.Error, ~r/Forbidden/, fn ->
          client
          |> Pagination.stream("{ accounts { nodes { id } pageInfo { hasNextPage endCursor } } }", %{},
            path: ["accounts"]
          )
          |> Enum.to_list()
        end

      assert error.kind == :graphql
    end

    test "raises a GraphQL error encountered after yielding an earlier page" do
      # Serve pages by cursor rather than by call order: `Stream.resource/3`
      # restarts from the first page on every enumeration, so both traversals
      # below must see the same sequence.
      req_options = ReqStub.install(&reply_by_cursor/1)
      client = Client.new(endpoint: @endpoint, req_options: req_options)

      stream =
        Pagination.stream(client, "{ accounts { nodes { id } pageInfo { hasNextPage endCursor } } }", %{},
          path: ["accounts"]
        )

      assert Enum.take(stream, 1) == [%{"id" => "1"}]

      error = assert_raise Gaiia.Error, ~r/Traversal failed/, fn -> Enum.to_list(stream) end

      assert error.kind == :graphql
    end

    defp reply_by_cursor(%Req.Request{body: body}) do
      %{"variables" => variables} = Jason.decode!(body)

      case variables["after"] do
        nil -> ReqStub.ok_response(page([%{"id" => "1"}], true, "next"))
        "next" -> ReqStub.ok_response(%{"errors" => [%{"message" => "Traversal failed"}]})
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

  describe "pagination properties" do
    property "forward traversal concatenates pages in order and fetches each page once" do
      check all(pages <- node_pages_generator()) do
        {req_options, request_tag} = pages |> paginated_pages(:forward) |> replay_and_capture()
        client = Client.new(endpoint: @endpoint, req_options: req_options)

        result =
          client
          |> Pagination.stream("query {}", %{}, path: ["accounts"])
          |> Enum.to_list()

        requests = recorded_variables(request_tag)

        assert result == List.flatten(pages)
        assert length(requests) == length(pages)
      end
    end

    property "forward traversal propagates every cursor under the configured variable name" do
      check all(
              pages <- node_pages_generator(2),
              cursor_variable <- StreamData.member_of(~w[continuation cursor olderThan])
            ) do
        {req_options, request_tag} = pages |> paginated_pages(:forward) |> replay_and_capture()
        client = Client.new(endpoint: @endpoint, req_options: req_options)
        initial_variables = %{"first" => 3}

        client
        |> Pagination.stream("query {}", initial_variables,
          path: ["accounts"],
          cursor_variable: cursor_variable
        )
        |> Enum.to_list()

        expected_requests =
          [initial_variables] ++
            Enum.map(0..(length(pages) - 2), fn index ->
              Map.put(initial_variables, cursor_variable, "page-#{index}")
            end)

        assert recorded_variables(request_tag) == expected_requests
      end
    end

    property "backward traversal follows start cursors newest-to-oldest while preserving each page's order" do
      check all(pages <- node_pages_generator(2)) do
        {req_options, request_tag} = pages |> paginated_pages(:backward) |> replay_and_capture()
        client = Client.new(endpoint: @endpoint, req_options: req_options)
        initial_variables = %{"last" => 3}

        result =
          client
          |> Pagination.stream("query {}", initial_variables,
            path: ["accounts"],
            direction: :backward
          )
          |> Enum.to_list()

        expected_requests =
          [initial_variables] ++
            Enum.map(0..(length(pages) - 2), fn index ->
              Map.put(initial_variables, "before", "page-#{index}")
            end)

        assert result == List.flatten(pages)
        assert recorded_variables(request_tag) == expected_requests
        assert length(expected_requests) == length(pages)
      end
    end

    property "forward traversal terminates for every incomplete or non-advancing page shape" do
      check all(
              nodes <- StreamData.map(node_pages_generator(), &List.first/1),
              reason <-
                StreamData.member_of([
                  :has_next_false,
                  :has_next_absent,
                  :non_binary_cursor,
                  :missing_page_info,
                  :missing_connection
                ]),
              invalid_cursor <-
                StreamData.one_of([
                  StreamData.integer(),
                  StreamData.boolean(),
                  StreamData.list_of(StreamData.integer(), max_length: 2)
                ])
            ) do
        body =
          case reason do
            :has_next_false ->
              connection_page(%{
                "nodes" => nodes,
                "pageInfo" => %{"hasNextPage" => false, "endCursor" => "unused"}
              })

            :has_next_absent ->
              connection_page(%{"nodes" => nodes, "pageInfo" => %{"endCursor" => "unused"}})

            :non_binary_cursor ->
              connection_page(%{
                "nodes" => nodes,
                "pageInfo" => %{"hasNextPage" => true, "endCursor" => invalid_cursor}
              })

            :missing_page_info ->
              connection_page(%{"nodes" => nodes})

            :missing_connection ->
              %{"data" => %{}}
          end

        {req_options, request_tag} = replay_and_capture([body])
        client = Client.new(endpoint: @endpoint, req_options: req_options)

        result =
          client
          |> Pagination.stream("query {}", %{}, path: ["accounts"])
          |> Enum.to_list()

        expected = if reason == :missing_connection, do: [], else: nodes

        assert result == expected
        assert recorded_variables(request_tag) == [%{}]
      end
    end

    property "edges yield cursor maps whose nodes match stream traversal in either direction" do
      check all(
              pages <- node_pages_generator(),
              direction <- StreamData.member_of([:forward, :backward])
            ) do
        scripted_pages = paginated_pages(pages, direction, true)

        expected_edges =
          pages
          |> Enum.with_index()
          |> Enum.flat_map(fn {nodes, page_index} ->
            nodes
            |> Enum.with_index()
            |> Enum.map(fn {node, node_index} ->
              %{"cursor" => "edge-#{page_index}-#{node_index}", "node" => node}
            end)
          end)

        {edge_req_options, edge_request_tag} = replay_and_capture(scripted_pages)
        edge_client = Client.new(endpoint: @endpoint, req_options: edge_req_options)

        edges =
          edge_client
          |> Pagination.edges("query {}", %{}, path: ["accounts"], direction: direction)
          |> Enum.to_list()

        edge_requests = recorded_variables(edge_request_tag)

        {node_req_options, node_request_tag} = replay_and_capture(scripted_pages)
        node_client = Client.new(endpoint: @endpoint, req_options: node_req_options)

        nodes =
          node_client
          |> Pagination.stream("query {}", %{}, path: ["accounts"], direction: direction)
          |> Enum.to_list()

        node_requests = recorded_variables(node_request_tag)

        assert edges == expected_edges
        assert Enum.map(edges, & &1["node"]) == nodes
        assert length(edge_requests) == length(pages)
        assert length(node_requests) == length(pages)
      end
    end
  end
end
