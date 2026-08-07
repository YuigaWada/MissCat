# MissCat legacy functional and visual inventory

## Purpose and evidence boundary

This is the migration baseline for replacing the UIKit application and share extension with SwiftUI. It distinguishes implemented behavior from dead, partial, or broken legacy paths so that “all functions work” does not accidentally mean reproducing a known defect.

The inventory is based on the checked-in source, `MissCat/View/Base.lproj/Main.storyboard`, `MissCatShare/Base.lproj/MainInterface.storyboard`, all XIBs under `MissCat/View`, `Podfile.lock`, target plists/entitlements, the Node push relay under `ApiServer`, and the eleven historic simulator captures under `images/ScreenShot`. No backend, account, or live Misskey instance was invoked during this audit. Secret/key file contents were deliberately not read or reproduced.

The historic screenshots are:

| Device / resolution | Legacy states represented |
| --- | --- |
| iPhone 11 Pro Max, 1242×2688 | Home timeline, post detail, profile, reaction picker, reaction search, start/login |
| iPhone 8 Plus, 1242×2208 | Start/login, Home timeline, post detail, notifications, profile |

The captures establish the strongest available visual contract: white/light appearance, blue `#2F7CF6` accent, compact information-dense rows, top search/timeline tab strip, a five-position footer with an oversized circular compose button, and the cyan gradient MissCat start screen. See `images/ScreenShot/iPhoneX` and `images/ScreenShot/iPhone Pro`.

## Runtime architecture

- The app is UIKit, Storyboard/XIB, RxSwift/RxCocoa/RxDataSources, and CocoaPods. `AppDelegate` is the `@UIApplicationMain` entry point (`MissCat/Others/App/AppDelegate.swift`).
- The initial route is `CustomNavigationController` → `HomeViewController`. Home is a `PolioPagerViewController`; most screens are instantiated by Storyboard identifier and pushed, presented full-screen, or embedded as children.
- The UI and models call `MisskeyKit` directly. REST and streaming concerns are mixed into view models/models, and global current-user/theme/emoji state is used by many screens.
- The share extension is a separate `SLComposeServiceViewController` target with duplicate account persistence types.
- Push is a three-hop design: Misskey WebPush subscription → custom Node relay (`ApiServer`) → Firebase Cloud Messaging → app notification handling.
- The project declares iOS 12.0 for the app/share targets and iOS 13.2 for tests, Swift 5.0, and portrait-only iPhone UI. Xcode 16.4/iOS 18.6 sees the scheme, but a clean checkout has no `Pods` directory, so the legacy target is not presently a reproducible build without restoring/upgrading dependencies.

Legacy target declarations that affect the rewrite are app-group/keychain/push entitlements; remote-notification, processing, and fetch background modes; camera, microphone, photo-library, and Apple Music usage strings; the `twitter` queried URL scheme; Font Awesome bundled fonts; and a scene manifest with multiple scenes disabled. `UIUserInterfaceStyle` is forced to Light even though MissCat has its own custom dark palette, so system chrome and app-owned theme behavior must be verified separately. The obsolete `armv7` required capability must not be carried forward.

## Navigation map

```text
Launch
└─ Home container
   ├─ no saved account → Start
   │  ├─ change instance
   │  ├─ sign up → Terms → auth web flow
   │  └─ log in  → Terms → auth web flow
   ├─ top pager
   │  ├─ Search → Trends | note results | user results
   │  └─ configured Home / Local / Social / Global timelines
   ├─ footer Home
   ├─ footer Notifications
   ├─ footer Compose → normal | reply | quote
   ├─ footer Messages → conversation
   └─ footer Account/Profile
      ├─ account switcher / account list / add account / delete account
      ├─ Profile → Notes | Notes & Replies | Media
      └─ Settings
         ├─ Design
         ├─ Reactions → instance → favorite reaction editor
         ├─ Licenses → license body
         └─ About MissCat

Any note → detail / author profile / reply / renote / quote / reaction picker /
           overflow actions / link / image gallery / video player / poll vote
```

## Screen and interaction inventory

Status meanings: **implemented** is an observable legacy path; **partial** exists but contains a known missing branch; **dead** is not reachable from the shipped navigation.

Migration ownership and acceptance are tracked separately in `docs/ui-migration-surfaces.tsv`. Run `scripts/report-ui-migration.sh` for the current UIKit/SwiftUI ratio. A surface only becomes accepted after it is reachable on the ordinary route, preserves its required behavior, passes relevant tests, and reaches at least 90% screenshot similarity.

| Area | Screen/state | User-visible contract and actions | Status / primary evidence |
| --- | --- | --- | --- |
| Shell | Home/pager | Search is first top item, followed by user-configured timeline tabs. Horizontal paging and selected blue underline. Light/dark theme and custom main color propagate. | Implemented. `MissCat/View/Main/HomeViewController.swift:70-165`; `MissCat/Others/Utilities/Theme.swift:13-331` |
| Shell | Footer | Home, notifications, large center compose, messages/star, account/profile. Selection tint follows main color; double-tapping Home or Notifications scrolls to top. | Implemented. `MissCat/View/Reusable/Tab/TabBar.swift`; `MissCat/View/Main/HomeViewController.swift:336-431` |
| Shell | Account navbar/dropdown | Avatar opens account dropdown; selecting changes global current account and reloads account-scoped pages. Settings cog opens Settings. | Implemented. `MissCat/View/Reusable/Tab/NavBar.swift`; `AccountsDropdownMenu.swift` |
| Login | Start | Cyan/teal gradient, centered MissCat logo/tagline, white Sign up and Login buttons, instance-change link, selected instance at bottom. | Implemented and captured. `MissCat/View/Login/StartViewController.swift`; Storyboard scene `start` |
| Login | Terms | Terms content and “同意する”; both sign-up and login pass through it. | Implemented, but consent is recorded via controller disappearance after button action rather than durable acceptance. `TosViewController.swift` |
| Login | Instance selector | Alert input defaults to `misskey.io`; strips scheme and spaces. | Implemented. `StartViewController.swift:215-246` |
| Login | Auth web | Creates app (or legacy fixed app for misskey.io), opens sign-up/login web content, exchanges session token after the `https://misscat.dev` callback, saves account, primes emoji/push, resets/relaunches shell. Web storage is cleared for each auth. | Implemented legacy Misskey auth. `StartViewController.swift:102-214`; `AuthWebViewController.swift` |
| Timeline | Home / Local / Social / Global | Initial skeletons; REST page load; streaming insertion/update/deletion; near-end pagination; row selection to detail. | Implemented. `TimelineModel.swift:15-151,289-447`; `TimelineViewController.swift` |
| Timeline | Configured tabs | Default tabs are `@username`, Local, Global. Design settings can add/reorder/delete/rename Home/Local/Social/Global tabs and bind each to an account. | Implemented. `Theme.swift:35-109,266-331`; `DesignSettingsViewController.swift` |
| Timeline | User/list/search modes | `OneUser`, `UserList`, and `NoteSearch` REST modes exist. Profile uses `OneUser`; search uses `NoteSearch`. | Partial: Home’s `.user`/`.list` tab branches return empty controllers; NoteSearch is incorrectly considered stream-capable although it has no channel. `HomeViewController.swift:122-160`; `TimelineType` in `TimelineModel.swift` |
| Timeline | Pull to refresh | A refresh control is shown for non-stream timelines. | Broken: refresh body is commented out. `TimelineViewController.swift:210-235` |
| Note | Normal/reply/renote/promotion/quote | Compact avatar/name/handle/age header, reply marker, note text, optional renote/promotion header, nested quote, action footer. Skeleton form exists. | Implemented. `NoteCell.xib`; `NoteCell.swift`; `TimelineModel.swift:417-476` |
| Note | MFM/text | Clickable HTTP(S)/markdown links, mentions, hashtags; bold, strike, inline/block code; custom/default emoji and remote-instance emoji; unsupported motion/flip/spin/jump/small/`***`/`(((` wrappers are stripped. | Implemented subset, not full current MFM. `MissCat/MFMEngine/MFMEngine.swift:22-377` |
| Note | Content warning | CW text displays with “タップで詳細表示”, then reveals the note on tap. | Implemented. `MFMEngine.swift:194-207`; `NoteCell.swift` |
| Note | Attachments | 1/2/3/4-item mosaic; image opens swipeable Agrume gallery at tapped index; video opens AV player. Sensitive media is blurred with “閲覧注意 タップで表示” overlay. | Implemented. `FileContainer.swift`; `FileContainerCell.swift`; `UIViewController+ImageViewer.swift` |
| Note | URL preview | Uses instance `/url?url=…`, falls back to SwiftLinkPreview; displays image/title/description; memory-caches result; tap opens the URL. | Implemented. `UrlPreviewerModel.swift`; `UrlPreviewer.swift` |
| Note | Poll | Single/multiple choice, vote button, totals/percent/progress, optimistic selected/count update, disabled after completed vote. | Implemented. `PollView.swift`; `NoteCellViewModel.swift:298-309`; `HomeModel.swift` |
| Note | Reactions | Shows emoji/count chips with selected styling; tap an existing reaction to add/remove; plus opens picker; own posts cannot be reacted to. | Implemented. `ReactionCell.swift`; `NoteCell.swift:680-726`; `ReactionGenModel.swift` |
| Note | Reply / renote / quote | Reply opens compose with target; renote menu offers immediate renote or quote compose. | Implemented. `TimelineViewController.swift:374-456`; `HomeViewController.swift` |
| Note | Overflow | Other user: detail, copy text, copy URL, browser, system share, block confirmation, abuse report with required message. Own note: delete confirmation. | Implemented only in timeline. `TimelineViewController.swift:457-578`; `TimelineViewModel.swift:342-418` |
| Detail | Post thread | Recursively loads ancestor replies, shows selected note, loads child replies, and permits nested detail navigation. Detail typography is larger than timeline. | Implemented. `PostDetailViewController.swift`; `PostDetailViewModel.swift`; `PostDetailModel.swift` |
| Detail | Detail actions | Same note footer is rendered. | Partial: base `NoteDisplay` forwards overflow to `HomeViewController`, whose default handler is empty, so detail overflow is nonfunctional. Child pagination is also commented out. |
| Search | Trends | Empty search state shows “{instance}でのトレンド”; tapping hashtag starts note search. | Implemented. `TrendViewController.swift`; `SearchViewController.swift` |
| Search | Note/user search | Search entry/cancel, animated Notes/Users selection. Note results reuse timeline; user results use user rows. | Implemented. `SearchViewController.swift`; `TimelineModel.swift:144-149`; `UserListModel.swift:65-78` |
| Users | User result/list | Avatar, MFM name/handle, bio, skeletons; tap opens profile. | Search implemented. Follow/follower/list enum cases exist but model implements only search, and pagination trigger is commented. `UserListViewController.swift`; `UserListModel.swift` |
| Profile | Profile | Gradient/blur banner, circular avatar and cat mark, MFM display name/handle/bio, post/following/follower counts, follow/edit button, settings/back, Notes / Notes & Replies / Media child timelines. Avatar opens gallery; bio links work. | Implemented and captured. `ProfileViewController.swift`; `ProfileViewModel.swift` |
| Profile | Relationship/list navigation | Other users can be followed/unfollowed; own profile opens Edit. | Partial: following/follower count controls have no route; follow API errors are reported as success. `ProfileModel.swift`; `ProfileViewController.swift` |
| Profile | Edit profile | Edit banner/avatar via camera/library/photo editor or reset; name, bio, cat toggle, emoji entry; save uploads changed images and updates profile, optimistically reflecting changes. | Implemented but unsafe: unchanged optional values are sent as empty strings and the screen pops before network result. `ProfileSettingsViewController.swift`; `ProfileSettingsModel.swift:20-45` |
| Compose | Normal/reply/quote | Close, account avatar/switch, reply/quote target preview, 1500-character editor and counter, visibility, post button. Visibility choices: public, home, followers; choice is persisted. | Implemented. `PostViewController.swift`; `PostViewModel.swift`; `PostModel.swift` |
| Compose | Media | Camera/photo library, photo editor, remove/edit attachment, global NSFW toggle; one video and no image/video mixing; uploads resized JPEG or MP4 before note creation. | Implemented. No explicit four-image limit in app compose. `PostViewController.swift:325-445,627+`; `PostViewModel.swift:313-391` |
| Compose | CW / now playing / emoji | CW editor; Apple Music “artist - title #nowplaying” plus artwork; emoji picker inserts Unicode or `:custom:`. | Implemented. `PostViewController.swift`; `PostViewModel.swift:224-284` |
| Compose | Poll/location | Poll editor classes and toolbar item exist; location state exists. | Dead/incomplete: poll toolbar binding/item and location UI are commented/hidden. They are not legacy acceptance features unless product scope explicitly restores them. |
| Notifications | Notification list | REST initial/pagination plus main-stream updates; follow/reaction/renote compact cells and reply/mention/quote note cells; account switch; note-type tap opens detail; footer navigation. | Implemented. `NotificationsViewController.swift`; `NotificationModel.swift`; `NotificationsViewModel.swift` |
| Notifications | In-app push banner | Foreground remote notification resolves notification ID against Misskey notifications and shows a rich banner; badge clears in foreground. Tiny status/error banners also exist. | Implemented. `AppDelegate.swift:77-146`; `NotificationBanner.xib`; `NanoNotificationBanner.xib` |
| Messages | History | Account-scoped direct-message history with avatar, MFM name, preview, and relative time; tap opens conversation. | Implemented. `MessageListViewController.swift`; `MessageListModel.swift` |
| Messages | Conversation | MessageKit bubbles, sender/recipient colors, avatars/names, periodic date labels, “Read”, text composer, pull-to-load older, link/mention/hashtag routing. | Implemented text-only. Image input branch and group conversation are absent; no stream/live refresh. `ChatViewController.swift`; `DirectMessageViewController.swift`; `DirectMessageModel.swift` |
| Accounts | Account list | 120-point account cards, add-account row, edit/delete mode, selecting account opens its profile; deleting last account returns to Start and removes its tabs. | Implemented. `AccountsListViewController.swift`; `AccountsListViewModel.swift`; `AccountCell.xib` |
| Settings | Settings root | Design, Reaction, LICENSE, About MissCat. About is wired by Storyboard segue. | Implemented. `SettingsViewController.swift`; Storyboard `settings` |
| Settings | Design | Reorder/add/delete/rename tabs; assign account; light/dark mode; custom main color. Saves on exit and chooses partial/full relaunch. | Implemented. `DesignSettingsViewController.swift`; `Theme.swift` |
| Settings | Reactions | Select instance, view favorites, add via picker, delete in edit mode, long-press reorder; saves on exit. Picker shows favorites/history/custom/default groups and search. | Implemented. `InstanceViewController.swift`; `ReactionSettingsViewController.swift`; `ReactionGenViewController.swift` |
| Settings | Licenses | Dependency list and embedded license text/detail. | Implemented, but inventory omits some linked pods such as Firebase and SVGKit. `LicenseViewController.swift` |
| Settings | About | Legacy gradient/logo animation, version, developer Twitter and Misskey links. | Implemented. `AboutMisskeyViewController.swift` |
| Settings | Legacy account/theme controllers | Account logout screen is in Storyboard; `ThemeViewController` source is fully commented. | Account screen appears unreachable; theme controller is dead. |
| Empty/error | Placeholder and banners | Sad cat image, “No Data / 表示するデータがありません”; nano loading/success/error banner styles. | Storyboard/XIB implemented reusable states. |
| Share extension | Compose sheet | Native share composer, max 1500, app-colored navigation, account selector, visibility selector (public/home/followers), text/URL/image posting. | Partial/broken; see dedicated section below. `MissCatShare/ShareViewController.swift` |

## API and service dependency inventory

All calls below must be represented by protocols and deterministic test doubles before UI migration. API spelling reflects the legacy `MisskeyKit` interface; a modern implementation may map to current Misskey endpoints.

| Capability | Legacy API/service |
| --- | --- |
| Auth | `app.create`, auth session/token exchange, callback `https://misscat.dev` |
| Current/profile user | `users.i`, `users.showUser`, `users.getUserRelationship`, `users.updateMyAccount` |
| Social graph | `users.follow`, `users.unfollow`, `users.block`, `users.reportAsAbuse` |
| Timelines | `notes.getTimeline`, `getLocalTimeline`, `getHybridTimeline`, `getGlobalTimeline`, `getUserNotes`, `getUserListTimeline` |
| Note/detail/search | `notes.showNote`, `notes.getChildren`, `search.notes`, `search.user`, `search.trendHashtags` |
| Mutations | `notes.createNote`, `renote`, `deletePost`, `createReaction`, `deleteReaction`, `vote` |
| Files | `drive.createFile` for JPEG and MP4 |
| Notifications | `notifications.get`; main notification streaming channel |
| Timeline streaming | home/local/hybrid/global channels; `note`, `reacted`, `unreacted`, `deleted` events |
| Emoji | `emojis.getDefault`, `emojis.getCustom`, `notes.getEmojis`; Twemoji SVG CDN |
| Messaging | `messaging.getHistory`, `getMessageWithUser(markAsRead:)`, `messaging.create` |
| Link preview | instance `https://{host}/url?url=…`, then SwiftLinkPreview fallback |
| Push | Firebase token; Misskey `sw/register`; custom `/api/v1/push/{lang}/{userId}/{deviceToken}` relay |
| Media/system | Photos, camera, microphone, AV playback, Apple Music now-playing, Safari, system share sheet |

## Persistence, app groups, and cache contract

| Store | Keys/data and behavior | Evidence / migration concern |
| --- | --- | --- |
| App-group defaults | Suite `group.yuwd.MissCat`: `saved-user` JSON without API keys, `current-user-id`, `current-visibility`, `latest-notification` | `MissCat/Others/Utilities/Cache.swift:153-370`; must preserve compatible decoding during upgrade |
| Keychain | Service `yuwd.MissCat`, user ID → API token | Same file. App and extension entitlements currently declare different keychain groups while code requests `group.yuwd.MissCat`; verify/fix signing access-group alignment before declaring share parity |
| Legacy migration | Copies standard defaults to app group once (`DidMigrateToAppGroups`); migrates older login keys and old non-group keychain | Must retain an idempotent migration test using a pre-upgrade fixture |
| Theme | Standard defaults key `theme-key`, Codable model: ordered tabs, `mainColorHex`, light/dark | `Theme.swift:266-331`; preserve unknown/old tab handling and fallback-to-default behavior |
| Reaction favorites/history | Standard defaults keys `{favs\|history}-{instance}`, archived emoji objects; history capped to 14 | `ReactionGenModel.swift`; `EmojiView.swift:124-159`; deprecated unarchiving needs a safe one-time decoder/migration |
| Image/user/preview cache | In-memory `NSCache`; remote custom emoji data may be persisted under Application Support using URL hash | `Cache.swift`; `MFMImageView.swift`; persistence existence check mixes URL string/path and needs correction |
| Badge/notification | Badge cleared on foreground; latest notification ID stored | `AppDelegate.swift`; `NotificationModel.swift` |

API tokens, Firebase credentials, WebPush private material, and test device tokens must never enter defaults, fixtures, screenshots, documentation, or commits. The repository currently contains credential-shaped files under `ApiServer/key` and `ApiServer/test`; their contents were not inspected. Rotate/remove from history and replace with environment/secret-manager inputs as a separate security gate.

## Share extension: intended contract and legacy failures

The extension advertises text, one web URL, and up to four images (`MissCatShare/Info.plist`), but implementation consumes only the first input item and first attachment. It checks URL then image conformity, posts at most one item, and does not post text-only content because `didSelectPost` returns when there is no attachment (`ShareViewController.swift:78-94`). Additional gaps:

- Saved visibility is displayed but never assigned to `currentVisibility`; unless the user reselects it, the actual post is public (`ShareViewController.swift:23-24,64-69`).
- The extension completes the request immediately after starting asynchronous upload/post, allowing iOS to terminate work and making the later error alert unreliable (`ShareViewController.swift:87-92,131-134`).
- Multiple images, video, per-file sensitive state, retry, progress, cancellation, and offline/error recovery are absent.
- `currentUser` failure calls `fatalError`, and `PostModel` force-unwraps the API key.
- Main app and extension duplicate `SecureUser`/persistence code, increasing migration drift.

The SwiftUI rewrite must implement the advertised text/URL/1–4 image contract, wait for completion, retain the selected account and saved visibility, surface failures, and share a single persistence/API module with the app.

## Third-party and custom-library replacement ledger

Versions are from `Podfile.lock`; all are 2020-era and should be treated as incompatible until proven on the current toolchain.

| Legacy dependency | Use | Rewrite disposition |
| --- | --- | --- |
| MisskeyKit 3.0.4 + Starscream 3.1.1 | Misskey REST/auth/streaming | Repair/fork as a local Swift package or replace with typed URLSession/WebSocket protocol while preserving every API capability above |
| PolioPager 2.6 | Search + top timeline pager | Replace with SwiftUI pager/tab-strip implementation matching gesture, underline, offsets, and state restoration |
| In-repo YanagiText (`MisskeyTextView.swift`) | UITextView with embedded animated custom emoji | Retain/fix as a narrowly wrapped representable only if pure SwiftUI text cannot reach pixel/interaction parity; parser/rendering must be unit-tested |
| RxSwift/RxCocoa/RxDataSources | Binding and animated lists | Replace with Observation/Combine/structured concurrency and stable identifiable models |
| APNGKit, Gifu, SVGKit | APNG/GIF/SVG emoji/media | Replace/fork behind one animated-image protocol; verify frame timing, cancellation, cache, reuse, memory |
| Agrume | Image gallery | SwiftUI full-screen gallery with paging, zoom, dismissal, starting index |
| SkeletonView | Loading rows | SwiftUI redacted/shimmer implementation matching row geometry |
| FloatingPanel + XLActionController | Reaction sheet and note action menus | SwiftUI presentation/custom sheet matching legacy half/full detents and menu appearance |
| XLPagerTabStrip | Profile sub-tabs | SwiftUI tab strip with exact legacy underline/spacing |
| MessageKit/InputBarAccessoryView | Direct messages | SwiftUI conversation; preserve grouping, date/read labels, load-older, keyboard behavior |
| Eureka + ChromaColorPicker | Settings/forms/color | SwiftUI Form plus pixel-matched custom rows/color picker |
| SwiftLinkPreview + Cache | URL metadata/cache | URLSession metadata service and bounded actor cache |
| iOSPhotoEditor | Attachment/profile image edits | Modern PhotosUI/camera plus equivalent crop/draw/filter behavior, or maintained internal package |
| Firebase/Messaging 8.0.0 | Remote push transport | Upgrade to supported SDK/current APNs integration and revalidate token rotation and foreground payload handling |
| Native Security storage | API tokens | Replaced the former wrapper while preserving its generic-password schema for migration compatibility |

The old license screen must be regenerated from the final dependency graph, including every binary/source dependency and required attribution.

## Known legacy defects and parity decisions

These are not acceptable as “function parity”; they are regression tests that should fail against the old behavior and pass after migration.

1. Share extension first-attachment/text-only/saved-visibility/async-completion defects.
2. User-list follow/follower/list modes and pagination are declared but not implemented; profile counts do not navigate.
3. Pull-to-refresh for non-stream timelines is inert.
4. Detail-note overflow menu is inert and detail child pagination is disabled.
5. Profile update sends empty strings for unchanged optional fields and exits before confirming success.
6. Follow/unfollow reports success regardless of server result.
7. Compose dismisses immediately while upload/post result is not presented; empty/default-placeholder posting behavior needs an explicit validation test.
8. `MisscatApi.registerSw(owner:)` reads the global current user instead of consistently using its owner, risking wrong multi-account registration.
9. Direct-message `currentSender` reads global current user rather than the conversation owner; account switching can misclassify bubbles.
10. Timeline/share URLs are constructed with `http://` in places; all external note links must be HTTPS unless a deliberately supported development host requires otherwise.
11. Timeline stream ignores poll-vote updates, messages have no live stream, and NoteSearch tries to enter stream setup despite no matching channel.
12. App/share keychain access-group configuration appears inconsistent.
13. Checked-in push credential-shaped files and fixed secrets require removal/rotation; no values should be migrated.
14. The legacy test target contains only MFM string smoke tests plus a no-op example, and no UI-test target exists.

## Migration boundary

“Completely SwiftUI” should mean every app-owned screen and cell is declared in SwiftUI, navigation/state is SwiftUI-native, and UIKit view controllers/storyboards/XIBs are absent from normal UI flow. Framework bridges are acceptable only where Apple provides no SwiftUI surface (share extension host integration, web auth/web view, photo/camera picker, activity/safari/player) or where the custom animated MFM renderer is temporarily required for exact parity. Every bridge must be isolated behind an adapter, have an owner and removal rationale, and must not become the navigation root.
