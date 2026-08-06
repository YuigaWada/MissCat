# Accounts and settings retirement map

This document fixes the ownership boundary for the grouped Accounts / Settings
migration. It is intentionally narrower than the final authenticated-root cutover.

## Ordinary routes after this bundle

| Route | Principal content | Temporary boundary |
| --- | --- | --- |
| Accounts footer tab | `MissCatAccountsScreen` | `AccountsListViewController` is now only a `UIHostingController` container while `HomeViewController` owns the root. |
| Accounts → add | `MissCatAddAccountView` using the existing native SwiftUI MiAuth flow | Full-screen `UIHostingController`; no legacy login controller. |
| Accounts → profile | Existing `MissCatProfileScreen` | Existing profile bridge. |
| Profile cog / Settings cog | `MissCatSettingsRootView` | A hosting controller hides the legacy navigation bar while the SwiftUI `NavigationStack` is active. |
| Design / reactions / licenses / About | Native SwiftUI destinations in the same navigation stack | Persistence adapters call the existing data stores only. |

All tokens remain inside `Cache.UserDefaults` / Keychain-backed legacy adapters.
The SwiftUI models and views receive account IDs and display metadata only.

## Explicitly retired ordinary controllers

- `AccountViewController` (`accounts-settings`) has no ordinary route. Its logout
  behavior is replaced by verified per-account deletion and the non-dismissible
  native add-account flow when the last account is removed.
- `ThemeViewController.swift` is historical commented source. Its storyboard scene
  is not reachable; the active Light/Dark and accent behavior belongs to
  `MissCatDesignSettingsScreen`.
- `SettingsViewController`, `DesignSettingsViewController`,
  `InstanceViewController`, `ReactionSettingsViewController`,
  `LicenseTableViewController`, `LicenseViewController`, and
  `AboutMisskeyViewController` remain compiled only as legacy visual/behavior
  baselines. `HomeViewController.openSettings()` no longer instantiates them.
- The old `StartViewController` add-account route is no longer used by Accounts.

## Physical removal gate

The inert storyboard scenes and legacy controller sources must be physically removed
with `Main.storyboard` at the authenticated-root cutover. Removing them earlier would
mix an unrelated storyboard graph rewrite into this bundle and discard the source of
truth needed for screenshot comparison. The final removal must verify:

1. no storyboard identifier or segue references the retired scenes;
2. the app launches directly into the native authenticated root;
3. Accounts add/switch/delete, all Settings destinations, and back navigation pass E2E;
4. deterministic 414×896 reference captures satisfy both >=0.90 changed-pixel
   similarity and >=0.90 SSIM;
5. the project has no source-build entry for the retired controllers.

## Persistence invariants

- Account deletion updates tabs only after Keychain/metadata removal succeeds.
- Current-account switching is read back and verified before the app root relaunches.
- A cancelled task cannot begin an account mutation; a mutation that crossed the
  persistence boundary is always reflected in visible state.
- Theme data stays under `theme-key`; reaction favorites stay compatible with the
  legacy instance-scoped `favs-<instance>` archive.
- No credential, token, cookie, or authentication payload is logged or exposed to a
  SwiftUI state object.

