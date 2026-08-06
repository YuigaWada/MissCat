# Reviewer audit — SwiftUI migration

Date: 2026-08-07

Reviewed baseline: `origin/migration/swiftui-main` at `9b29738` (`270820f` is an ancestor)

Review mode: source inspection, deterministic shell tests, and iPhone 16 Pro / iOS 18.6 Simulator unit XCTest. The reviewer did not run XCUITest, GUI automation, or screenshot capture.

## Verdict

The current baseline is not release-ready against `docs/swiftui-migration-acceptance-matrix.md`. The SwiftUI launch, first-account authentication boundary, and share-composer content are present, but ordinary authenticated app use still enters the legacy Storyboard application. The available evidence does not establish complete SwiftUI migration, functional parity, or pixel parity.

## Release-blocking findings

### 1. ARCH-01: authenticated runtime still requires Main.storyboard

`ApplicationState.Root.legacyApplication` is selected for both an existing session and successful authentication (`MissCat/Others/App/MissCatApp.swift:31-35`, `:45-66`, `:86-98`). `MissCatRootView` then renders `LegacyApplicationView`, whose only implementation instantiates the initial controller from `Main.storyboard` (`MissCat/Others/App/MissCatApp.swift:117-180`).

`MissCatMainShellView` is defined but has no runtime call site. Consequently, the main app's timeline, note, profile, compose, notification, message, and settings acceptance rows remain backed by legacy UIKit/Storyboard/XIB code. This independently fails ARCH-01 and the explicit non-acceptance rule against Storyboard/XIB screens in ordinary flow.

The share extension is further along: `ShareViewController` installs `ShareComposerView` in a `UIHostingController`. Its extension entry still declares `MainInterface.storyboard`, however, and there is no extension E2E or visual-parity evidence. This SwiftUI content migration does not change the main-app verdict.

### 2. AUTH-03: add-account and last-account flows bypass SwiftUI authentication

The SwiftUI authentication flow is used only by the top-level no-session route. Inside the authenticated legacy application, add-account, logout, and missing-account recovery instantiate the Storyboard `StartViewController` directly (`MissCat/View/Main/AccountsListViewController.swift:135-161`; `MissCat/View/Main/HomeViewController.swift:305-331`).

This creates two authentication implementations with different error, retry, persistence, and navigation behavior. AUTH-03 cannot pass until all account-entry paths share the tested SwiftUI flow or a single injected authentication coordinator.

### 3. AUTH-02: callback validation is a substring check

`MissCatAuthenticationService.callbackMatches` accepts any absolute URL containing the callback string (`MissCat/SwiftUI/Authentication/MissCatAuthenticationService.swift:84-86`). That includes unrelated hosts with the expected URL embedded in a path or query. The browser uses this predicate to begin token exchange (`MissCat/SwiftUI/Authentication/MissCatAuthenticationBrowserView.swift:149-160`).

Callback acceptance must compare normalized URL components (scheme, host, port, and allowed path) and have unit coverage for lookalike hosts, encoded query values, fragments, and duplicate navigations. The existing `isCompletingAuthentication` and per-URL browser guards reduce duplicate work but do not repair origin validation.

### 4. VIS-01 and REL-01: the only confirmed candidate fails, and the required suite is absent

The Xcode project has app, share-extension, and unit-test targets only; there is no UI-test or snapshot target and no `MissCatUITests` source tree. There is also no fixture-backed capture runner or `visualReady` implementation.

The integration agent confirmed a normal-launch SwiftUI Welcome capture at `artifacts/screenshots/swiftui/welcome-iphone16pro-ios18.6.png` in its worktree. Direct comparison against the selected legacy reference is a hard failure:

- full image: 3,027,518 / 3,162,132 changed pixels (0.957429354625), normalized RMSE 0.124123;
- status-bar-masked: 2,847,751 / 2,937,820 changed pixels (0.969342872392), normalized RMSE 0.147354670021.

That is far beyond the documented 0.10% changed-pixel ceiling. A single failing candidate is not a replacement for baseline/current/diff triplets covering all historic and required deterministic states, so VIS-01 and REL-01 remain unresolved.

### 5. VIS-01: comparator does not implement the documented gate

`scripts/compare-screenshots.sh` gates changed-pixel ratio and optional normalized RMSE (`:297-352`). The required protocol additionally gates mean absolute RGBA error, SSIM, and maximum connected changed-region size (`docs/migration-test-matrix.md:99-115`). Those metrics are neither calculated nor written to `summary.json`.

The script self-test passes and covers dimensions, masks, fuzz, deterministic artifacts, RMSE, and large scientific-notation pixel counts. It should be retained, then extended to the complete documented metric set and invoked by a batch manifest that fails on missing cases.

### 6. VIS-02: the unused shell cannot establish identical design

The proposed bottom bar uses SF Symbols (`MissCat/SwiftUI/MainShell/MissCatMainShellView.swift:271-328`), while the legacy contract uses the checked-in Font Awesome/tab assets and historical raster output. Even before runtime integration, substituting glyph families changes outlines, optical sizing, and baseline placement. An explicit approved asset mapping plus screenshot evidence is required; code-level geometry constants are insufficient.

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
