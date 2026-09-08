# Gaiia

[![Hex.pm](https://img.shields.io/hexpm/v/gaiia.svg)](https://hex.pm/packages/gaiia)
[![Documentation](https://img.shields.io/badge/documentation-hexdocs-purple.svg)](https://hexdocs.pm/gaiia)
[![License](https://img.shields.io/hexpm/l/gaiia.svg)](LICENSE)
[![CI](https://github.com/gmcintire/gaiia/actions/workflows/ci.yml/badge.svg)](https://github.com/gmcintire/gaiia/actions/workflows/ci.yml)

An Elixir client for the [Gaiia](https://gaiia.com) GraphQL API.

Write GraphQL by hand against a small `Req`-based client, or call one of the
functions generated from the schema — 125 queries and 212 mutations, one
function each, with the API's own descriptions and argument types carried
through as `@doc`.

> Unofficial community project. Not affiliated with, endorsed by, or supported
> by Gaiia.

## Installation

Add `gaiia` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:gaiia, "~> 0.2.0"}
  ]
end
```

Requires Elixir ~> 1.19. Documentation is on
[HexDocs](https://hexdocs.pm/gaiia).

## Configuration

```elixir
config :gaiia,
  endpoint: "https://api.gaiia.com/api/v1",
  api_key: System.get_env("GAIIA_API_KEY")
```

The endpoint above is the default, so only the key is required. It is sent as
`X-Gaiia-Api-Key: <key>`, the only scheme the API accepts — an `Authorization`
header authenticates nothing. Omit the key and every operation comes back as an
`UNAUTHENTICATED` GraphQL error. Keys are issued in `Admin -> API keys` with
per-key permissions; `gaiia_sk_*` keys are server-side secrets, `gaiia_pk_*`
are publishable, and `*_sbox_*` keys address the sandbox instance. Never commit
a key — read it from the environment.

With that config in place, the top-level module builds an implicit client:

```elixir
Gaiia.query("query Account($id: GlobalID!) { account(id: $id) { id name } }", %{"id" => id})
#=> {:ok, %{"account" => %{"id" => "...", "name" => "..."}}}

Gaiia.mutate("mutation ...", %{"input" => input})
```

## Explicit clients

For multiple endpoints, per-call headers, or request options, build a
`Gaiia.Client` yourself. Clients are immutable structs, safe to build once and
share.

```elixir
client = Gaiia.Client.new(api_key: key, headers: [{"x-trace-id", "abc"}])

Gaiia.Client.query(client, "{ __typename }")
```

`Gaiia.Client.new/1` accepts:

| Option         | Meaning                                                          |
| -------------- | ---------------------------------------------------------------- |
| `:endpoint`    | GraphQL endpoint URL. Defaults to `https://api.gaiia.com/api/v1`. |
| `:api_key`     | API key for the `X-Gaiia-Api-Key` header.                        |
| `:timezone`    | IANA identifier sent as `x-timezone`.                            |
| `:headers`     | Extra headers as `[{name, value}]`.                              |
| `:req_options` | Options forwarded to `Req.request/1` (`:adapter`, `:plug`, ...).  |

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
- `opts` — forwarded to `Gaiia.Client.query/4`, e.g. `operation_name: "..."`,
  `timezone: "America/Toronto"`.

Operations the schema marks deprecated carry Elixir's `@deprecated`, so calling
one warns at compile time and names its replacement.

## Schema reference

Each generated function documents its own arguments — every name, its rendered
GraphQL type, and any default — so `h Gaiia.Queries.account` or
[HexDocs](https://hexdocs.pm/gaiia) answers what a call takes. What it does not
answer is what to put in `selection`, since that depends on the return type.

The type side of the schema lives in the repository under `docs/`, written by
the same introspection task: `objects.json`, `inputs.json`, `enums.json`,
`unions.json`, `interfaces.json`, and `scalars.json`, each field and input
rendered in GraphQL syntax with the API's own description. They are reference
dumps rather than a compile-time input, so they are not shipped in the Hex
package — read them in the repository, alongside Gaiia's own docs at
<https://app.gaiia.com/docs>.

## Pagination

`Gaiia.Pagination.stream/4` walks Relay-style cursors lazily, so only the pages
you consume are fetched. `edges/4` is the same walk over `edges`, when you need
each item's own cursor.

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

`:path` locates the connection inside `data`. `:direction` selects `:forward`
(`first`/`after`, following `hasNextPage`/`endCursor`) or `:backward`
(`last`/`before`, following `hasPreviousPage`/`startCursor`); the cursor
variable defaults to match and `:cursor_variable` renames it. Pages default to
50 and cap at 250, but individual fields override both, so the library does not
enforce a size. A request failure mid-stream raises the `Gaiia.Error`, since a
stream cannot return an error tuple.

## Rate limits

Limits are query-cost based: each key has a point bucket that every operation
draws from. `Gaiia.Client.request/4` returns a `Gaiia.Response` instead of bare
data, carrying the reported budget so bulk jobs can throttle before being
rejected:

```elixir
{:ok, %Gaiia.Response{data: data, rate_limit: %Gaiia.RateLimit{remaining: remaining}}} =
  Gaiia.Client.request(client, "{ accounts(first: 50) { nodes { id } } }")
```

A rejected operation is a `RATE_LIMITED` GraphQL error; the same struct is then
on the error, including `retry_at`.

## Global IDs

`Gaiia.GlobalID` converts between the API's `type_base58` global IDs and UUIDs.
Multi-word types keep their underscores (`work_order_6fRnaKy8Xf1Vsh2Wz2sVnR`).

```elixir
Gaiia.GlobalID.encode("Account", uuid)
Gaiia.GlobalID.decode(global_id)   #=> {"account", uuid}
Gaiia.GlobalID.type(global_id)
Gaiia.GlobalID.to_uuid(global_id)
```

## Files

File bytes move directly between you and Gaiia's storage host, outside GraphQL.
`Gaiia.Files` covers those transfers; the surrounding mutations are generated
like any other.

```elixir
{:ok, %{"uploadUrl" => %{"url" => url, "fileKey" => key}}} =
  Gaiia.Mutations.create_document_upload_url(client, %{"input" => input}, "uploadUrl { url fileKey }")

:ok = Gaiia.Files.upload(url, File.read!("contract.pdf"), "application/pdf")

Gaiia.Mutations.create_document(client, %{"input" => %{"fileKey" => key}}, "document { id }")
```

Download URLs come from any `File` object's `url` field and expire, so re-run
the query for a fresh one. `Gaiia.Files.download/2` returns the bytes and
`download_to/3` streams to disk. Neither sends your API key to the file host.

## Webhooks

Gaiia signs each delivery with `X-Gaiia-Webhook-Signature`.
`Gaiia.Webhook.verify/4` checks it against the raw request body — the exact
bytes, since re-encoding the JSON changes the signature:

```elixir
case Gaiia.Webhook.verify(raw_body, signature_header, secret) do
  :ok -> handle(event)
  {:error, reason} -> send_resp(conn, 400, to_string(reason))
end
```

Manage endpoints and subscriptions with `Gaiia.Queries.webhooks/4` and
`Gaiia.Mutations.create_webhook/4`.

## Errors

Failures come back as `{:error, %Gaiia.Error{kind: kind}}`, where `kind` lets
you match the failure mode instead of parsing messages:

| `:kind`    | Cause                                                    |
| ---------- | -------------------------------------------------------- |
| `:graphql` | 2xx response carrying a non-empty `errors` list          |
| `:http`    | Non-2xx HTTP response (`:status`, `:details` hold it)    |
| `:network` | Request never reached the server — DNS, refused, timeout |
| `:decode`  | 2xx body that was not a valid GraphQL envelope           |

Most Gaiia failures are `:graphql` at HTTP 200. `:code` carries the first
error's `extensions.code` (`"UNAUTHENTICATED"`, `"RATE_LIMITED"`, ...).
Expected mutation failures are not errors at all: they arrive as an `errors`
list inside the mutation payload of an `{:ok, data}` result.

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
mix docs --warnings-as-errors
```

CI runs `mix test` on Elixir 1.20.4 / Erlang-OTP 29.0.5, and builds the docs
and the Hex package on the same versions. `mise.toml` pins those two versions
locally, so `mise install` provisions exactly what CI uses; the library itself
supports Elixir ~> 1.19 and is not pinned to them.

Formatting runs [Styler](https://github.com/adobe/elixir-styler) as a plugin,
so `mix format` also normalizes aliases and directive order.

## Refreshing the schema

`Gaiia.Queries` and `Gaiia.Mutations` are generated at compile time from
`priv/queries.json` and `priv/mutations.json`, so those dumps *are* the API
surface — an operation missing from them has no function. Refresh them from a
live introspection query:

```sh
GAIIA_API_KEY=... mix gaiia.introspect
mix compile --force
```

The task also rewrites the flattened, human-readable dumps under `docs/` —
every object, input object, enum, union, interface, and scalar in the schema,
with types rendered in GraphQL syntax. `mix gaiia.introspect --check` writes
nothing and fails when the bundled dumps have drifted from the live schema.

## Releasing

Releases go to [Hex](https://hex.pm/packages/gaiia) from a clean tree on
`main`. `@version` in `mix.exs` drives the package version, the docs
`source_ref`, and the changelog link in the package metadata, so the tag has
to name the commit being published — a tag pointing elsewhere sends every
source link in the docs to the wrong tree.

```sh
# 1. Bump @version in mix.exs and add the CHANGELOG.md entry.
# 2. Verify.
mix test
mix format --check-formatted
mix credo --strict
mix docs --warnings-as-errors
mix hex.build          # inspect the file list and metadata

# 3. Tag the release commit and publish.
version=$(mix run -e 'IO.puts(Mix.Project.config()[:version])')
git tag -a "v$version" -m "v$version"
git push origin main --follow-tags
mix hex.publish        # publishes the package and the docs
```

`mix hex.publish` needs a Hex account with the package owner's API key —
`mix hex.user auth` locally, or `HEX_API_KEY` from `mix hex.user key generate`
in CI.

## License

MIT — see [LICENSE](LICENSE).
