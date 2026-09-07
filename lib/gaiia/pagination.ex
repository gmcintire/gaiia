defmodule Gaiia.Pagination do
  @moduledoc """
  Helpers for traversing Relay-style cursor pagination over the Gaiia API.

  The GraphQL schema exposes paginated lists with a `nodes` field and a
  `pageInfo { hasNextPage endCursor }` envelope. `stream/4` follows
  these cursors transparently and yields individual node maps.

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

  @type opts :: [
          path: [String.t()],
          cursor_variable: String.t()
        ]

  @doc """
  Stream all nodes from a paginated GraphQL field.

  ## Options

    * `:path` — A list of keys describing where the connection lives inside
      the `data` payload, for example `["accounts"]`. Required.
    * `:cursor_variable` — Variable name for the after-cursor (default `"after"`).
  """
  @spec stream(Client.t(), String.t(), map(), opts()) :: Enumerable.t()
  def stream(%Client{} = client, query, variables, opts) do
    path = Keyword.fetch!(opts, :path)
    cursor_var = Keyword.get(opts, :cursor_variable, "after")

    Stream.resource(
      fn -> {:cont, nil} end,
      &next_page(&1, client, query, variables, path, cursor_var),
      fn _ -> :ok end
    )
  end

  defp next_page(:halt, _client, _query, _variables, _path, _cursor_var), do: {:halt, :halt}

  defp next_page({:cont, cursor}, client, query, variables, path, cursor_var) do
    vars = put_cursor(variables, cursor_var, cursor)

    client
    |> Client.query(query, vars)
    |> handle_page(path)
  end

  defp put_cursor(variables, _cursor_var, nil), do: variables
  defp put_cursor(variables, cursor_var, cursor), do: Map.put(variables, cursor_var, cursor)

  defp handle_page({:ok, data}, path) do
    connection = get_in(data, path) || %{}
    nodes = Map.get(connection, "nodes", [])
    page_info = Map.get(connection, "pageInfo", %{})
    {nodes, advance_from(page_info)}
  end

  defp handle_page({:error, error}, _path), do: raise(error)

  defp advance_from(%{"hasNextPage" => true, "endCursor" => cursor}) when is_binary(cursor), do: {:cont, cursor}

  defp advance_from(_page_info), do: :halt
end
