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

`chat/history` is requested with `room: false` and returns full chat messages,
including both peer objects. `chat/messages/user-timeline` and
`chat/messages/create-to-user` use the current lite one-to-one shape
(`fromUserId`, `toUserId`, optional `text`, and `reactions`); the current lite
shape does not provide the legacy `isRead` field. Fixture contracts cover both
shapes without inventing absent values.

The adapter also recognizes the complete legacy set
`messaging/history`, `messaging/messages`, and `messaging/create`. It selects a
family only when all three endpoints are advertised by `/api/endpoints`; mixed or
partial families are rejected.

Endpoint discovery is cached once per immutable account-scoped repository, so
history, timeline, and send do not repeatedly call the public `/api/endpoints`
route. Mentions use the current native `POST /api/users/show` contract before
opening the profile route.

An unauthenticated endpoint-discovery request to `https://misskey.io/api/endpoints`
on 2026-08-07 exposed `i/notifications` but neither the current `chat/*` family nor
the legacy `messaging/*` family. Therefore direct messages remain a P1 server/product
compatibility blocker for misskey.io. The SwiftUI UI, account-scoped stores, request
contracts, and fixture tests remain implemented; the client reports the unsupported
capability explicitly and does not guess an endpoint or silently remove the feature.

## Ordinary application routes

- The legacy footer's Notifications and Messages taps construct native SwiftUI
  hosting controllers without a launch argument or preview-only route.
- Notification rows and push taps route to the SwiftUI profile/note paths.
- Message history rows push the native conversation screen; URL, mention, and
  hashtag taps are bridged to the existing application navigation boundary.
- Tapping an already-selected Notifications tab issues a deterministic native
  scroll-to-top request.

## Security and account isolation

- Access tokens are sent only in the `Authorization: Bearer` header or the WebSocket
  connection required by Misskey and are never logged, persisted by this bundle, or
  included in fixtures.
- Every repository has an immutable account scope. Stores use a generation token and
  cancel realtime/send work during account switching so stale results cannot cross
  account boundaries.
- Foreground push payloads must contain both owner account ID and notification ID;
  wrong-owner and malformed payloads are ignored.
- Camel-case and service-worker snake-case push keys are normalized at the
  boundary. Push registration always uses the immutable account being registered,
  never a mutable global current account, and payload contents are not logged.

No live credentials or authenticated network calls are used by the contract test
suite. Current upstream schemas were audited at official Misskey source commit
`988e3c32a39c1b0a30f71ffcf1f3baf19e5fcd5f`.
