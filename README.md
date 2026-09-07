# Gaiia

[![CI](https://github.com/gmcintire/gaiia/actions/workflows/ci.yml/badge.svg)](https://github.com/gmcintire/gaiia/actions/workflows/ci.yml)

An Elixir client for the [Gaiia](https://gaiia.com) GraphQL API.

Write GraphQL by hand against a small `Req`-based client, or call one of the
functions generated from the schema — 169 queries and 113 mutations, one
function each, with the API's own descriptions carried through as `@doc`.

> Unofficial community project. Not affiliated with, endorsed by, or supported
> by Gaiia.

## Installation

Add `gaiia` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gaiia, github: "gmcintire/gaiia"}
  ]
end
```

Requires Elixir ~> 1.19.

## Configuration

```elixir
config :gaiia,
  endpoint: "https://api.gaiia.com/graphql",
  token: System.get_env("GAIIA_TOKEN")
```

The token is sent as `Authorization: Bearer <token>`; omit it and no
`Authorization` header is set. Never commit a token — read it from the
environment.

With that config in place, the top-level module builds an implicit client:

```elixir
Gaiia.query("query Account($id: ID!) { account(id: $id) { id name } }", %{"id" => id})
#=> {:ok, %{"account" => %{"id" => "...", "name" => "..."}}}

Gaiia.mutate("mutation ...", %{"input" => input})
```

## Explicit clients

For multiple endpoints, per-call headers, or request options, build a
`Gaiia.Client` yourself. Clients are immutable structs, safe to build once and
share.

```elixir
client = Gaiia.Client.new(token: token, headers: [{"x-trace-id", "abc"}])

Gaiia.Client.query(client, "{ __typename }")
```

`Gaiia.Client.new/1` accepts:

| Option         | Meaning                                                         |
| -------------- | --------------------------------------------------------------- |
| `:endpoint`    | GraphQL endpoint URL. Required unless set in app env.           |
| `:token`       | Bearer token for the `Authorization` header.                    |
| `:headers`     | Extra headers as `[{name, value}]`.                             |
| `:req_options` | Options forwarded to `Req.request/1` (`:adapter`, `:plug`, ...). |

## Generated operations

Every query and mutation in the schema has a generated function. Names are
`Macro.underscore`d from the GraphQL field, and the result is unwrapped from
the `data` envelope:

```elixir
Gaiia.Queries.account(client, %{"id" => id}, "id name")
#=> {:ok, %{"id" => "...", "name" => "..."}}

Gaiia.Mutations.create_internal_ticket(client, %{"input" => input}, "ticket { id }")
```

The signature is the same throughout:

```elixir
name(client, variables \\ %{}, selection \\ "", opts \\ [])
```

- `variables` — GraphQL argument names, camelCase string keys. Only keys you
  pass are sent, so optional arguments stay absent.
- `selection` — selection-set body without the surrounding braces. Required for
  object return types; pass `""` for scalars.
- `opts` — forwarded to `Gaiia.Client.query/4`, e.g. `operation_name: "..."`.

## Pagination

`Gaiia.Pagination.stream/4` walks Relay-style cursors lazily, so only the pages
you consume are fetched.

```elixir
query = ~S"""
query Accounts($first: Int, $after: String) {
  accounts(first: $first, after: $after) {
    nodes { id name }
    pageInfo { hasNextPage endCursor }
  }
}
"""

client
|> Gaiia.Pagination.stream(query, %{"first" => 50}, path: ["accounts"])
|> Stream.take(200)
|> Enum.to_list()
```

`:path` locates the connection inside `data`; `:cursor_variable` renames the
after-cursor variable (default `"after"`). A request failure mid-stream raises
the `Gaiia.Error`, since a stream cannot return an error tuple.

## Global IDs

`Gaiia.GlobalID` converts between the API's base58 global IDs and UUIDs.

```elixir
Gaiia.GlobalID.encode("Account", uuid)
Gaiia.GlobalID.decode(global_id)   #=> {"account", uuid}
Gaiia.GlobalID.type(global_id)
Gaiia.GlobalID.to_uuid(global_id)
```

## Errors

Failures come back as `{:error, %Gaiia.Error{kind: kind}}`, where `kind` lets
you match the failure mode instead of parsing messages:

| `:kind`    | Cause                                                    |
| ---------- | -------------------------------------------------------- |
| `:graphql` | 2xx response carrying a non-empty `errors` list          |
| `:http`    | Non-2xx HTTP response (`:status`, `:details` hold it)    |
| `:network` | Request never reached the server — DNS, refused, timeout |
| `:decode`  | 2xx body that was not a valid GraphQL envelope           |

`Gaiia.Error` is an exception, so it can also be raised or passed to
`Exception.message/1`.

## Testing against the client

Pass a `Req` adapter through `:req_options` to intercept requests without
network access — this is how the suite tests header and body construction; see
`test/support/req_stub.ex`.

```elixir
client = Gaiia.Client.new(endpoint: endpoint, req_options: [adapter: MyStub])
```

## Development

```sh
mix deps.get
mix test
mix format
mix credo --strict
mix dialyzer
```

CI runs `mix test` on Elixir 1.20.4 / Erlang-OTP 29.0.5.

Formatting runs [Styler](https://github.com/adobe/elixir-styler) as a plugin,
so `mix format` also normalizes aliases and directive order.

The generators read `priv/queries.json` and `priv/mutations.json` at compile
time via `Gaiia.Schema`. Both are `@external_resource`s, so replacing them with
a fresh introspection dump and recompiling regenerates the API surface. The
flattened, human-readable dumps under `docs/` describe the same schema.

## License

MIT — see [LICENSE](LICENSE).
