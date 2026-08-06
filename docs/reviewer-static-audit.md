# Reviewer static audit — SwiftUI migration

Date: 2026-08-07

Reviewed baseline: `origin/migration/swiftui-main` at `46a31f3` (`270820f` is an ancestor)

Review mode: source and deterministic shell tests only; no Simulator, XCTest, XCUITest, or GUI automation

## Verdict

The current baseline is not release-ready against `docs/swiftui-migration-acceptance-matrix.md`. The SwiftUI launch and first-account authentication boundary is present, but ordinary authenticated use still enters the legacy Storyboard application. No evidence currently establishes complete SwiftUI migration, functional parity, or pixel parity.

## Release-blocking findings

### 1. ARCH-01: authenticated runtime still requires Main.storyboard

`ApplicationState.Root.legacyApplication` is selected for both an existing session and successful authentication (`MissCat/Others/App/MissCatApp.swift:31-35`, `:45-66`, `:86-98`). `MissCatRootView` then renders `LegacyApplicationView`, whose only implementation instantiates the initial controller from `Main.storyboard` (`MissCat/Others/App/MissCatApp.swift:117-180`).

`MissCatMainShellView` is defined but has no runtime call site. Consequently, every timeline, note, profile, compose, notification, message, settings, and share-flow acceptance row remains backed by legacy UIKit/Storyboard/XIB code. This independently fails ARCH-01 and the explicit non-acceptance rule against Storyboard/XIB screens in ordinary flow.

### 2. AUTH-03: add-account and last-account flows bypass SwiftUI authentication

The SwiftUI authentication flow is used only by the top-level no-session route. Inside the authenticated legacy application, add-account, logout, and missing-account recovery instantiate the Storyboard `StartViewController` directly (`MissCat/View/Main/AccountsListViewController.swift:135-161`; `MissCat/View/Main/HomeViewController.swift:305-331`).

This creates two authentication implementations with different error, retry, persistence, and navigation behavior. AUTH-03 cannot pass until all account-entry paths share the tested SwiftUI flow or a single injected authentication coordinator.

### 3. AUTH-02: callback validation is a substring check

`MissCatAuthenticationService.callbackMatches` accepts any absolute URL containing the callback string (`MissCat/SwiftUI/Authentication/MissCatAuthenticationService.swift:84-86`). That includes unrelated hosts with the expected URL embedded in a path or query. The browser uses this predicate to begin token exchange (`MissCat/SwiftUI/Authentication/MissCatAuthenticationBrowserView.swift:149-160`).

Callback acceptance must compare normalized URL components (scheme, host, port, and allowed path) and have unit coverage for lookalike hosts, encoded query values, fragments, and duplicate navigations. The existing `isCompletingAuthentication` and per-URL browser guards reduce duplicate work but do not repair origin validation.

### 4. VIS-01 and REL-01: no executable UI/snapshot evidence exists

The Xcode project has app, share extension, and unit-test targets only; there is no UI-test or snapshot target and no `MissCatUITests` source tree. The repository contains the eleven historic screenshots, but no same-state SwiftUI candidate captures or baseline/current/diff triplets. There is also no fixture-backed capture runner or `visualReady` implementation.

The checked-in comparator is useful infrastructure, not visual acceptance evidence. Without deterministic UI state, current-device captures, and CI artifacts, VIS-01 and REL-01 remain unresolved.

### 5. VIS-01: comparator does not implement the documented gate

`scripts/compare-screenshots.sh` gates changed-pixel ratio and optional normalized RMSE (`:300-352`). The required protocol additionally gates mean absolute RGBA error, SSIM, and maximum connected changed-region size (`docs/migration-test-matrix.md:99-115`). Those metrics are neither calculated nor written to `summary.json`.

The script self-test passes and covers dimensions, masks, fuzz, deterministic artifacts, RMSE, and large scientific-notation pixel counts. It should be retained, then extended to the complete documented metric set and invoked by a batch manifest that fails on missing cases.

### 6. VIS-02: the unused shell cannot establish identical design

The proposed bottom bar uses SF Symbols (`MissCat/SwiftUI/MainShell/MissCatMainShellView.swift:271-328`), while the legacy contract uses the checked-in Font Awesome/tab assets and historical raster output. Even before runtime integration, substituting glyph families changes outlines, optical sizing, and baseline placement. An explicit approved asset mapping plus screenshot evidence is required; code-level geometry constants are insufficient.

## MFM crash diagnosis

The reported `EXC_BAD_ACCESS` in `MFMTests.testIgnoreSpinTag` is attributable to the old test fixture `UIFont()`, not to `simctl` launch or normal application lifecycle. `UIFont()` exposes an inherited Objective-C initializer that does not produce a valid CoreText-backed font on current iOS. `MFMEngine.generatePlaneString` immediately reads `familyName` and `pointSize`, so the invalid object faults in the XCTest host.

The integrated fix replaces all active MFM test fixtures with `UIFont.systemFont(ofSize:)`; production MFM call sites use named/system fonts with fallbacks. Regression coverage includes the original `<spin>` path and `testGeneratePlaneStringWithValidHelveticaFont`. This is a test-host object-validity issue: a normal app launched through `simctl` does not run `MissCatTests` and cannot exercise that invalid fixture. No Simulator result should be inferred from an XCTest-host crash, or vice versa.

## Reviewer-owned regression additions

`MissCatTests/MissCatTests.swift` adds deterministic coverage for two persistence failure paths:

- legacy plaintext API-key metadata is scrubbed even when Keychain reading throws;
- a failed Keychain removal leaves metadata, the credential, and current-account selection intact.

These tests use only the injected fake store and isolated `UserDefaults` suite. They were authored but intentionally not launched while the shared Simulator was reserved.

## Verification performed

```sh
git merge-base --is-ancestor 270820f origin/migration/swiftui-main
bash -n scripts/compare-screenshots.sh
bash -n scripts/test-compare-screenshots.sh
scripts/test-compare-screenshots.sh
git diff --check
```

The visual comparator self-test passed all fixtures, including the 3,162,132-pixel scientific-notation case. No secret value was copied, modified, or added by this review; an existing credential-shaped source constant was deliberately left untouched and omitted from this report.
