# Migration unit, integration, UI/E2E, and visual test matrix

## Deterministic test environment

Create a fixture-backed `MisskeyService` and WebSocket server before UI implementation. It must return stable IDs, avatars, banners, emoji files (PNG/SVG/GIF/APNG), note timestamps, Japanese/Latin text, and explicit latency/errors. Never point CI or screenshot tests at a live Misskey instance.

Global conditions for visual tests:

- Locale `ja_JP`, timezone `Asia/Tokyo`, fixed clock, deterministic relative times, fixed status-bar state, light appearance unless the case says dark, default text size, animations disabled after the target screen settles.
- Use bundled fixture images in both baseline/reference rendering and replacement rendering. Network-fetched avatars from the 2020 captures are reference evidence, not suitable live dependencies.
- Record accessibility identifiers for every navigation item, tab, note action, configuration row, attachment, form field, banner, and error/retry control.
- Run release E2E on the newest supported stable iOS/Xcode. The audited machine currently exposes only iOS 18.6 (iPhone 16 Pro and iPhone 16 Pro Max/Plus), so those runs are a local minimum and are not by themselves evidence that the “latest iOS” release gate is satisfied. Also run the compact-width set on the smallest supported current iPhone simulator.

## Unit and component matrix

| ID | Component | Required cases |
| --- | --- | --- |
| U-ACCOUNT | Account repository | Empty/default current; JSON decode; missing keychain token filtered without deleting valid accounts; add/duplicate; switch; delete current/noncurrent/last; account-scoped service creation |
| U-MIGRATE | Legacy persistence migration | Standard defaults → app group; old login keys → `SecureUser`; old keychain → shared group; `theme-key`; archived reaction favorites/history; interrupted and repeated migration; corrupt/unknown-version fixture |
| U-THEME | Theme/tabs | Default `@username`/Local/Global; account fill-in; deleted owner removal; zero tabs fallback; add/delete/reorder/rename; model equality; light/dark palette and arbitrary valid/invalid hex |
| U-AUTH | Auth state machine | Sign-up/login, Terms accept/decline, instance sanitization, app-create/session/callback/token exchange, cancellation/retry, duplicate user, malformed callback, no token persistence on failure |
| U-TL-REST | Timeline repository | Each timeline endpoint/flags; empty/error; until pagination; dedupe; promotion/renote/reply/quote conversion; special-host semantics are not silently substituted |
| U-TL-STREAM | Stream reducer | Connect/channel, note insert, reacted/unreacted/deleted/poll-voted, self vs other reaction, nested/renoted note IDs, reconnect catch-up, duplicate event, malformed event, cancellation/account switch |
| U-MFM | MFM parser | HTTP/HTTPS, markdown link, URL containing `@/#`, user `@u@host`, Japanese hashtag, bold, strike, inline/block code, newline, reply mark, legacy-disabled tags, malformed/nested markup, HTML escaping, tap target |
| U-EMOJI | Emoji resolver | Unicode/default/custom/non-colon legacy names, remote `:name@host:`, aliases/categories/Others, unresolved literal, Twemoji codepoint/variation selector, instance handler isolation |
| U-IMAGE | Animated image/cache | PNG/SVG/GIF/APNG decode, correct frame order/duration, cancellation/reuse, retry/error image, memory pressure, disk filename, max-size/eviction, no stale-image race |
| U-NOTE | Note view state | All note types; CW closed/open; own/reaction-disabled; selected reaction/count; URL selection; attachment types; stable identity; optimistic mutation success/rollback |
| U-FILES | Attachment layout | 0/1/2/3/4 files geometry; >4 policy; image/video classification; missing thumbnail; sensitive default; tapped gallery index; video URL validation |
| U-POLL | Poll state | Single/multiple choice; no choice; already voted; closed/expired; show/hide results; percent at zero and rounding; exactly-once calls; rollback; stream update |
| U-PREVIEW | URL preview | Instance proxy success; invalid JSON/status; fallback success/failure; GitHub image choice; timeout/cancel; cache hit/expiry; sensitive metadata |
| U-POST | Compose reducer/payload | Placeholder/empty/whitespace; 1499/1500/1501 grapheme boundaries; public/home/followers; reply/quote IDs; CW; emoji; saved visibility; account switch; submit lock/cancel/retry |
| U-UPLOAD | Upload pipeline | Image resize ≤1024 preserving aspect; JPEG metadata/quality contract; 1–4 order; video exclusive; NSFW; partial failure/cancel/retry; note not created before every file ID exists |
| U-NOWPLAY | Now playing | Artist+title, title only, no item, artwork/no artwork, text insertion without overwriting user text |
| U-PROFILE | Profile/edit | Own/other relationship; three tab query flags; follow/unfollow success/error rollback; sparse patch does not clear unchanged field; avatar/banner upload/reset/error; cat/name/bio |
| U-USERS | User lists | Search/following/followers/list members, empty/error/paging, Japanese query, MFM bio fallback, stable dedupe |
| U-NOTIF | Notification reducer | Every type, missing user/note, REST order/paging, dedupe with stream, latest ID, account switch, deep-link target, unread/read behavior |
| U-PUSH | Push coordinator | Permission denied/provisional/allowed; APNs/FCM token rotation; register each owner (not global user); malformed/wrong-owner payload; foreground banner; tap route; badge clear/unregister |
| U-MSG | Messaging | History ordering; peer derivation; current sender from conversation owner; initial/until paging; mark read; text send success/error/retry; duplicate message; link routing |
| U-REACTION | Favorites/history | Default preset; instance key isolation; add duplicate; delete/reorder; raw/default/custom round trip; history recency and cap 14; safe decode of legacy archive/corruption |
| U-SHARE | Share ingestion/lifecycle | No attachment text-only; URL; file URL image; direct image; 1–4 images; content ordering; unsupported provider; load error; saved visibility assignment; zero/missing-token account; exactly-once complete only after success |
| U-RELAY | Push relay | Valid/invalid WebPush envelope, authentication/tag/length validation, decrypt failure, supported notification types/languages, FCM failure/retry, logs redact tokens/keys |

## UI and E2E journey matrix

Each test uses the fixture server and asserts both the visible result and the recorded request/event. A tap alone is not proof of behavior.

| ID | Journey | Assertions |
| --- | --- | --- |
| E2E-01 | First launch → instance → Terms → sign up/login → callback | Visual start parity; explicit consent; cancel/retry; saved account; Home loads with correct token; no secret in logs |
| E2E-02 | Upgrade legacy fixture → launch | No re-login; current account, tab order/names, color/theme, visibility and emoji favorites/history preserved |
| E2E-03 | Home tabs + pager + footer | Correct REST/stream channel per tab/account; swipe/tap selection; footer routes; double-tap scroll; state survives background/relaunch |
| E2E-04 | Timeline pagination/refresh/reconnect | Loading/empty/error/retry; refresh replaces/dedupes; near-end pages once; disconnect/reconnect catches up without scroll jump |
| E2E-05 | Note variants and navigation | Normal/reply/renote/promotion/quote/CW/URL/media/poll rows; detail, author, nested thread, back position |
| E2E-06 | Note mutations | Reply create; immediate renote; quote; add/remove reaction; poll; own delete; other block/report; success and forced error rollback; calls exactly once |
| E2E-07 | Search | Blank trends → hashtag; note/user toggle; keyboard submit/cancel; empty/error/retry; pagination; result detail/profile |
| E2E-08 | Profile/social graph | Own and other profile; Notes/Replies/Media; follow/unfollow error; following/follower counts open functional paged lists; avatar/bio link |
| E2E-09 | Profile edit | Change one field only; camera/library permission paths; avatar/banner edit/reset; cat; upload error/retry; wait for confirmed update; unchanged server fields intact |
| E2E-10 | Compose text/reply/quote | 1500 boundary, validation, visibility persistence, account switch, CW, emoji, now playing; success and failure/retry; dismissal timing |
| E2E-11 | Compose attachments | 1–4 photos edit/order/remove/NSFW; one video; reject invalid mix/count; partial upload failure; final file-ID order/payload |
| E2E-12 | Notifications and push | Six notification variants; paging/stream dedupe; tap; account switch; foreground rich banner; background notification deep link; malformed/wrong-account payload |
| E2E-13 | Messages | History → conversation; correct bubble sides after account switch; older paging; send success/failure/retry; read/date labels; URL/mention/hashtag routes; keyboard |
| E2E-14 | Accounts/settings | Add/switch/delete/noncurrent/current/last; tab cleanup; design reorder/rename/account/color/light/dark; relaunch state |
| E2E-15 | Reaction preferences | Choose instance; add via picker/search; duplicate; edit/delete/reorder; leave/relaunch; timeline picker reflects saved order/history |
| E2E-16 | About/licenses | Exact visual; version derives from bundle; both external links; every shipping dependency appears with correct license body |
| E2E-17 | Share text/URL/1–4 images | Host app invokes extension; selected saved account/visibility used; full ordered input sent; progress; success closes once; failure remains for retry; cancellation sends nothing |
| E2E-18 | Offline/slow/cancel stress | Auth, every list, preview, upload, post, follow, reaction, poll, DM under offline/timeout/500; useful retry; no crash/stuck loader/duplicate mutation |
| E2E-19 | Rapid multi-account stress | Switch while stream/load/upload/message is active; old tasks cancel; no token/content/bubble/push registration crosses accounts |
| E2E-20 | Accessibility | VoiceOver traversal/actions, Reduce Motion, keyboard navigation where applicable, large text without hidden controls; default-size screenshots unchanged |

## Screenshot baseline and comparison protocol

### Historic baseline mapping

| Visual ID | Legacy source | Required replacement state |
| --- | --- | --- |
| G-11PM-HOME | `images/ScreenShot/iPhoneX/Simulator Screen Shot - iPhone 11 Pro Max - 2020-03-28 at 19.32.36.png` | Home timeline/top tabs/footer with mixed notes and image |
| G-11PM-DETAIL | `... at 19.32.58.png` | Post-detail ancestor/selected/child layout |
| G-11PM-PROFILE | `... at 19.33.13.png` | Profile header/counts/tabs/timeline |
| G-11PM-REACTION | `... at 19.33.57.png` | Half/full reaction picker categories/favorites |
| G-11PM-REACTION-SEARCH | `... at 19.34.44.png` | Picker search with keyboard/results |
| G-11PM-START | `... at 19.35.01.png` | Start screen |
| G-8P-START | `images/ScreenShot/iPhone Pro/Simulator Screen Shot - iPhone 8 Plus - 2020-03-29 at 00.27.35.png` | Start screen, non-notch safe area |
| G-8P-HOME | `... at 00.28.09.png` | Home timeline/top tabs/footer |
| G-8P-DETAIL | `... at 00.28.14.png` | Post detail |
| G-8P-NOTIFICATIONS | `... at 00.28.28.png` | Notifications mixed cell types |
| G-8P-PROFILE | `... at 00.28.44.png` | Profile header/tabs/timeline |

Do not rename or overwrite historic files. Store replacement output and diffs under a separate test-artifact directory keyed by commit, simulator, OS, locale, theme, and case.

### Required additional deterministic goldens

Historic captures do not cover all required design states. Add fixtures/snapshots for:

- Timeline: every row variant, skeleton, empty/error, dark theme, long text, CW closed/open, URL preview, 1/2/3/4 sensitive/non-sensitive media, video, poll states, every reaction chip form.
- Search trends/note/user; account list/dropdown; compose normal/reply/quote/CW/media/visibility/account menu; notification variants/banner; message history/conversation; profile other/follow/edit and profile editor.
- Settings root/design/instance/reaction editor/license/detail/about; placeholder/nano banners; share composer/account/visibility/progress/error.
- Current safe-area devices in light/dark and the smallest supported current iPhone width.

### Capture and diff algorithm

1. Seed identical fixtures, clock, account, theme, scroll offset, and content-size category.
2. Wait for an explicit `visualReady` accessibility signal: fonts/images/emoji loaded, animations paused on a deterministic frame, no skeleton unless it is the target state.
3. Capture lossless PNG using `simctl io <udid> screenshot` or XCTest attachments. Preserve original scale and color space.
4. Compare only like-sized captures. For historic devices that cannot run the current runtime, first create a reference canvas at the historic 1242×2688 or 1242×2208 dimensions and document any safe-area transform; do not stretch either image.
5. Align by app window bounds only. Mask only non-app-owned nondeterminism (system clock/carrier/signal/battery and an explicitly recorded dynamic keyboard suggestion row). Never mask app text, media, tabs, separators, banners, or controls.
6. Emit three artifacts: baseline, current, and amplified absolute-difference/overlay image, plus JSON metrics.
7. Gate app-owned pixels on all of:
   - exact dimensions;
   - mean absolute RGBA error ≤ 0.5/255;
   - changed pixels above 8/255 per channel ≤ 0.10%;
   - SSIM ≥ 0.995;
   - no connected changed region larger than 16×16 pixels unless reviewer marks and explains an approved OS-rendering exception.
8. A numerical pass is necessary but not sufficient. Reviewer inspects overlay at 100% for hierarchy, truncation, wrong font weight, safe-area/footer drift, animation frame, and tap-state mismatch, then signs the case.

The “completely identical design” target is zero app-owned pixel difference. The tolerances above exist only for unavoidable rasterization differences between OS/font renderers; every exception must be case-specific and recorded, never a blanket baseline update.

## Behavior comparison protocol

For each E2E test, retain a machine-readable event trace containing route transitions, request method/endpoint plus redacted body, stream inputs, persistence mutations, and final visible state. Compare it against the expected legacy/intended sequence. Assertions must include:

- exactly-once destructive/write requests;
- account/user ID bound at operation creation, not looked up globally later;
- cancellation of obsolete requests after navigation/account switch;
- visible pending/success/error states and rollback where applicable;
- preservation of scroll, tab, draft, and navigation state called out in the acceptance matrix;
- no API token, FCM/APNs token, WebPush secret, private key, or private fixture content in logs/artifacts.

## CI and reviewer handoff

The CI job should archive clean build logs, test `.xcresult`, coverage, baseline/current/diff screenshots, diff metrics, and the requirements trace report. Fail CI for a missing capture, baseline auto-update, focused/skipped test, unexpected network call, leaked secret pattern, or unresolved P0/P1 acceptance row. Baseline changes require a separate review explaining why the design contract changed; migration implementation commits must not silently regenerate goldens.
