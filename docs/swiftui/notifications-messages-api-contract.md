# Notifications and messages API contract

Checked on 2026-08-07 JST. This document records capability evidence; it does not
declare the bundle release-ready.

## Notifications

- HTTP page: `POST /api/i/notifications` with `limit`, optional `untilId`,
  `markAsRead`, and the six legacy-visible `includeTypes` values.
- Realtime: authenticated WebSocket `/streaming`, `main` channel,
  `notification` event.
- Required permission: `read:notifications`.
- Supported UI variants: follow, reaction, renote, reply, mention, and quote.

These contracts match the [official API request rules](https://misskey-hub.net/en/docs/for-developers/api/token/),
the [official main channel event list](https://misskey-hub.net/en/docs/for-developers/api/streaming/channel/main/),
and official Misskey source commit `988e3c32a39c1b0a30f71ffcf1f3baf19e5fcd5f`.

## Direct messages / chat

Current upstream Misskey renewed chat uses:

- `POST /api/chat/history`
- `POST /api/chat/messages/user-timeline`
- `POST /api/chat/messages/create-to-user`
- permissions `read:chat` and `write:chat`

The adapter also recognizes the complete legacy set
`messaging/history`, `messaging/messages`, and `messaging/create`. It selects a
family only when all three endpoints are advertised by `/api/endpoints`; mixed or
partial families are rejected.

An unauthenticated endpoint-discovery request to `https://misskey.io/api/endpoints`
on 2026-08-07 exposed `i/notifications` but neither the current `chat/*` family nor
the legacy `messaging/*` family. Therefore direct messages remain a P1 server/product
compatibility blocker for misskey.io. The SwiftUI UI, account-scoped stores, request
contracts, and fixture tests remain implemented; the client reports the unsupported
capability explicitly and does not guess an endpoint or silently remove the feature.

## Security and account isolation

- Access tokens are sent only in the `Authorization: Bearer` header or the WebSocket
  connection required by Misskey and are never logged, persisted by this bundle, or
  included in fixtures.
- Every repository has an immutable account scope. Stores use a generation token and
  cancel realtime/send work during account switching so stale results cannot cross
  account boundaries.
- Foreground push payloads must contain both owner account ID and notification ID;
  wrong-owner and malformed payloads are ignored.
