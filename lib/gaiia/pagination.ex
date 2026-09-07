defmodule Gaiia.Pagination do
  @moduledoc """
  Helpers for traversing Relay-style cursor pagination over the Gaiia API.

  Connections expose `edges`, `nodes`, `pageInfo`, and `totalCount`. Each edge
  contains its `cursor` and `node`; `totalCount` is the total across all pages,
  not the number of items on the current page. Page info contains
  `hasNextPage`, `hasPreviousPage`, `startCursor`, and `endCursor`.

  Forward traversal uses `first` and `after`, following `hasNextPage` and
  `endCursor`. Backward traversal uses `last` and `before`, following
  `hasPreviousPage` and `startCursor`. Backward traversal yields the nodes or
  edges within each page in the order returned by the server, while traversing
  pages from newest to oldest.

  The general page-size default is 50 and maximum is 250. Individual fields
  can override both values, so this library deliberately does not cap or
  validate page sizes.

  ## Example

      query = ~S\"\"\"
      query Accounts($first: Int, $after: String) {
        accounts(first: $first, after: $after) {
          nodes { id name }
          pageInfo { hasNextPage endCursor }
        }
      }
      \"\"\"

      client
      |> Gaiia.Pagination.stream(query, %{"first" => 50}, path: ["accounts"])
      |> Stream.take(200)
      |> Enum.to_list()
  """

  alias Gaiia.Client

  @type direction :: :forward | :backward
  @type opts :: [
          path: [String.t()],
          cursor_variable: String.t(),
          direction: direction()
        ]

  @doc """
  Stream all nodes from a paginated GraphQL field.

  In backward mode, nodes retain the order returned within each page while
  pages are traversed from newest to oldest.

  ## Options

    * `:path` — A list of keys describing where the connection lives inside
      the `data` payload, for example `["accounts"]`. Required.
    * `:direction` — `:forward` (default) or `:backward`.
    * `:cursor_variable` — Cursor variable name. Defaults to `"after"` for
      forward traversal and `"before"` for backward traversal.
  """
  @spec stream(Client.t(), String.t(), map(), opts()) :: Enumerable.t()
  def stream(%Client{} = client, query, variables, opts) do
    stream_items(client, query, variables, opts, "nodes")
  end

  @doc """
  Stream all edges from a paginated GraphQL field.

  Each yielded edge includes the server-provided `cursor` and `node`, allowing
  callers to save an item cursor and resume by supplying it as the initial
  `after` or `before` variable. Accepts the same options and traversal ordering
  as `stream/4`.
  """
  @spec edges(Client.t(), String.t(), map(), opts()) :: Enumerable.t()
  def edges(%Client{} = client, query, variables, opts) do
    stream_items(client, query, variables, opts, "edges")
  end

  defp stream_items(client, query, variables, opts, item_key) do
    path = Keyword.fetch!(opts, :path)
    direction = Keyword.get(opts, :direction, :forward)
    cursor_var = Keyword.get(opts, :cursor_variable, default_cursor_variable(direction))

    Stream.resource(
      fn -> {:cont, nil} end,
      &next_page(&1, client, query, variables, path, cursor_var, item_key, direction),
      fn _ -> :ok end
    )
  end

  defp next_page(:halt, _client, _query, _variables, _path, _cursor_var, _item_key, _direction), do: {:halt, :halt}

  defp next_page({:cont, cursor}, client, query, variables, path, cursor_var, item_key, direction) do
    vars = put_cursor(variables, cursor_var, cursor)

    client
    |> Client.query(query, vars)
    |> handle_page(path, item_key, direction)
  end

  defp put_cursor(variables, _cursor_var, nil), do: variables
  defp put_cursor(variables, cursor_var, cursor), do: Map.put(variables, cursor_var, cursor)

  defp handle_page({:ok, data}, path, item_key, direction) do
    connection = get_in(data, path) || %{}
    items = Map.get(connection, item_key, [])
    page_info = Map.get(connection, "pageInfo", %{})
    {items, advance_from(page_info, direction)}
  end

  defp handle_page({:error, error}, _path, _item_key, _direction), do: raise(error)

  defp default_cursor_variable(:forward), do: "after"
  defp default_cursor_variable(:backward), do: "before"

  defp advance_from(%{"hasNextPage" => true, "endCursor" => cursor}, :forward) when is_binary(cursor), do: {:cont, cursor}

  defp advance_from(%{"hasPreviousPage" => true, "startCursor" => cursor}, :backward) when is_binary(cursor),
    do: {:cont, cursor}

  defp advance_from(_page_info, _direction), do: :halt
end
