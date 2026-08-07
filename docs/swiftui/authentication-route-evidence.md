# Authentication route evidence

This audit covers fixed-ledger surfaces 04–07 as one capability: Start, Terms,
the instance editor, and the native MiAuth browser handoff. The ordinary
logged-out route is:

```text
MissCatApp
  -> MissCatRootView
  -> MissCatApplicationPhaseView (.signedOut / .failed)
  -> MissCatAuthenticationFlowView
  -> Start -> Terms -> registration or MiAuth -> callback check -> account install
```

The shipping lifecycle owner uses iOS 17 Observation (`@Observable`, `@State`,
and typed `@Environment`). The authentication directory and its application
lifecycle owner contain no Combine import, `ObservableObject`, `@Published`,
`@StateObject`, or `@EnvironmentObject` state management.

## Behavior and persistence

- Both sign-up and login push Terms and require the explicit `同意する` action.
- Sign-up opens the selected instance's HTTPS `/signup` route and requires the
  explicit `登録後にログインへ進む` handoff before creating a fresh MiAuth session.
- Login uses `ASWebAuthenticationSession` with shared website data. Only an
  explicit account-switch request selects an ephemeral session; neither path
  clears global browser data.
- A user cancellation stays on the native auth surface. `再試行` opens the same
  pending authorization URL; it does not create another MiAuth UUID.
- Callback scheme, host, port, path, the single unescaped `session` query item,
  and the pending UUID must all match. The retired HTTPS origin remains a
  strict receive-only migration path and is never generated for a new request.
- The MiAuth check is one-shot. Transport, status, JSON, denial, missing token,
  missing user, and persistence failures install no new account. Explicit
  retry creates a new UUID and rejects the old callback.
- Successful completion uses `installAuthenticatedUser`, which verifies the
  Keychain credential, credential-free metadata, and current compound account
  identity as one rollback-safe operation. Existing compound identities are
  updated without crossing instance boundaries.

The unit contract is in `MissCatTests/MissCatTests.swift`. It covers current and
legacy callback acceptance, lookalike rejection, session freshness and replay,
sign-up handoff, minimal response decoding, each failure family, rollback-safe
persistence, and explicit retry. The deterministic UI route in
`MissCatLoginProfileUITests/MissCatLoginProfileUITests.swift` covers the four
surfaces, invalid instance input, back/cancel, preparation and browser failure,
sign-up, callback, and system-session cancellation followed by a same-request
retry. Its URLs use the reserved `.invalid` TLD and it contains no live
credential.

## Legacy visual source and capture readiness

The repository has two Start baselines:

| Baseline | Pixels | SHA-256 |
| --- | ---: | --- |
| `images/ScreenShot/iPhoneX/Simulator Screen Shot - iPhone 11 Pro Max - 2020-03-28 at 19.35.01.png` | 1242 × 2688 | `8998e380635365c9fbbe92be86f37a7bfd39643fd012da98d414ca5760128e55` |
| `images/ScreenShot/iPhone Pro/Simulator Screen Shot - iPhone 8 Plus - 2020-03-29 at 00.27.35.png` | 1242 × 2208 | `ed4b7cbb774b53f0113ce4755ea8b792571e4e923a11f770a6eb5f380f96e57c` |

They independently show the diagonal three-stop gradient, logo/tagline, two
white actions, instance-change action, selected instance, and notch/non-notch
safe-area behavior. The exact numeric geometry remains in
`MissCatVisualTokens.swift` and its unit tests.

There is no repository screenshot for Terms or the live WebKit authorization
page. Their legacy app-owned evidence is the `origin/develop` Main.storyboard:
Terms pins its text area to safe top/leading/trailing, then keeps a 15-point gap
to the 30-point agreement action at trailing 20; the auth web content fills all
four safe-area edges and uses background `#5C6367`. Server-owned page pixels are
not an app visual contract after the secure system-browser migration.

`docs/visual-acceptance-requirements.tsv` expands these four surfaces to 36
cases: 8 Start, 8 Terms, 8 instance-editor, and 12 auth-browser cases. Shipping
views now expose stable readiness identifiers for every required state:

- `visual-ready.login-start.default|error`
- `visual-ready.login-terms.top|bottom`
- `visual-ready.login-instance.default|invalid`
- `visual-ready.login-auth-browser.loading|error|callback`

The Start readiness value stays `false` until its legacy 0.7-second entrance
animation completes. Terms markers are overlays and do not change text layout.
The production Start no longer forces light appearance, so the pinned light and
dark cases can both be captured.

No screenshot was produced during this audit. Therefore the 36 cases remain
unrecorded and surfaces 04–07 remain `migrating`; the `>=90%` changed-pixel and
SSIM gates must be run on distinct, policy-sized captures and independently
reviewed before any ledger row can become `accepted`.

## Non-Simulator verification

The supported compile-only check is:

```sh
xcodebuild build-for-testing \
  -project MissCat.xcodeproj \
  -scheme MissCat \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

This compiles all unit and UI test targets without booting or modifying a
Simulator. It is compilation evidence, not executed XCTest or visual evidence.
The static migration and inventory checks remain:

```sh
ruby scripts/verify-swift6-project-settings.rb
ruby scripts/verify-tracked-swift-source-boundary.rb
ruby scripts/verify-pod-linkage-boundary.rb
scripts/report-ui-migration.sh
scripts/verify-visual-acceptance.sh --inventory
```
