# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-09-08

First release published to Hex.

### Added

- `Gaiia.Client.request/4` returns a `Gaiia.Response` carrying the transport
  metadata, including the `Gaiia.RateLimit` budget parsed from the
  `x-rate-limit-*` headers. Rejected operations surface the same struct on the
  error, `retry_at` included.
- `Gaiia.Webhook.verify/4` checks the `X-Gaiia-Webhook-Signature` header
  (HMAC-SHA-256 over `"<timestamp>.<raw body>"`, compared in constant time and
  tolerant of secret rotation). `sign/3` builds signatures for test fixtures.
- `Gaiia.Files` moves file bytes to and from Gaiia's signed storage host with
  `download/2`, `download_to/3`, and `upload/4`. The storage host never
  receives the API key.
- `Gaiia.Pagination.edges/4` yields each item with its own cursor, and
  `stream/4` accepts `direction: :backward` to walk `last`/`before` through
  `hasPreviousPage`/`startCursor`.
- `:timezone` on `Gaiia.Client.new/1` and per call sends the `x-timezone`
  header that scheduling operations need to resolve local day boundaries.
- `Gaiia.Error.code` exposes the first GraphQL error's `extensions.code`
  (`"UNAUTHENTICATED"`, `"RATE_LIMITED"`, ...), and GraphQL failures keep the
  HTTP status they arrived with.
- `mix gaiia.introspect` regenerates the bundled schema dumps from a live
  introspection query, along with the flattened, human-readable dumps under
  `docs/`. `--check` writes nothing and fails when the bundled dumps have
  drifted from the live schema.
- Generated function docs carry each argument's rendered GraphQL type and
  default value, and operations the schema marks deprecated carry Elixir's
  `@deprecated`.

### Changed

- The default endpoint is `https://api.gaiia.com/api/v1`. The previous
  `/graphql` path is not a route — API Gateway answers it with a 403
  `Missing Authentication Token`.
- The API key is sent as `X-Gaiia-Api-Key`, the only scheme the API accepts;
  an `Authorization: Bearer` header authenticates nothing. The client option
  is `:api_key`, replacing `:token`.
- The generated surface is regenerated from a live introspection query: 125
  queries and 212 mutations, replacing 169 queries and 113 mutations. 38
  queries and 100 mutations were missing, 82 generated queries targeted fields
  the API had removed (the `*ImportCsvDocumentation`/`*Template` family), and
  `updateInventoryItem` carried a hand-written `id: ID!` argument that does not
  exist — the API takes `inventoryItemId: GlobalID`.
- The dumps under `docs/` cover the whole schema: every object with all of its
  fields (previously 319 of 4050), plus input objects, enums, unions,
  interfaces, and scalars, with types rendered in GraphQL syntax.

## [0.1.0] - 2026-09-07

Initial commit, tagged but never published to Hex. Its transport could not
authenticate against the live API and its bundled schema had drifted in both
directions; see 0.2.0.

[0.2.0]: https://github.com/gmcintire/gaiia/releases/tag/v0.2.0
[0.1.0]: https://github.com/gmcintire/gaiia/releases/tag/v0.1.0
