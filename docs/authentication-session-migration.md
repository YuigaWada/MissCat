# Native authentication session

MissCat opens MiAuth with SwiftUI's `webAuthenticationSession`. The system
browser owns credentials, cookies, and website storage; MissCat receives only
the final callback URL.

## Callback contract

New MiAuth requests use `misscat://auth`. A callback is accepted only when its
scheme, host, path, single `session` query item, and pending UUID all match.
During migration, the former `https://misscat.dev` origin is accepted by the
same strict matcher for an already-pending session. It is never generated for a
new request. This compatibility path does not depend on DNS, an AASA file, or
an Associated Domains entitlement.

The custom scheme uses the SwiftUI authentication API available since iOS
16.4, within MissCat's iOS 17 deployment target. The iOS 17.4 HTTPS callback
API is intentionally not used because it requires the callback host to be an
associated web-credentials domain.

## Login, cancellation, and retry

Ordinary login uses the shared system browser session so an existing server
login remains reusable. An explicit account-switch request uses an ephemeral
session and does not erase global Safari or application data. Cancelling the
system sheet is treated as a user action, not a network error; the native
screen remains visible and its retry controls reopen the same pending MiAuth
request. Token exchange and rollback-safe Keychain persistence remain in
`MissCatAuthenticationService`.

## Sign-up handoff

Sign-up opens the selected instance's `/signup` page with SwiftUI `openURL`.
After registration, the user returns to MissCat and selects
`登録後にログインへ進む`, which creates a fresh MiAuth session. MissCat no
longer embeds server content or reads the server's `localStorage` token.

Acceptance fixtures inject deterministic local session and URL handlers. They
never launch a real browser, contact a server, or contain a real credential.
