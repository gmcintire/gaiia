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

  Traversal comes in a lazy and an eager form. `stream/4` and `edges/4` are
  lazy, so they compose with `Stream` and can stop early, but a failed page has
  nowhere to return an error to and raises `Gaiia.Error`. `collect/4` and
  `collect_edges/4` walk every page eagerly and return
  `{:ok, items} | {:error, %Gaiia.Error{}}` instead.

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
  alias Gaiia.Error

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

  @doc """
  Collect every node from a paginated GraphQL field into a list.

  `stream/4` is lazy, so a failed page has nowhere to return an error to and
  raises. Use this when the whole collection is wanted anyway and the failure
  belongs in a return value — a sync job, a `with` chain, a `GenServer` that
  must not crash on someone else's outage. Traversal stops at the first failed
  page and the partial result is discarded.

  Accepts the same options and traversal ordering as `stream/4`.

  ## Example

      case Gaiia.Pagination.collect(client, query, %{"first" => 50}, path: ["accounts"]) do
        {:ok, accounts} -> Enum.each(accounts, &upsert!/1)
        {:error, %Gaiia.Error{} = error} -> {:error, Gaiia.Error.message(error)}
      end
  """
  @spec collect(Client.t(), String.t(), map(), opts()) :: {:ok, [map()]} | {:error, Error.t()}
  def collect(%Client{} = client, query, variables, opts) do
    collect_items(client, query, variables, opts, "nodes")
  end

  @doc """
  Collect every edge from a paginated GraphQL field into a list.

  The non-raising counterpart of `edges/4`, with the same cursor-bearing items
  and the same options as `collect/4`.
  """
  @spec collect_edges(Client.t(), String.t(), map(), opts()) :: {:ok, [map()]} | {:error, Error.t()}
  def collect_edges(%Client{} = client, query, variables, opts) do
    collect_items(client, query, variables, opts, "edges")
  end

  defp stream_items(client, query, variables, opts, item_key) do
    walk = walker(client, query, variables, opts, item_key)

    Stream.resource(
      fn -> {:cont, nil} end,
      fn
        :halt ->
          {:halt, :halt}

        {:cont, cursor} ->
          case walk.(cursor) do
            {:ok, items, next} -> {items, next}
            {:error, error} -> raise(error)
          end
      end,
      fn _state -> :ok end
    )
  end

  defp collect_items(client, query, variables, opts, item_key) do
    collect_pages(walker(client, query, variables, opts, item_key), {:cont, nil}, [])
  end

  defp collect_pages(_walk, :halt, acc), do: {:ok, Enum.reverse(acc)}

  defp collect_pages(walk, {:cont, cursor}, acc) do
    case walk.(cursor) do
      {:ok, items, next} -> collect_pages(walk, next, Enum.reduce(items, acc, &[&1 | &2]))
      {:error, error} -> {:error, error}
    end
  end

  # One page fetch, shared by the lazy and the eager traversal so they cannot
  # drift on cursor handling, option defaults, or the shape of a page.
  defp walker(client, query, variables, opts, item_key) do
    path = Keyword.fetch!(opts, :path)
    direction = Keyword.get(opts, :direction, :forward)
    cursor_var = Keyword.get(opts, :cursor_variable, default_cursor_variable(direction))

    fn cursor ->
      with {:ok, data} <- Client.query(client, query, put_cursor(variables, cursor_var, cursor)) do
        connection = get_in(data, path) || %{}
        page_info = Map.get(connection, "pageInfo", %{})
        {:ok, Map.get(connection, item_key, []), advance_from(page_info, direction)}
      end
    end
  end

  defp put_cursor(variables, _cursor_var, nil), do: variables
  defp put_cursor(variables, cursor_var, cursor), do: Map.put(variables, cursor_var, cursor)

  defp default_cursor_variable(:forward), do: "after"
  defp default_cursor_variable(:backward), do: "before"

  defp advance_from(%{"hasNextPage" => true, "endCursor" => cursor}, :forward) when is_binary(cursor), do: {:cont, cursor}

  defp advance_from(%{"hasPreviousPage" => true, "startCursor" => cursor}, :backward) when is_binary(cursor),
    do: {:cont, cursor}

  defp advance_from(_page_info, _direction), do: :halt
end
