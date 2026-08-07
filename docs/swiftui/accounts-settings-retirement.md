# Accounts and settings retirement map

This document records the ownership boundary for the grouped Accounts / Settings
migration after the authenticated-root cutover and physical legacy-source removal.

## Ordinary routes after this bundle

| Route | Principal content | Remaining acceptance boundary |
| --- | --- | --- |
| Accounts footer tab | `MissCatAccountsRootView` / `MissCatAccountsScreen` | The native SwiftUI shell owns the route; authenticated live-service and final visual acceptance remain. |
| Accounts → add | `MissCatAddAccountView` using the existing native SwiftUI MiAuth flow | SwiftUI `fullScreenCover`; no UIKit presentation and no legacy login controller. |
| Accounts → profile | Existing `MissCatProfileScreen` | Typed `MissCatAccountsRoute.profile(accountID:)` inside the Accounts `NavigationStack`; no UIKit profile destination. |
| Profile cog / Settings cog | `MissCatSettingsRootView` | The production SwiftUI router and `NavigationStack` own presentation and back navigation. |
| Design / reactions / licenses / About | Native SwiftUI destinations in the same navigation stack | Persistence adapters call the existing data stores only. |

All tokens remain inside `Cache.UserDefaults` / Keychain-backed adapters. The
Accounts route carries only the opaque local composite account identifier and
display metadata. A token is resolved at the production profile destination
boundary and passed directly to the existing profile repository; it is never a
navigation value, accessibility value, fixture value, or log field.

## Explicitly retired ordinary controllers

- `AccountViewController` (`accounts-settings`) was physically removed. Its logout
  behavior is replaced by per-account deletion and the non-dismissible native
  add-account flow when the last account is removed.
- `ThemeViewController.swift` and its storyboard scene were physically removed; the
  active Light/Dark and accent behavior belongs to `MissCatDesignSettingsScreen`.
- `SettingsViewController`, `DesignSettingsViewController`,
  `InstanceViewController`, `ReactionSettingsViewController`,
  `LicenseTableViewController`, `LicenseViewController`, and
  `AboutMisskeyViewController` were physically removed with the retired
  `HomeViewController` shell.
- The old `StartViewController` add-account route was physically removed.

## Physical removal status

The authenticated-root cutover and physical cleanup are complete. The tracked-source
boundary verifies that every tracked Swift source has explicit PBX ownership, no
retired controller source or PBX reference has reappeared, and no storyboard or XIB is
tracked. The production app launches through the native SwiftUI root rather than the
retired `HomeViewController` graph.

Physical removal does not imply final feature acceptance. Authenticated live-service
coverage for Accounts add/switch/delete and every Settings destination, plus the final
402x874-point iPhone 16 Pro / iOS 18.6 screenshot comparison at >=0.90 similarity and
>=0.90 SSIM, remains part of the migrating acceptance work.

## Persistence invariants

- Account deletion updates tabs only after Keychain/metadata removal succeeds.
- Current-account switching is read back and verified before the app root relaunches.
- A cancelled task cannot begin an account mutation; a mutation that crossed the
  persistence boundary is always reflected in visible state.
- Theme data stays under `theme-key`; reaction favorites stay compatible with the
  legacy instance-scoped `favs-<instance>` archive.
- No credential, token, cookie, or authentication payload is logged or exposed to a
  SwiftUI state object.
