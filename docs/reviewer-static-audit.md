# Reviewer audit — SwiftUI migration

Date: 2026-08-07

Reviewed baseline: production SwiftUI-root cutover based on `9c1a338`

Review mode: source inspection, deterministic shell tests, and iPhone 16 Pro / iOS 18.6 Simulator unit and ordinary-root XCUITest on arm64 and x86_64. Screenshot acceptance remains a separate reviewer gate.

## Verdict

The ordinary logged-out and authenticated routes now enter the SwiftUI application assembly without a legacy application wrapper or Storyboard fallback. The fixed ledger records SwiftUI runtime ownership for 44/45 surfaces, no UIKit-owned surface, and one explicitly deferred remote-notification surface. Acceptance remains 0/45: live-service, full visual-parity, legacy-retirement, and independent reviewer gates are still open.

## Release-blocking findings

### 1. ARCH-01: authenticated runtime cutover and physical retirement are implemented; acceptance remains

`ApplicationState` now restores `MissCatApplicationRootStore`, and the authenticated phase constructs `MissCatProductionApplicationRootView`. Its root-owned `NavigationStack`, shell, feature destinations, account generation, and modal routing are exercised through the ordinary production assembly. Remote push ingress is not shipped in this revision. `MissCatLegacyApplicationView` and its project references have been removed.

Static cutover tests reject any legacy application host in shipping Swift sources or the project file, and reject Storyboard/Home-controller construction from the app entry and production root. Ordinary-root UI tests cover the native timeline, account switch, compose, notifications, messages, profile, and settings routes. The 3 Storyboards, 22 XIBs, orphan UIKit controller sources, and their runtime loader calls have been physically removed from the repository and project. Live-service and visual acceptance remain before release.

The share extension is further along: `ShareViewController` installs `ShareComposerView` in a `UIHostingController`, and its extension entry now uses `NSExtensionPrincipalClass` instead of `MainInterface.storyboard`. Share-host E2E and visual-parity evidence remain open. This SwiftUI content migration does not change the main-app verdict.

### 2. AUTH-03: account entry still requires release evidence

The native accounts/settings assembly owns ordinary add, switch, delete, and required last-account recovery routing. AUTH-03 remains unaccepted until live add-account authentication, cancellation, relaunch, and final-account recovery have retained release evidence on the designated environment.

### 3. AUTH-02: callback origin and session validation is implemented

`MissCatAuthenticationCallbackMatcher` compares normalized HTTPS scheme, host, default/explicit port, root path, an exact single `session` query item, and the expected session UUID. It rejects lookalike hosts, wrong ports/paths/sessions, extra query items, fragments, and encoded callback text embedded elsewhere.

The service moves a matching pending session to checking state before suspension, and the browser callback gate reports a callback once, preventing duplicate token exchange. `MissCatAuthenticationCallbackMatcherTests`, callback-gate tests, and service retry/stale-session tests cover these contracts. AUTH-02 is no longer an open blocker; live authentication evidence remains tracked separately under AUTH-03.

### 4. VIS-01 and REL-01: runtime UI coverage exists; visual acceptance remains open

The Xcode project now includes fixture-backed UI targets and deterministic `visualReady` markers, including an ordinary production-root journey. These functional tests do not replace the required same-state screenshot matrix or independent visual review.

The integration agent confirmed a normal-launch SwiftUI Welcome capture at `artifacts/screenshots/swiftui/welcome-iphone16pro-ios18.6.png` in its worktree. Direct comparison against the selected legacy reference is a hard failure:

- full image: 3,027,518 / 3,162,132 changed pixels (0.957429354625), normalized RMSE 0.124123;
- status-bar-masked: 2,847,751 / 2,937,820 changed pixels (0.969342872392), normalized RMSE 0.147354670021.

That is far beyond the documented 0.10% changed-pixel ceiling. A single failing candidate is not a replacement for baseline/current/diff triplets covering all historic and required deterministic states, so VIS-01 and REL-01 remain unresolved.

### 5. VIS-01: comparator does not implement the documented gate

`scripts/compare-screenshots.sh` gates changed-pixel ratio and optional normalized RMSE (`:297-352`). The required protocol additionally gates mean absolute RGBA error, SSIM, and maximum connected changed-region size (`docs/migration-test-matrix.md:99-115`). Those metrics are neither calculated nor written to `summary.json`.

The script self-test passes and covers dimensions, masks, fuzz, deterministic artifacts, RMSE, and large scientific-notation pixel counts. It should be retained, then extended to the complete documented metric set and invoked by a batch manifest that fails on missing cases.

### 6. VIS-02: the active shell still requires visual acceptance

The ordinary bottom bar and shell now use the native SwiftUI implementation. Its SF Symbol mapping still differs from the historical Font Awesome/tab assets, so an explicit approved asset mapping plus screenshot evidence is required; runtime ownership and code-level geometry constants are insufficient for acceptance.

## Additional runtime diagnostic

The full unit run passed, but app startup emitted `[SwiftUI] Invalid frame dimension (negative or non-finite).` three times. `MissCatWelcomeView` computes a logo width as `size.width - 2 * inset` without clamping (`MissCat/SwiftUI/Authentication/MissCatWelcomeView.swift:55-61`), making the transient zero-width layout a likely source. This is an inference from the source and log; it should be isolated with a focused layout test and fixed before relying on captures.

## MFM crash diagnosis

The reported `EXC_BAD_ACCESS` in `MFMTests.testIgnoreSpinTag` is attributable to the old test fixture `UIFont()`, not to `simctl` launch or normal application lifecycle. `UIFont()` exposes an inherited Objective-C initializer that does not produce a valid CoreText-backed font on current iOS. `MFMEngine.generatePlaneString` immediately reads `familyName` and `pointSize`, so the invalid object faults in the XCTest host.

The integrated fix replaces all active MFM test fixtures with `UIFont.systemFont(ofSize:)`; production MFM call sites use named/system fonts with fallbacks. Regression coverage includes the original `<spin>` path and `testGeneratePlaneStringWithValidHelveticaFont`. Both tests passed on iPhone 16 Pro / iOS 18.6. This is a test-host object-validity issue: a normal app launched through `simctl` does not run `MissCatTests` and cannot exercise that invalid fixture. No Simulator result should be inferred from an XCTest-host crash, or vice versa.

## Reviewer-owned regression additions

`MissCatTests/MissCatTests.swift` adds deterministic coverage for two persistence failure paths:

- legacy plaintext API-key metadata is scrubbed even when Keychain reading throws;
- a failed Keychain removal leaves metadata, the credential, and current-account selection intact.

These tests use only the injected fake store and isolated `UserDefaults` suite. Both passed in the targeted and full Simulator runs.

## Verification performed

```sh
git merge-base --is-ancestor 270820f origin/migration/swiftui-main
bash -n scripts/compare-screenshots.sh
bash -n scripts/test-compare-screenshots.sh
scripts/test-compare-screenshots.sh
xcodebuild test -workspace MissCat.xcworkspace -scheme MissCat \
  -destination 'platform=iOS Simulator,id=002539B6-65C0-4B44-B516-15EDDD36DBB9' \
  -derivedDataPath /private/tmp/misscat-reviewer-derived-data \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MissCatTests/MFMTests/testIgnoreSpinTag \
  -only-testing:MissCatTests/MFMTests/testGeneratePlaneStringWithValidHelveticaFont \
  -only-testing:MissCatTests/AccountPersistenceTests \
  -only-testing:MissCatTests/ShareContentNormalizerTests \
  -only-testing:MissCatTests/ShareVisibilityTests \
  -only-testing:MissCatTests/ShareComposerViewModelTests
xcodebuild test -workspace MissCat.xcworkspace -scheme MissCat \
  -destination 'platform=iOS Simulator,id=002539B6-65C0-4B44-B516-15EDDD36DBB9' \
  -derivedDataPath /private/tmp/misscat-reviewer-derived-data \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
git diff --check
```

The visual comparator self-test passed all fixtures, including the 3,162,132-pixel scientific-notation case. Targeted XCTest passed 18 tests with zero failures or skips; the full suite passed 32 tests with zero failures or skips. Result bundles and complete logs are at `/private/tmp/misscat-reviewer-test-logs/targeted-99aee13.xcresult`, `/private/tmp/misscat-reviewer-test-logs/targeted-99aee13.log`, `/private/tmp/misscat-reviewer-test-logs/full-99aee13.xcresult`, and `/private/tmp/misscat-reviewer-test-logs/full-99aee13.log`.

No secret value was copied, modified, or added by this review; an existing credential-shaped source constant was deliberately left untouched and omitted from this report.
