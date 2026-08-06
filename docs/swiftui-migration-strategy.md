# MissCat complete SwiftUI migration strategy

Date: 2026-08-07

Strategy baseline: `migration/swiftui-main` at `cdf01f1`

Authority: `docs/legacy-functional-inventory.md`, `docs/swiftui-migration-acceptance-matrix.md`, and `docs/migration-test-matrix.md`

## Outcome and non-negotiable decisions

The target is one current-iOS application and share extension whose app-owned UI, navigation, and state ownership are SwiftUI-native. UIKit is allowed only as a narrow Apple-framework adapter where SwiftUI has no equivalent, such as `WKWebView`, camera, activity, Safari, player, and the share-extension host. An adapter may not own app navigation or silently fall back to a legacy controller.

The migration is governed by these decisions:

1. **Progress is measured over the fixed 45 inventory surfaces.** `docs/ui-migration-surfaces.tsv` is the single source of truth. Runtime ownership and acceptance are separate. A detached SwiftUI type does not change runtime ownership.
2. **The authenticated root is cut over atomically, not screen by screen.** A fixture-only SwiftUI root is wired early for automated testing. The ordinary user route changes only after the root-cutover gate in this document passes; it then has no Storyboard fallback.
3. **Every request is account scoped at creation.** New code may not read `MisskeyKit.shared`, a global current user, or `Theme.shared` while an operation is in flight. Account switches cancel the old scope before the new one becomes visible.
4. **The 2020 Pods are a temporary legacy build aid, not the new architecture.** Existing source patches are frozen. A SwiftUI surface cannot be accepted while its live path depends on a patched Pod API.
5. **Visual parity is quantitative and state matched.** Both SSIM and changed-pixel similarity must independently be at least `0.90`; a passing average is not sufficient. Every accepted surface also needs functional and test evidence.
6. **`build-for-testing` is only compilation evidence.** It is never recorded as a passed test. Test evidence requires an executed test action and a retained `.xcresult` with zero unexpected failures and zero required skips.
7. **Live credentials are supplemental E2E input only.** They never enter CI, fixtures, screenshots, logs, shell history committed to the repository, or archived artifacts.

## Fixed progress model

### Required fields and invariants

The canonical ledger is `docs/ui-migration-surfaces.tsv`, with exactly the 45 rows derived from the functional inventory. `scripts/report-ui-migration.sh` must reject a missing, duplicate, or extra ID.

The primary fields have deliberately different meanings:

- `runtime_owner=swiftui|uikit`: the framework rendering the ordinary reachable route in the current integrated commit. A source file, preview, launch argument, or test-only route does not alter this value.
- `migration_state=legacy|migrating|accepted`: delivery status. `migrating` includes detached or incomplete SwiftUI work. `accepted` is permitted only when `runtime_owner=swiftui` and all evidence below exists.

The current `cdf01f1` baseline is:

| Metric | Count | Ratio |
| --- | ---: | ---: |
| SwiftUI ordinary runtime owner | 5 / 45 | 11.1% |
| UIKit ordinary runtime owner | 40 / 45 | 88.9% |
| Accepted | 0 / 45 | 0.0% |
| Migrating | 25 / 45 | 55.6% |
| Legacy | 20 / 45 | 44.4% |

The five SwiftUI-owned inventory surfaces are Login IDs `04`–`07` and Share extension ID `45`. The detached main shell, feed, note-row, detail, and compose implementations remain UIKit-owned because authenticated ordinary use still enters `LegacyApplicationView`.

`accepted` requires all of the following for that row:

- the ordinary route is SwiftUI-owned and has no UIKit fallback;
- every required behavior in the inventory and linked acceptance IDs works, including error and cancellation paths;
- applicable unit, request-contract, stream-integration, UI/E2E, accessibility, and snapshot tests have executed successfully;
- the baseline and candidate represent the same deterministic state;
- SSIM is at least `0.90` and changed-pixel similarity is at least `0.90` independently;
- evidence names the tested commit, Xcode/runtime/device, `.xcresult`, screenshot pair, and metric JSON;
- no unresolved P0/P1 defect applies to the row.

To keep the main ledger readable, detailed evidence should live in a manifest keyed by the same ID. Required evidence fields are:

```text
id
acceptance_ids
ordinary_route
functionality_evidence
test_evidence        # command, commit, runtime, xcresult
visual_evidence      # baseline, candidate, diff, SSIM, changed similarity
blockers
assigned_bundle
reviewed_by
```

CI must join the two files by ID and fail if there are not exactly 45 rows, if an accepted row lacks any required evidence, if an accepted row is UIKit-owned, or if the recorded evidence commit is not an ancestor of the build under review. Runtime-owner ratio is the migration ratio; accepted ratio is the completion ratio. Neither may be replaced by line counts or file counts.

## Delivery path: feature bundles, not individual screens

No agent is assigned one screen in isolation. A feature bundle includes its routes, state, dependencies, unhappy paths, tests, and visual evidence. `N` below counts coherent user capabilities and is at least five wherever practical; the fixed 45 ledger remains the reporting denominator.

### Critical path and parallel lanes

```text
A. Auth + account kernel
        |
        v
B. Shell / feed / note / compose vertical milestone
        |
        v
C. Profile + social graph
        |
        v
D. Notifications + direct messages
        |
        v
E. Settings + reactions
        |
        +---- ordinary SwiftUI root cutover gate
        v
F. Push + share extension
        |
        v
G. Legacy source/resource/Pod removal and release audit

Parallel from A onward:
  P1 Design tokens + MFM/emoji/media
  P2 Deterministic fixture server + UI/snapshot/visual tooling
  P3 Native REST/WebSocket client + contract fixtures
  P4 Independent reviewer and security audit
```

Parallel work may prepare later bundles, but integration follows the critical path. A later bundle cannot introduce a second router, account store, API client, cache, or theme source.

### A — Authentication and account kernel (`N=9`)

Ledger focus: `04`–`07`, `37`. Acceptance focus: AUTH-01 through AUTH-03, STORE-01, STORE-02, ARCH-03.

Deliver as one integrated bundle:

1. exact legacy Start, Terms, instance editor, and browser states;
2. current Misskey MiAuth/session flow with exact callback origin validation;
3. cancel, retry, duplicate callback, duplicate account, and failure-without-save behavior;
4. `AccountRepository` plus Security-framework keychain vault;
5. idempotent app-group/defaults/keychain/theme/reaction migration;
6. add, switch, delete current/noncurrent/last account flows through the same auth coordinator;
7. immutable account-scoped dependency creation;
8. mock auth server contract tests and UI journey E2E-01/E2E-02;
9. Start/auth visual evidence and redacted manual live-login checklist.

This bundle is the first integration gate because every later request and stream must bind to the same account scope. The current fixed app-secret/session implementation is not a valid substitute for MiAuth on a current instance.

### B — Shell, feed, note, detail, search, and compose vertical milestone

Ledger focus: `01`–`03`, `08`–`24`, `29`–`32`, and shared state `44`. This milestone is large enough for three agents, but it integrates as one vertical slice.

#### B1 — Shell, configured timelines, and search (`N=10`)

1. header/search strip;
2. persisted account-bound Home/Local/Social/Global configuration;
3. one synchronized tap/swipe selection state;
4. forward, reverse, boundary, and rapid swipes;
5. per-tab and per-account scroll restoration;
6. five-position footer and repeat-tap scroll-to-top;
7. account dropdown and settings route;
8. initial/empty/error/retry/refresh/pagination states;
9. trends, hashtag, note search, and user search entry;
10. REST/stream channel assertions and shell golden captures.

#### B2 — Note presentation and actions (`N=11`)

1. normal/reply/renote/promotion/quote rows;
2. CW disclosure;
3. MFM and Unicode/default/custom/remote emoji;
4. 1–4 media mosaic, sensitive reveal, gallery, and player;
5. URL preview and bounded cache;
6. polls and stream updates;
7. reaction chips and picker;
8. reply, renote, and quote actions;
9. overflow/copy/browser/share/block/report/delete;
10. ancestor/root/child thread, pagination, and nested navigation;
11. optimistic rollback, exactly-once request traces, and visual fixtures.

#### B3 — Compose family (`N=9`)

1. normal compose;
2. reply;
3. quote and immediate renote;
4. account and visibility selection;
5. validation at whitespace and 1,499/1,500/1,501 graphemes;
6. 1–4 ordered images and single-video exclusivity;
7. media edit, description, NSFW, upload progress, cancellation, and retry;
8. CW, emoji, and now-playing behavior;
9. exactly-once post completion, request contracts, UI E2E, and snapshots.

Compose poll and location were not reachable legacy features. For the shortest safe parity path, neither appears in the ordinary route: remove the dormant location code and keep compose poll out of the shipping UI unless the product owner explicitly promotes it. If promoted, poll becomes a fully tested capability in B3; it may not remain half functional. Timeline poll display and voting remain required.

The present B code is useful scaffolding but not accepted: its runtime route is UIKit, navigation callbacks default to no-ops, configured accounts/tabs are not wired, and important note/media/action behavior is incomplete.

### C — Profile, users, and social graph (`N=8`)

Ledger focus: `24`–`28`. Acceptance focus: USER-01 and PROFILE-01 through PROFILE-03.

The bundle includes own profile, other profile, Notes/Notes & Replies/Media tabs, followers, following, user/list/search results, follow/unfollow rollback, avatar and bio links, and sparse profile editing with banner/avatar upload/reset. It must fix the legacy false-success and empty-string overwrite defects rather than reproduce them.

Profile and user-list endpoints are added to the native API actor before views call them. The three profile tab queries and all follow/edit request bodies need contract tests. Capture the legacy profile baseline with deterministic fixtures before deleting the controller.

### D — Notifications and direct messages (`N=7`)

Ledger focus: `33`–`36` and the notification part of `44`. Acceptance focus: NOTIF-01, MSG-01, and MSG-02.

The bundle includes six notification variants, REST pagination, stream dedupe/order, account switching, in-app banner routing, message history, conversation paging, text send/retry, keyboard behavior, and link routes. Sender identity is captured from the conversation owner, never read later from a global current account.

Current-server capability discovery for direct messages is a contract-test task, not grounds to silently remove the feature. If a supported current Misskey endpoint cannot provide the legacy contract, that remains an explicit P1 product decision and release blocker.

### E — Settings, design, reactions, licenses, and app states (`N=8`)

Ledger focus: `38`–`44`. Acceptance focus: HOME-02, SET-01 through SET-03, VIS-02, VIS-03.

The bundle includes Settings root, tab add/delete/reorder/rename/account binding, light/dark/custom accent, reaction instance/favorites/history/search/reorder, generated license list/detail, About, shared loading/empty/error/nano banners, and removal of unreachable account/theme routes. Reaction history migration remains instance scoped and capped at 14.

This bundle consumes one typed design-token source. It may not wrap Eureka, ChromaColorPicker, FloatingPanel, or XLActionController as permanent architecture.

### Ordinary SwiftUI root cutover gate

Do not replace `ApplicationState.Root.legacyApplication` in production merely because shell/feed/compose compile. Before the ordinary root changes, all of these conditions must be true on one integrated commit:

- A through E are integrated and all reachable main-app routes have a SwiftUI destination;
- account add/switch/delete/last-account recovery uses the single SwiftUI auth coordinator;
- the root receives an `AppContainer` and current `AccountScope`; no view creates a live client from global cache state;
- all five footer destinations, Search, Profile, Settings, Note Detail, Compose, media/gallery/player, and action sheets close within SwiftUI navigation;
- tap plus horizontal swipe, reverse/boundary/rapid swipe, per-tab scroll, repeated footer tap, and account-state isolation UI tests pass;
- required P0 unit, contract, stream, and fixture E2E tests pass with an archived `.xcresult`;
- all eleven historic visual states have same-state baseline/current/diff triplets and both metrics are at least `0.90`;
- a static route audit finds no ordinary call to `UIStoryboard`, `UINib`, `instantiateViewController`, or a legacy `UIViewController`;
- the new root has run fixture offline/error/cancellation and rapid multi-account stress journeys;
- the independent reviewer has no open P0 root-cutover finding.

Until then, expose the complete SwiftUI root only through a deterministic UI-test launch argument and previews. That route must use fixture dependencies and must never read a live keychain. At cutover, delete the legacy root case and fallback in the same commit. Do not keep an automatic “if new route fails, show Storyboard” path.

Legacy UI resources may remain temporarily in a non-shipping reference target after cutover so final diffs can be reproduced. They are removed from the shipping target immediately and deleted from the repository in G after evidence is archived.

### F — Push and share extension (`N=8`)

Ledger focus: notification/banner state `34` and share `45`. Acceptance focus: NOTIF-02, SHARE-01 through SHARE-03, PUSH-01.

The bundle includes permission states, APNs/FCM token rotation, per-account WebPush registration/removal, foreground presentation, background tap/deep link, malformed/wrong-owner payloads, relay security/observability, share text/URL/1–4 ordered images, account/visibility persistence, progress/cancel/retry, and exactly-once host completion.

The extension uses `NSExtensionPrincipalClass` with the minimum UIKit host required by Apple and SwiftUI-owned content. Remove `MainInterface.storyboard` and the unused UIKit account/visibility controllers. App and extension share the same account/keychain module and signed access group.

### G — Legacy removal and release audit (`N=10`)

This is not a cleanup that can be deferred after “completion.” It is part of completion:

1. remove `Main.storyboard` and every app UI XIB from target and repository;
2. remove `MainInterface.storyboard` and unused share controllers;
3. remove legacy view controllers, view models, Rx bindings, and duplicate persistence models;
4. remove `LegacyApplicationView` and every runtime Storyboard/nib loader;
5. remove all CocoaPods integration phases/configurations and `Podfile`/lock after replacements land;
6. remove post-install source patches and stale framework/linker settings;
7. remove obsolete assets/fonts only after visual mapping proves they are unused;
8. regenerate license inventory from the final dependency graph;
9. run clean-checkout build/test/visual/security jobs on current stable tooling;
10. complete the 45-row evidence audit and independent release sign-off.

## Target architecture

### Root, routing, and navigation

```text
MissCatApp
└─ AppContainer                    immutable dependency graph
   └─ AppStore @MainActor          root state only
      ├─ .booting
      ├─ .authentication(AuthPath)
      └─ .authenticated(AccountScope, AppRouter)
         ├─ selectedRootSection
         ├─ timelineSelection
         ├─ NavigationPath per root section
         ├─ sheet route
         └─ full-screen route
```

`AppRouter` owns typed route values such as note ID, user ID, compose mode, conversation owner/peer, settings destination, gallery start index, and notification deep link. Views emit intents; they do not instantiate controllers, reach into cache, or build clients. Each bottom section retains an independent navigation path and scroll state. Modal routes are mutually exclusive and restorable where required.

The root bootstrap order is fixed: migrate persistent data, resolve account metadata plus keychain token, create `AccountScope`, repair theme tabs against available accounts, then publish authenticated UI. A missing or corrupt credential returns to recoverable account/auth UI rather than crashing or presenting legacy code.

### Account-scoped dependency graph

`AccountScope` is an immutable, `Sendable` value containing at least account ID, username, normalized instance, a non-secret credential handle, and a monotonically increasing generation. It creates or references:

- `MisskeyAPIClient` actor;
- `MisskeyStreamClient` actor;
- account-keyed repositories;
- in-memory cache namespace;
- upload coordinator;
- push registration coordinator;
- cancellation registry.

The API token is resolved inside the client from the keychain vault and is never exposed to a view or stored in `UserDefaults`. Every repository method receives or captures the scope at operation creation. Results include their generation; stale generations are discarded even if a lower-level callback ignores cancellation.

On account switch: mark the old generation obsolete, cancel child tasks, close its WebSocket subscriptions, cancel/finish uploads that cannot safely transfer, clear only its transient UI bindings, persist the new account ID, create the new scope, then publish it. Cache keys include account/instance where content or authorization can differ.

### REST and streaming actors

Use a typed `URLSession` REST actor for current Misskey endpoints. Separate transport DTOs from domain models and use a central endpoint description for method, path, request body, response type, authorization requirement, and redaction policy. Contract tests compare recorded requests to fixtures and reject unexpected network calls.

Use one WebSocket actor per account scope, built on the current Apple WebSocket API unless a maintained dependency proves necessary. The actor multiplexes channel subscriptions, reference-counts note captures, reconnects with bounded jitter, emits typed `AsyncSequence` events, performs missed-note catch-up, and closes when the scope ends. Reducers own ordering/dedupe and reaction/unreaction/delete/poll updates. Views never call WebSocket APIs.

### Persistence, keychain, and cache

- `AccountRepository` actor owns app-group metadata and current account selection.
- `KeychainVault` actor uses the Security framework and the signed shared access group.
- `LegacyMigration` is versioned, resumable, and idempotent; every step has before/interrupted/after/corrupt fixtures.
- `PreferenceRepository` owns visibility and theme/tab configuration.
- `ReactionPreferenceRepository` safely decodes and migrates legacy archives.
- `MediaCache` and `URLPreviewCache` are bounded actors with cancellation, expiry, memory-pressure handling, and deterministic test clocks.

No new code calls `UserDefaults.standard`, shared app-group defaults, or keychain APIs directly outside these adapters.

### Theme and design tokens

One `ThemeStore` converts persisted theme configuration into immutable `MissCatDesignTokens`: colors, typography, metrics, separators, corner radii, shadows, icon assets, animation timing, and safe-area behavior. Tokens are injected through SwiftUI environment and can be fixed by snapshots. Default-size typography must match the legacy raster; accessibility sizes expand without hiding controls.

Do not assume SF Symbols are visually interchangeable with the legacy Font Awesome/tab assets. Use the legacy asset/font when licensing and screenshots permit, or create an approved replacement mapping. The choice is accepted only by the visual gate.

### MFM, emoji, media, and previews

Split MFM into a pure parser, semantic attributed model, tap destinations, emoji resolver, and renderer. The parser and destinations are platform independent. A temporary `UIViewRepresentable` for YanagiText is allowed only if it is isolated, account independent, snapshot tested, and has a recorded removal reason; it cannot own navigation.

Animated PNG/GIF/SVG/emoji decoding sits behind one media protocol with bounded cache, reuse cancellation, frame timing, and memory tests. Attachment layout, sensitive reveal, zoom/paging gallery, AV playback, photo/camera selection, editing, upload preparation, and URL preview are independent services with deterministic fixtures.

### Cancellation and exactly-once writes

Every long-lived load, stream, upload, and mutation has an owner and cancellation point. SwiftUI uses `.task(id:)` for lifetime-bound reads; stores retain explicit tasks only for work that outlives a view transition. Write reducers use stable operation IDs, a submit lock, and terminal-state guards. Cancellation cannot report success, and a retry cannot duplicate a completed write.

Callback-based legacy adapters use checked continuations with a one-resume gate until the endpoint moves to the native client. A callback adapter is not accepted without tests for duplicate callback, late callback after cancellation, and missing callback timeout.

## Dependency retirement policy

### Keep-or-replace test

A third-party dependency may ship only when all conditions hold:

- it is maintained and supports the final Xcode, Swift mode, deployment target, and current iOS runtime without source mutation;
- its public API is isolated behind a MissCat-owned protocol;
- it materially reduces security or correctness risk versus a native/internal implementation;
- deterministic tests cover MissCat's use of it, including cancellation and malformed input;
- its license and notices are included and its transitive graph is acceptable;
- it has no checked-in credentials, binary provenance gap, or unbounded cache/background behavior.

If one condition fails, replace it with Apple frameworks or a small checked-in module with tests.

### Locked-source patch deadline

The current `Podfile` mutates FloatingPanel, APNGKit, MisskeyKit, Eureka, and RxCocoa sources. These patches are grandfathered only to keep the legacy reference build available. Effective immediately:

- no new dependency-family source patch may be added;
- every existing patch has a named replacement endpoint/component and a hash/assertion so it fails loudly if upstream source changes;
- a surface cannot change to `runtime_owner=swiftui` or `accepted` while its ordinary live path uses a patched API;
- the current feed/compose use of patched MisskeyKit poll/upload APIs must move behind the native client before root cutover;
- all patched Pods are removed from the shipping app/extension before the ordinary SwiftUI root cutover commit; a non-shipping legacy-reference configuration may retain the frozen patches only until its evidence is archived, after which G deletes the patch blocks and Pods entirely.

### MisskeyKit strangler sequence

Keep a temporary `LegacyMisskeyAdapter` behind repository protocols, then replace capabilities in this order:

1. MiAuth, `users/i`, and account identity;
2. app-group/keychain ownership and client factory;
3. timeline REST and note/detail/search conversion;
4. streaming channels, capture, reconnect, and reducers;
5. create/upload/reply/renote/reaction/vote/delete/favorite mutations;
6. profile, relationship, follow, edit, and user lists;
7. notifications and direct messages;
8. push/WebPush registration;
9. share-extension posting;
10. remove `MisskeyKit`, Starscream 3.1.1, and every legacy callback type.

Each endpoint moves only with request/response/error contract fixtures. Do not expose MisskeyKit models in new domain interfaces; otherwise the strangler cannot finish.

### Final dependency inventory

The target is CocoaPods zero. Remove PolioPager, RxSwift/RxCocoa/RxDataSources, Agrume, SkeletonView, FloatingPanel, XLActionController, XLPagerTabStrip, MessageKit/InputBarAccessoryView, Eureka, ChromaColorPicker, SwiftLinkPreview/Cache, iOSPhotoEditor, APNGKit/Gifu/SVGKit, KeychainAccess, MisskeyKit, and Starscream after their bundle exits pass.

Final shipping dependencies should be:

- Apple frameworks and MissCat-owned typed modules for UI, REST/WebSocket, Security, media, and caches;
- optionally the current supported Firebase Messaging package through Swift Package Manager **only** if the accepted push architecture retains the FCM relay;
- no Firebase dependency if B6 proves and adopts direct APNs delivery instead.

The push choice is recorded before B6 implementation, with device evidence and relay migration impact. The final license screen is generated from the actual resolved Swift package graph plus checked-in third-party source notices.

## Test and evidence architecture

### Deterministic environment first

Before accepting UI work, add a fixture HTTP/WebSocket server and launch configuration with fixed account IDs, tokens that are unmistakably fake, notes, users, images, SVG/GIF/APNG, clock, latency, failures, and stream events. It records redacted request/event traces and fails unexpected traffic. CI must not reach a live instance.

Visual runs fix locale `ja_JP`, timezone `Asia/Tokyo`, clock, appearance, content-size category, status bar, account, theme, scroll offset, and animation frame. Each screen publishes an accessibility `visualReady` signal only after fonts, images, emoji, previews, and intended loading state settle. A fixed timeout is a failure, not visual readiness.

### Evidence layers per bundle

| Layer | Required proof |
| --- | --- |
| Unit | reducers, parsers, validation, migration, state repair, cancellation, error rollback |
| Contract | exact endpoint/path/body/header semantics and typed response/error decoding |
| Stream integration | connect/channel/reconnect/catch-up/dedupe/events/teardown with fake WebSocket |
| Component/snapshot | deterministic states, both themes, long content, compact/current widths |
| UI/E2E | visible result **and** recorded request/event/persistence trace |
| Live E2E | manual login/current-server compatibility only; redacted pass/fail checklist, no secret artifacts |
| Visual | baseline/current/diff/overlay plus JSON containing both required metrics |
| Stress/a11y | rapid account/tab/navigation, offline/slow/cancel, VoiceOver, Dynamic Type, keyboard |

`xcodebuild build` and `xcodebuild build-for-testing` prove only that compilation/linking succeeded. Executed evidence must name `xcodebuild test` or `test-without-building`, list the selected tests, preserve `.xcresult`, report executed/failure/skip counts, and identify the exact commit and runtime. Required tests may not be focused out or skipped.

### Screenshot protocol

For all eleven historic states and all additional states in `docs/migration-test-matrix.md`:

1. capture or construct the legacy reference using the same fixture data before deleting its controller;
2. preserve historic screenshots unchanged and document any reference-canvas safe-area transform;
3. capture the SwiftUI state at identical pixel dimensions without stretching;
4. mask only recorded OS-owned nondeterminism, never app UI;
5. threshold a pixel as changed at more than `8/255` per channel and calculate changed-pixel similarity;
6. calculate SSIM over the same evaluated app-owned pixels;
7. require changed-pixel similarity `>=0.90` **and** SSIM `>=0.90`;
8. emit baseline, candidate, amplified diff, overlay/side-by-side, and JSON metrics;
9. have a reviewer inspect the overlay at 100% even after numerical pass.

The comparator calculates changed-pixel similarity and SSIM independently. The
45-ID requirement inventory expands the states/devices/appearances and the
evidence verifier rejects missing captures, hash drift, relaxed thresholds,
unreviewed overlays, or non-ancestor evidence commits. Keep every surface in
`migrating` until that strict gate and its functional requirements both pass.

### Mandatory tab and account behavior suite

The same selected-tab binding must pass UI tests for direct tap, forward swipe, reverse swipe, first/last boundary swipe, rapid alternating tap/swipe, page-list replacement, background/relaunch restoration, and account switch. Every tab retains its own scroll position per account, then restores the correct position when returning. Switching accounts while REST or stream work is active must cancel the old scope and never display old-account notes. Re-tapping Home or Notifications verifies scroll-to-top rather than only selected tint.

### Credential policy

Live credentials are used only in a human-authorized E2E run on the designated simulator/device. Token strings, callbacks containing secrets, APNs/FCM tokens, WebPush keys, private notes, and private media are redacted before output and are never archived. The fixture suite is the reproducible release evidence; live E2E adds a dated compatibility result, not a reusable credential artifact.

## Git and multi-agent operating model

### Agent admission and isolation

Official implementation subagents are newly created `gpt-5.6-sol` agents at `xhigh` reasoning. Every task has a bounded feature bundle, acceptance IDs, branch name, evidence contract, and non-overlapping file ownership.

Each agent works in a full independent clone such as `/private/tmp/misscat-<bundle>.<random>/repo` and a branch `agent/<bundle>`. Do not use or mutate the dirty primary worktree. Each clone has its own:

- CocoaPods sandbox and lock verification while Pods remain;
- DerivedData directory;
- test result and visual-artifact directory;
- simulator selection/clone when UI execution is required;
- git identity `YuigaWada <yuigawada@gmail.com>`.

Never share `Pods`, DerivedData, `.xcuserstate`, or generated screenshots between feature branches. Do not commit DerivedData, live tokens, device IDs tied to credentials, or user-specific Xcode state.

### Commit discipline

Commits are small, ordered, and use English bracket subjects, for example:

```text
[add] build account scoped API client
[add] implement profile feature bundle
[test] cover profile contract and UI journeys
[fix] cancel stale account streams
[update] record profile visual evidence
```

No attribution trailers are added. Generated project changes are isolated from feature source changes where possible. Because `project.pbxproj`, schemes, and Pod integration are high-conflict files, one integration owner applies target membership/scheme changes per cadence. An agent may keep a local pbx change to build its clone, but submits source/test commits separately so the integrator can reapply project membership safely.

### Integration cadence and gates

Integrate the shared architecture commit before dependent feature code. A feature branch rebases onto the latest integration head, reruns its full bundle gate in its own clone, then hands over ordered commits and evidence. Main accepts at most one pbx/scheme mutation at a time.

A bundle is integration-green only when:

- scoped unit/contract/stream tests execute and pass;
- required UI/E2E/snapshots execute and pass;
- visual cases pass both `0.90` metrics or are explicitly still marked `migrating`;
- clean build warnings are triaged;
- secrets scan and `git diff --check` pass;
- ledger/evidence changes do not claim acceptance prematurely;
- reviewer findings are resolved or recorded as blocking.

Integration-green is different from acceptance-green: incomplete visuals may be integrated as `migrating`, but they do not advance accepted/45.

### Manual Preview policy

The user-designated `MissCat Manual Preview` simulator is overwritten only at a green milestone after the integrated commit has passed its relevant tests. Never reinstall a known broken auth candidate merely because it builds. Record the installed commit and runtime outside credential-bearing logs. A failed Manual Preview run returns to the feature clone for repair; it does not redefine the gate.

Manual Preview and authentication E2E builds must retain their signed Keychain and application-group entitlements. Build the Simulator app with local ad-hoc signing enabled (the Xcode default for Simulator builds), never with `CODE_SIGNING_ALLOWED=NO`, and run `scripts/verify-simulator-keychain-entitlements.sh /path/to/MissCat.app` before installation. Unit-test-only unsigned products do not qualify as installable authentication evidence.

## Current-state audit at `cdf01f1`

### Proven integrated

- SwiftUI `@main` launch and logged-out authentication presentation exist.
- SwiftUI share-composer content is hosted by the extension.
- acceptance, functional inventory, test matrix, and reviewer audit documents exist.
- a changed-pixel/SSIM comparator, deterministic self-test, and fixed visual
  acceptance inventory exist.
- compose domain/service/controls/screens and 21 compose test methods are on main.
- feed domain/repository/store/note row/screens/pager and 11 feed test methods are on main.
- 64 XCTest methods are present in source across current test files, including one no-op example.
- deployment target declarations are iOS 17.0 and the app uses a SwiftUI entry point.

These are source facts, not claims that all tests or user flows pass.

### Unwired or incomplete

- existing sessions and successful authentication still route to `LegacyApplicationView`, which loads `Main.storyboard`;
- the detached shell/feed/compose types have no ordinary root call site;
- add-account and last-account recovery still use the legacy Start controller;
- current authentication uses old app/session exchange, a fixed secret, and substring callback matching; the reported live simulator path fails with “データ処理に失敗しました”;
- feed defaults are hard coded rather than repaired from persisted account-bound tab configuration;
- feed navigation closures default to no-ops, so source presence does not prove working navigation;
- streaming has no proved reconnect/catch-up contract and still relies on the locked MisskeyKit/Starscream path;
- the SwiftUI row uses basic URL detection, not the required MFM/emoji contract;
- URL preview, full gallery/player, full overflow actions, reaction picker, and detail pagination are incomplete or absent;
- the last action button conflates favorite and overflow behavior;
- shell glyphs use SF Symbols without visual acceptance against the legacy assets;
- share content remains behind `MainInterface.storyboard`, duplicates account persistence, and uses MisskeyKit;
- no UI-test or snapshot target, fixture server, `visualReady` implementation, batch visual manifest, or current CI release gate exists;
- current GitHub Actions selects Xcode 11.3.1/iOS 13.3, incompatible with the present iOS 17.0 project target;
- the evidence inventory remains incomplete even though the comparator and strict
  gate semantics now exist;
- Storyboards, XIBs, UIKit controllers, Rx code, patched Pods, and old build settings remain in the shipping targets.

### Test evidence boundary

The reviewer document proves a 32-test execution at commit `99aee13`, before the compose/feed commits. Source at `cdf01f1` contains 64 test methods, but this branch contains no tracked `.xcresult` or current-head executed-test report. Prior claims of normal build or `build-for-testing` success therefore do not prove the compose/feed XCTest methods ran. The next integration gate must execute the complete current suite and preserve commit-specific evidence.

### Release blockers

P0 blockers:

1. current live authentication failure and no integrated MiAuth contract;
2. authenticated Storyboard root and duplicate auth entry routes;
3. no account-scoped root dependency graph and continuing global/locked-client paths;
4. shell/feed/compose absent from ordinary runtime;
5. no fixture-backed UI/E2E/snapshot targets or current CI;
6. no complete visual comparator or 11-state passing evidence;
7. share Storyboard/duplicate persistence/no host E2E;
8. push relay, entitlement, token-rotation, and per-account evidence gaps;
9. credential-shaped files/fixed secrets requiring removal, rotation, and secret-manager inputs;
10. no clean-checkout release evidence on the newest supported stable toolchain/runtime.

P1 blockers include exact shell assets/geometry, full MFM/animated emoji/media, URL preview, note/detail actions, Search/users, Profile/edit, Notifications/DM, Settings/reactions, accessibility, cancellation stress, and license accuracy.

## Next three bundles

1. **`agent/auth-account-kernel`** — integrate MiAuth, exact callback validation, account/keychain/migration actors, add/switch/delete/last-account flows, auth contract tests, E2E-01/E2E-02, and Start/auth visuals. This must land first.
2. **`agent/shell-feed-root`** — consume `AccountScope`; wire configured tabs, shell/footer/account dropdown, REST/stream actors, Search/trends, fixture-only root, tab tap/swipe/scroll/account UI tests, and shell/feed visuals. It may prepare in parallel but lands after bundle 1.
3. **`agent/note-compose-actions`** — finish MFM/media/preview/poll/action/detail and connect normal/reply/quote/renote/media compose with exactly-once contract/UI tests and row/compose visuals. It consumes bundles 1 and 2 and does not add another client or router.

## Decision log

| ID | Decision | Rationale / exit condition |
| --- | --- | --- |
| D-001 | Fixed 45-row ledger is authoritative. | Prevents code-file progress inflation; complete only at accepted 45/45. |
| D-002 | Runtime ownership and acceptance are separate. | Detached SwiftUI remains UIKit-owned on ordinary runtime. |
| D-003 | Both visual metrics must independently be `>=0.90`. | Implements the product owner's definition without averaging a failure. |
| D-004 | Fixture root early, ordinary root atomically after A–E gate. | Provides continuous integration without shipping broken fallback paths. |
| D-005 | Account scope captures immutable ID/generation. | Prevents cross-account reads, bubbles, uploads, streams, and push registration. |
| D-006 | Native typed REST/WebSocket actors replace MisskeyKit by endpoint. | Makes current API, cancellation, and testing auditable. |
| D-007 | Existing Pod source patches are frozen and expire before root cutover. | A patched 2020 dependency cannot become final SwiftUI architecture. |
| D-008 | CocoaPods final inventory is zero. | Removes obsolete UI/Rx/network dependency graph and patch machinery. |
| D-009 | UIHosting/System adapters are allowed but cannot own app navigation. | Satisfies complete SwiftUI UI while respecting Apple framework boundaries. |
| D-010 | Compose poll/location stay out of ordinary parity route unless promoted. | They were dead/incomplete legacy paths; no half-functional controls ship. |
| D-011 | Build-for-testing is not test evidence. | Only executed tests plus `.xcresult` can prove behavior. |
| D-012 | Manual Preview updates only at green milestones. | Protects the user's login/test simulator from known broken candidates. |

## Completion and legacy-exit checklist

Completion is proven only when every item has authoritative current-commit evidence:

- [ ] `scripts/report-ui-migration.sh` reports SwiftUI owner `45/45` and accepted `45/45`.
- [ ] Every P0 and P1 acceptance-matrix row maps to passing evidence; no unresolved defects remain.
- [ ] App, share extension, unit, contract/integration, UI/E2E, and snapshot targets build from a clean checkout.
- [ ] Full tests execute on the newest supported stable Xcode/iOS simulator and compact/current-width devices, with retained `.xcresult`, logs, counts, and zero required skips.
- [ ] All twenty E2E journeys pass with redacted machine-readable request/stream/persistence traces.
- [ ] Tap and horizontal swipe tab movement, reverse/boundary/rapid changes, repeated footer tap, per-tab scroll, relaunch, and multi-account state pass.
- [ ] All eleven historic goldens and every additional required state have baseline/current/diff/overlay/JSON artifacts at exact dimensions.
- [ ] Every visual case has SSIM `>=0.90` and changed-pixel similarity `>=0.90`, plus reviewer overlay sign-off.
- [ ] `visualReady` is deterministic and no baseline is silently regenerated.
- [ ] VoiceOver, Dynamic Type, Reduce Motion, long Japanese/Latin text, keyboard, and safe areas pass.
- [ ] Offline/timeout/500/cancel/retry, fast scrolling, reconnect, rapid navigation, and rapid account switching show no stale data, duplicate writes, task leak, or crash.
- [ ] Existing accounts, tokens, current account, visibility, theme/tabs/color, reactions/history, and latest notification migrate idempotently without re-login.
- [ ] Tokens remain keychain-only; app/share signed access groups match; logs/artifacts/defaults/screenshots contain no secret.
- [ ] Live auth and current-server compatibility pass on the designated simulator/device with a redacted checklist only.
- [ ] Push permission/token/register/unregister/foreground/background/deep-link/multi-account cases pass; relay deployment evidence passes if retained.
- [ ] Share text/URL/1–4 images, state, progress, error, retry, cancel, and exactly-once completion pass in host E2E.
- [ ] `Main.storyboard`, `MainInterface.storyboard`, app UI XIBs, and every legacy screen/controller/view-model are removed from target and repository.
- [ ] No ordinary source call loads a Storyboard, nib, or legacy controller; only documented Apple adapters remain.
- [ ] MisskeyKit, Starscream 3.1.1, Rx, old UI/media Pods, post-install source patches, CocoaPods phases/configs, and duplicate models are removed.
- [ ] Final Swift package inventory is minimal, maintained, pinned, licensed, and represented exactly in Settings.
- [ ] Credential-shaped repository material is removed and rotated; CI/deployment use secret-manager values.
- [ ] Warning audit, static/concurrency audit, leak/performance check, secret scan, and reviewer traceability report pass on the release commit.
- [ ] Manual Preview is installed from that same green integrated commit and its tab/login/primary journeys are rechecked.

Only after this checklist and the acceptance audit pass is the objective complete. Code presence, a successful build, or an absence of newly observed crashes is not completion evidence.
