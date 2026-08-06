# SwiftUI migration acceptance matrix

## Release gates

The rewrite is accepted only when all P0/P1 rows below pass on the newest installed iOS simulator runtime and no required capability remains backed by a legacy Storyboard/XIB controller. “Design is identical” is evaluated by the screenshot protocol in `docs/migration-test-matrix.md`; code review alone is not visual evidence.

Definitions:

- **P0**: release blocker: data/security, launch/auth, primary read/write, or crash/loss risk.
- **P1**: required functional/visual parity.
- **P2**: legacy dormant capability; implement only if product scope promotes it, otherwise remove unreachable code cleanly.

| ID | Pri | Area | Acceptance criterion | Evidence required |
| --- | --- | --- | --- | --- |
| ARCH-01 | P0 | SwiftUI | App-owned launch, shell, screens, reusable rows, sheets, and navigation are SwiftUI; Main storyboard is not an app entry point and no legacy VC is required for user flows. Allowed system adapters are isolated. | Source/static check; launch UI test |
| ARCH-02 | P0 | Current iOS | App and extension build with warnings triaged on the newest supported stable Xcode/iOS and, at minimum during local development, the newest installed simulator; launch without compatibility crash and support current safe areas/keyboard. | Clean build log; simulator run |
| ARCH-03 | P0 | State/API | Misskey REST, streaming, cache, auth, and persistence sit behind injectable protocols/actors; views contain no direct token/keychain/network handling. | Architecture review; unit tests |
| ARCH-04 | P1 | Concurrency | No UI update occurs off-main; repeated navigation, fast scrolling, cancellation, reconnect, and account switching do not leak tasks or show prior-account data. | Stress UI tests; Instruments/manual evidence |
| VIS-01 | P0 | Golden visuals | Every historic golden state has a same-state replacement capture and diff artifact; app-owned pixels meet the defined threshold. | Baseline/current/diff triplets |
| VIS-02 | P1 | Theme | Light and dark palettes, custom accent, typography, separators, corner radii, shadows, tab underline, footer geometry, avatar/cat badge, loading skeletons, and empty/error banners match legacy. | Snapshot suite at required devices/themes |
| VIS-03 | P1 | Accessibility/layout | Dynamic Type and VoiceOver do not block any function; default content size remains pixel-compatible. Long Japanese/Latin names, RTL-safe layout, and keyboard avoidance have no clipping. | UI/a11y tests and focused snapshots |
| AUTH-01 | P0 | Start | With no account, exact start screen appears; selected instance displays; change-instance normalization works. | Unit + screenshot + UI test |
| AUTH-02 | P0 | Terms/auth | Sign-up and login require explicit Terms acceptance, support cancel/retry, current Misskey auth/session exchange, and save no account on failure. | Mock-server E2E |
| AUTH-03 | P0 | Accounts | Existing accounts upgrade without re-login; API tokens remain keychain-only; duplicate account updates safely; add/switch/delete/last-account flows work. | Migration unit tests + UI E2E |
| HOME-01 | P0 | Shell | Top search/timeline pager and five-position footer match legacy, preserve selected page, and route all items; repeated tap scrolls Home/Notifications to top. | UI tests + screenshots |
| HOME-02 | P1 | Tabs | Add/delete/reorder/rename/account-bind Home/Local/Social/Global tabs; invalid/deleted-account tabs are repaired; empty set restores defaults. | Unit + settings-to-home E2E |
| TL-01 | P0 | Timelines | Home/Local/Social/Global initial load, correct account credentials, empty/error/retry, pagination, and manual refresh work. No special-host substitution changes requested timeline semantics. | Contract tests + UI E2E |
| TL-02 | P0 | Streaming | Correct channel connects, reconnects with missed-note catch-up, deduplicates, inserts notes, applies reaction/unreaction/delete/poll updates, and stops on account/tab teardown. | Fake WebSocket integration tests |
| TL-03 | P1 | Row variants | Normal, reply, renote, promotion, quote, CW, skeleton, and mixed-content rows render and size identically with stable scroll position. | Parameterized snapshots/UI scroll test |
| NOTE-01 | P0 | Actions | Note tap/detail, author profile, reply, renote, quote, reaction add/remove, overflow, copy, browser, share, block, report validation, and own-note delete all call exactly once and reconcile errors. | Unit + UI E2E |
| NOTE-02 | P1 | MFM | Links, markdown links, mentions, hashtags, bold/strike/code, reply mark, legacy-disabled tags, Unicode/default/custom/remote emoji produce equivalent text and tap destinations. | Parser/render unit tests + snapshots |
| NOTE-03 | P1 | Emoji media | PNG/SVG/GIF/APNG load, animate at valid frame timing, cancel/reuse correctly, cache boundedly, and show placeholder/retry on failure. | Unit/integration + memory/scroll test |
| NOTE-04 | P1 | Attachments | 1–4 image mosaics match; tapped index opens zoom/paging gallery; video playback works; sensitive media is not exposed before intentional tap. | Snapshot + UI E2E |
| NOTE-05 | P1 | URL preview | Instance proxy then fallback, cancellation/cache/error behavior, exact preview layout, and open action work. | Service unit + snapshot + UI test |
| NOTE-06 | P0 | Poll | Single/multiple selection, visibility of results, submit-once, optimistic state rollback, totals/percent, already-voted/closed state, and stream update work. | Unit + fake API/WebSocket E2E |
| DETAIL-01 | P1 | Thread | Ancestor chain, selected note, child replies, pagination/refresh, nested navigation, back restoration, and every footer/overflow action work. | UI E2E + screenshots |
| SEARCH-01 | P1 | Search | Blank state trends, hashtag tap, note/user toggle, submit/cancel, Japanese/Latin query, empty/error/retry, correct result tap, and pagination work. | Unit + UI E2E + snapshots |
| USER-01 | P1 | User lists | Search, followers, following, and list-member modes load/page and open profiles; profile counts route to corresponding lists. | API contract + UI E2E |
| PROFILE-01 | P0 | Profile | Banner/avatar/cat/name/handle/bio/counts/tabs match; Notes, Notes & Replies, Media query flags are correct; links/avatar work. | Contract + snapshot/UI tests |
| PROFILE-02 | P0 | Follow | Relationship loads; follow/unfollow confirms only server success, rolls back/display errors on failure, and is account scoped. | Unit + mock-server E2E |
| PROFILE-03 | P0 | Edit | Editing one field never clears untouched fields; avatar/banner choose/edit/reset/upload, name/bio/cat, cancel, progress, retry, server validation, and confirmed update work. | Request-body unit tests + UI E2E |
| POST-01 | P0 | Compose | Normal/reply/quote create correct payload; close/cancel; 1500-count boundary; whitespace/empty validation; saved visibility; account switch; one-submit guarantee; progress/success/failure/retry work. | Unit + mock-server E2E |
| POST-02 | P0 | Compose media | Camera/library permissions, photo edit/delete/order, 1–4-image policy, one-video exclusivity, resize/encoding/upload order, per-file failure/retry, and NSFW payload work. | Unit + simulator UI E2E |
| POST-03 | P1 | Compose extras | CW, emoji insertion, now-playing text/artwork and unavailable state match legacy. | Unit + UI/snapshot tests |
| POST-04 | P2 | Poll/location compose | Either explicitly implement current Misskey poll/location product requirements with tests, or remove the unreachable legacy controls/models. They must not appear half-functional. | Product decision + code review |
| NOTIF-01 | P0 | Notifications | REST paging and stream show follow/reaction/renote/reply/mention/quote variants; dedupe/order/account switch; tap routing; refresh/error/retry work. | Contract + stream + UI E2E |
| NOTIF-02 | P0 | Push | Permission states, APNs/FCM token refresh, per-account WebPush registration/removal, foreground banner, background tap/deep link, badge clear, malformed payload, and multiple accounts work. | Unit + integration/manual device checklist |
| MSG-01 | P1 | History | Correct account, ordering, name/avatar/preview/time, empty/error/retry and tap-to-conversation work. | Unit + snapshot/UI test |
| MSG-02 | P1 | Conversation | Correct sender identity is tied to conversation owner; initial/older paging, text send success/error/retry, bubble/date/read visuals, keyboard, and link routing work. | Unit + UI E2E + snapshots |
| SET-01 | P1 | Settings | Settings root routes Design, Reactions, Licenses, About with legacy rows/navigation and safe dismissal persistence. | UI test + snapshots |
| SET-02 | P1 | Reactions | Instance isolation, defaults, add/search/delete/reorder, history max 14, persistence upgrade, and animated/default/custom emoji match. | Unit + UI E2E |
| SET-03 | P1 | About/licenses | About visual/link/version parity; license list exactly matches final shipping dependencies and opens readable bodies. | Snapshot + generated inventory review |
| SHARE-01 | P0 | Extension | Text-only, URL-only, image-only, text+URL, text+1–4 images all post the complete advertised payload; unsupported/mixed inputs fail explicitly rather than truncate. | Extension unit + host E2E |
| SHARE-02 | P0 | Extension state | Current account and persisted visibility are both displayed and actually used; selection changes are retained; zero/missing-token account never crashes. | Unit + extension UI test |
| SHARE-03 | P0 | Extension lifecycle | Host request completes only after upload/post succeeds; progress/cancel/retry/error are visible; completion is exactly once and survives cancellation/background constraints. | Async lifecycle integration test |
| STORE-01 | P0 | Upgrade | App-group users/current account/visibility/latest notification, theme tabs/color/mode, reaction favorites/history, and keychain tokens migrate idempotently from legacy data. | Fixture-driven migration tests |
| STORE-02 | P0 | Isolation/security | Account data never crosses accounts; secrets never enter logs/defaults/snapshots; app/extension keychain groups match signed entitlements; logout removes intended token/cache only. | Security tests + entitlement inspection |
| PUSH-01 | P0 | Relay | If custom relay remains, WebPush decrypt/validation/localization/FCM send is deployed from secret-manager values, authenticates/limits input, has health/observability, and passes current payload tests. | Relay unit/integration/deployment evidence |
| REL-01 | P0 | Test suite | New unit, integration, UI/E2E, and snapshot targets run in CI from a clean checkout with deterministic fixtures and no live credentials. | Green CI artifact |
| REL-02 | P0 | Regression | Reviewer signs off requirements traceability, functional gaps, baseline/current/diff images, build/test logs, dependency licenses, and zero unresolved P0/P1 defects. | Review report |

## Explicit non-acceptance conditions

The following independently block release: retaining a Storyboard/XIB screen in ordinary flow; truncating share input; silently ignoring an API failure; using global current-user state for an account-bound request/conversation; missing a screenshot counterpart; accepting only manual visual inspection without diff artifacts; storing tokens outside keychain; depending on checked-in credentials; or skipping tests because the legacy endpoint/runtime is unavailable.
