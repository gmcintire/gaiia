# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-09-23

### Added

- Regenerated the API surface from a live introspection query: 130 queries
  and 225 mutations, up from 125 and 212. New queries:
  `consumableAssignationHistory`, `nonSerializedItems`,
  `nonSerializedItemsAssignedToAssignee`,
  `nonSerializedItemsPreviouslyAssignedToAssignee`, and
  `webhookTriggerRequest`. New mutations: `acknowledgeEntityChange`,
  `addConsumables`, `addNonSerializedItem`, `addScheduleToTechnician`,
  `assignConsumables`, `assignNonSerializedItems`,
  `clearSchedulesForTechnician`, `createCustomObjectRecordFileUploadUrl`,
  `createTicketMailbox`, `deleteTicketMailbox`, `moveConsumables`,
  `moveNonSerializedItems`, and `updateTicketMailbox`. The `tickets` query
  gained a `search` argument. No operations were removed or re-typed.

## [0.3.0] - 2026-09-08

Supersedes 0.2.1, which was tagged but never published to Hex.

### Added

- `Gaiia.Pagination.collect/4` and `collect_edges/4` walk every page eagerly
  and return `{:ok, items} | {:error, %Gaiia.Error{}}`. `stream/4` and
  `edges/4` are lazy, so a failed page has nowhere to return an error to and
  raises; a sync job or a `with` chain wants the failure in a return value.
  Both traversals now share one page walker, so they cannot drift on cursor
  handling or option defaults.
- `Gaiia.Error.retriable?/1` separates the failures worth trying again — a
  transport error, a 5xx, and rate limiting in either of the forms Gaiia
  reports it — from the ones that will fail identically, such as an
  `UNAUTHENTICATED` key or a rejected argument.
- `Gaiia.Error.retry_after/2` and `Gaiia.RateLimit.retry_after/2` turn the
  reported `retry_at` into whole seconds to wait, rounding up so a caller that
  sleeps for the result never wakes early. `nil` means the API named no time
  and the caller should pick its own backoff.
- `Gaiia.RateLimit.exhausted?/1` reports whether the budget leaves room for
  another operation.

### Fixed

- `Gaiia.Webhook.verify/4` accepts the millisecond `t=` timestamp Gaiia
  actually sends. It compared the value against `System.system_time(:second)`,
  so a live delivery was ~55,000 years in the future and every one was
  rejected as `:expired`. The scale is now inferred from the value's
  magnitude, and `:unit` (`:auto`, `:second`, `:millisecond`) pins it when a
  sender must be held to one. `:tolerance` and `:now` remain in seconds, and
  the digest still covers the timestamp exactly as it arrived.

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

[0.4.0]: https://github.com/gmcintire/gaiia/releases/tag/v0.4.0
[0.3.0]: https://github.com/gmcintire/gaiia/releases/tag/v0.3.0
[0.2.0]: https://github.com/gmcintire/gaiia/releases/tag/v0.2.0
[0.1.0]: https://github.com/gmcintire/gaiia/releases/tag/v0.1.0
