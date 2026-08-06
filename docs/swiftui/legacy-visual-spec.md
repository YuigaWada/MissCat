# MissCat legacy visual contract

This note records the evidence used by the isolated SwiftUI presentation layer in
`MissCat/SwiftUI`. Values are intentionally based on the legacy files, rather than on
current iOS defaults, so automated screenshot comparisons have a stable target.

## Reference canvases

| Reference | Logical canvas | What it proves |
| --- | ---: | --- |
| `images/ScreenShot/iPhoneX/...19.35.01.png` | 414 × 896 pt (@3x) | Welcome screen, safe-area placement, gradient, button sizing |
| `images/ScreenShot/iPhoneX/...19.32.36.png` | 414 × 896 pt (@3x) | Home timeline header and five-item footer |
| `images/ScreenShot/iPhoneX/...19.32.58.png` | 414 × 896 pt (@3x) | Standard pushed navigation treatment |
| `images/ScreenShot/iPhoneX/...19.33.13.png` | 414 × 896 pt (@3x) | Profile selected state in footer |
| `images/ScreenShot/iPhone Pro/...00.28.14.png` | 414 × 736 pt (@3x) | Footer scaling and notification selected state |
| `Resources/Base.lproj/LaunchScreen.storyboard` | 414 × 896 pt | Splash background and centered 19.6429%-height icon |
| `View/Base.lproj/Main.storyboard` | 414 × 896 pt | Welcome, terms and web authentication constraints |
| `View/Reusable/Tab/nib/TabBar.xib` | 414 × 80 pt design canvas | Tab order, icon names, spacing, separator and compose circle |

The remaining reference screenshots exercise note cells, replies, notification rows, the
profile screen and emoji search. They are outside the shell views in this change, but must
be retained as golden images for their respective feature migrations.

## Welcome/authentication

- Background gradient matches the legacy `CAGradientLayer`: bottom-leading `#4691A3`,
  midpoint `#5AB0C5`, top-trailing `#89D5E8`.
- `Logo` is aspect-fit, 40 pt from both sides, 112 pt high, and starts 236 pt below the
  top safe area on the 414 × 896 reference canvas.
- Tagline is 17 pt system, white, 3 pt below the logo.
- Buttons are each 39.8551% of the canvas width and 5.69196% of canvas height. On the
  reference canvas that is 165 × 51 pt. They have 10 pt corners, a 44 pt gap and 20 pt
  outer insets.
- The change-instance button ends 50 pt above the bottom safe area. The current instance
  is 15 pt system and ends 10 pt above the bottom safe area, trailing by 20 pt.
- The non-logo controls reproduce the original 0.7-second ease-in/out fade from y −30.
- Terms use the exact legacy text and preserve a scrollable text area plus the trailing
  `同意する` action. The web authentication view fills the safe area and has a reload item.

## Main shell

- Default theme: accent `#2F7CF6`, base `#FFFFFF`, text `#000000`, border `#C6C6C6`.
- Home header is 43 pt high. It contains search, `Home`, `Local`, and `Global`; the active
  underline is 2 pt high. The bottom hairline is 0.5 pt.
- Non-home sections use a 44 pt custom header and legacy titles: `Notifications`, `Chat`,
  and `Accounts`. The Accounts header exposes the settings action.
- Footer order is Home, Notifications, Compose, Messages, Profile. Its content height is
  55 pt and remains above the device bottom safe area. Compose uses a 48 pt accent circle;
  selected roots use the accent and inactive roots use 67% gray.
- Footer actions preserve reselect semantics so Home/Notifications can scroll or refresh
  when their already-selected buttons are tapped.

## E2E accessibility contract

- Welcome: `welcome.screen`, `welcome.signup`, `welcome.login`,
  `welcome.change-instance`, `welcome.instance`.
- Terms/auth: `terms.screen`, `terms.text`, `terms.agree`,
  `authentication.flow`, `authentication.loading`, `authentication.browser`,
  `authentication.reload`.
- Instance editor: `instance.screen`, `instance.field`, `instance.cancel`, `instance.apply`.
- Main shell: `main.shell`, `main.timeline.search`, `main.timeline.<id>`,
  `main.tab.home`, `main.tab.notifications`, `main.action.compose`,
  `main.tab.messages`, `main.tab.profile`, `main.header.settings`.

## Screenshot comparison procedure

1. Render at 414 × 896 points on a 3x simulator, with text size set to the default and the
   light appearance forced for the historical baselines.
2. Seed authentication state so both welcome and main-shell fixtures are deterministic.
3. Capture PNG files with `simctl io <device> screenshot`.
4. Compare after cropping only OS-controlled status-bar differences. UI-owned pixels must
   remain uncropped. Track pixel mismatch percentage plus a perceptual diff image.
5. Repeat shell layout at 414 × 736 points to detect unsafe fixed-height assumptions.

## Known evidence gaps

- No repository screenshot covers the Terms or live WebKit authorization pages. Their
  authoritative references are storyboard constraints and the instance-provided website.
- Timeline/profile/notification row content is deliberately injected into the shell and is
  not implemented by these files.
- SF Symbols are used for the five shell icons. Their silhouettes closely match the 2020
  Font Awesome screenshots while avoiding the legacy font dependency; golden-image review
  should decide whether exact bundled Font Awesome glyph rendering is still required.
