# Native compose API contract

Research date: 2026-08-07. The source contract below is pinned to the official
Misskey repository's stable `master` commit
[`00f66349766dc61298c66129ded5fdeb29e93f41`](https://github.com/misskey-dev/misskey/tree/00f66349766dc61298c66129ded5fdeb29e93f41).
Instance `/api-doc` remains authoritative if a fork deliberately changes its API.

## Authentication and account scope

The official API guide says HTTP endpoints are `POST`, JSON is used except for
`drive/files/create`, and authenticated requests may use
`Authorization: Bearer <accessToken>`. MissCat uses that header form and never
puts the token in JSON or multipart bodies. See [Using the Misskey API](https://misskey-hub.net/en/docs/for-developers/api/token/).

`MissCatComposeAccountScope` binds exactly one composite account ID, one
normalized HTTPS origin, and one token. A client cannot switch any of those per
request. Both the app composer and share extension resolve the selected
`SecureUser.accountIdentifier` before creating this scope. Tokens and response
bodies are never logged or retained in errors; recognized server error fields
are bounded and the active token is redacted if a server reflects it.

## `POST /api/notes/create`

The official endpoint source defines the current request and response schema in
[`notes/create.ts`](https://github.com/misskey-dev/misskey/blob/00f66349766dc61298c66129ded5fdeb29e93f41/packages/backend/src/server/api/endpoints/notes/create.ts).

MissCat sends `application/json` with these reachable compose fields:

- `visibility`: `public`, `home`, `followers`, or `specified`.
- `visibleUserIds`: the de-duplicated recipients for `specified`; otherwise an
  empty array.
- `text` and `cw`: omitted when empty. A plain renote therefore does not send
  an invalid empty `text`.
- `localOnly`, `noExtractMentions`, `noExtractHashtags`, and
  `noExtractEmojis` as booleans. The shipping UI currently produces `false` for
  all extraction flags, but the transport preserves the explicit domain values.
- `fileIds` in the same order as the user's media. It is omitted when empty.
- `replyId` for replies, or `renoteId` for quotes/plain renotes. Shipping flows
  never send both.
- `poll.choices`, `multiple`, and one optional millisecond integer expiry:
  `expiresAt` (absolute Unix time) or `expiredAfter` (duration).

The endpoint requires `write:notes` and returns
`{"createdNote": { ... }}`. The client minimally decodes a non-empty
`createdNote.id`; unknown note fields are ignored. Any HTTP `2xx` is accepted,
but malformed success data is an error.

Current server bounds relevant to reachable UI are applied before sending: CW
100 characters; poll 2–10 unique, non-empty choices of at most 50 characters.
MissCat intentionally retains its existing conservative 1,500-character note
limit and four-media UI limit even though current upstream allows 3,000 and 16.

## `POST /api/drive/files/create`

The official [`drive/files/create.ts`](https://github.com/misskey-dev/misskey/blob/00f66349766dc61298c66129ded5fdeb29e93f41/packages/backend/src/server/api/endpoints/drive/files/create.ts)
requires `write:drive` and multipart form data. MissCat sends:

- one binary `file` part with a sanitized content-disposition filename and its
  prepared MIME type;
- `name` with the intended filename;
- optional `comment` for non-empty alt text;
- `isSensitive` and `force=false`.

The current alt/comment database bound is 512 characters, defined by
[`DB_MAX_IMAGE_COMMENT_LENGTH`](https://github.com/misskey-dev/misskey/blob/00f66349766dc61298c66129ded5fdeb29e93f41/packages/backend/src/const.ts).
The response is a DriveFile object; the client only decodes its non-empty `id`.
Uploads are awaited in media-array order, so `fileIds` deterministically match
the UI order. The share extension uses the same transport with its existing
JPEG filename/type, non-sensitive, and no-comment contract.

## Mutation outcome, cancellation, and duplicate prevention

The official API dispatcher serializes failures as
`{"error":{"message", "code", "id", ...}}`; see
[`ApiCallService.send`](https://github.com/misskey-dev/misskey/blob/00f66349766dc61298c66129ded5fdeb29e93f41/packages/backend/src/server/api/ApiCallService.ts#L250-L268).
MissCat preserves the HTTP status plus those minimal fields, without retaining
the raw body.

The pinned upstream endpoint contract has no idempotency-key request field or
header for either `notes/create` or `drive/files/create`. MissCat therefore does
not send an `Idempotency-Key` header and does **not** claim server-backed
exactly-once delivery. Once either mutation has been dispatched, a transport
failure, cancellation, timeout, or malformed `2xx` response means the server
may already have committed the write. It is surfaced as `outcomeUnknown`, not
as a safely retryable network error.

Before dispatch, the app-group operation journal durably records a SHA-256
fingerprint and the mutation phase. A record contains no access token, note
body, attachment bytes, filename, alt text, or other draft material. It may
contain only the fingerprint, known server file/note IDs, and compensation
attempt markers. Failure to synchronize and read back that pre-dispatch record
prevents the mutation from starting. Corrupt records fail closed as
`outcomeUnknown`.

On relaunch, a safely completed upload response can be resumed by reusing its
known file ID. A request-started upload or note phase cannot be distinguished
from a committed write and blocks the same operation without another network
mutation. A definite note failure or pre-note cancellation deletes all known
orphan uploads through
[`drive/files/delete`](https://github.com/misskey-dev/misskey/blob/00f66349766dc61298c66129ded5fdeb29e93f41/packages/backend/src/server/api/endpoints/drive/files/delete.ts).
If cancellation wins after a note ID is known, the journal first records one
compensation attempt and then calls
[`notes/delete`](https://github.com/misskey-dev/misskey/blob/00f66349766dc61298c66129ded5fdeb29e93f41/packages/backend/src/server/api/endpoints/notes/delete.ts)
exactly once. An ambiguous compensation remains blocked as `outcomeUnknown`.

Two irreducible boundaries remain without server idempotency: an ambiguous
upload can leave an upload whose ID was never received, and an ambiguous note
creation can leave a note whose ID was never received. Blind retry would risk a
duplicate file or note, so MissCat keeps the durable block and tells the user
that the result cannot be confirmed.

Every request has a 60-second default timeout (injectable for tests). Native
`URLSession.data(for:)` and video export both participate in Swift task
cancellation. The app and share submission services reject a second concurrent
submit while the first is active, retain and cancel the active transport task,
and arbitrate terminal UI state so completion or cancellation wins only once.
No mutation is automatically retried. A definite pre-commit failure may be
retried explicitly; an unknown outcome may not.

## Share credential proof and remaining MisskeyKit debt

The signed share extension has an explicit DEBUG-only
`--misscat-share-credential-proof` launch probe. It resolves the exact composite
account ID through the production `UserModel`, reads that account's shared
Keychain credential, and stores only a boolean availability result plus a
SHA-256 account-ID hash in app-group defaults. The raw account ID and credential
are not returned, serialized, sent over the network, or logged.

Compose writes in both the app and share extension now use only the native
transport described above. `MissCatComposeService.swift` still imports
MisskeyKit solely to bridge its legacy persisted `Visibility` enum, and the
share `UserModel.swift` does the same when reading the legacy visibility value.
Neither import is used for upload or note mutations; removing them belongs to
the later persistence-format retirement.
