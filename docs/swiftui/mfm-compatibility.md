# Native MFM compatibility

MissCat's SwiftUI timeline treats MFM as untrusted text. Parsing and rendering
stay inside Foundation/SwiftUI: no `WebView`, HTML execution, UIKit text bridge,
or motion effect is allowed.

## Pinned primary sources

The compatibility baseline was audited on 2026-08-08 against:

- [Misskey Hub MFM user syntax](https://misskey-hub.net/en/docs/for-users/features/mfm/)
- [`mfm.js` parser at `61c9dd10d29a054489a346629b0bb420659aa626`](https://github.com/misskey-dev/mfm.js/blob/61c9dd10d29a054489a346629b0bb420659aa626/src/internal/parser.ts)
- [Misskey Web MFM renderer at `988e3c32a39c1b0a30f71ffcf1f3baf19e5fcd5f`](https://github.com/misskey-dev/misskey/blob/988e3c32a39c1b0a30f71ffcf1f3baf19e5fcd5f/packages/frontend/src/components/global/MkMfm.ts)
- [Misskey Web custom emoji renderer at the same commit](https://github.com/misskey-dev/misskey/blob/988e3c32a39c1b0a30f71ffcf1f3baf19e5fcd5f/packages/frontend/src/components/global/MkCustomEmoji.vue)

The pinned commits make later parser drift explicit and reviewable.

## Safety and static-rendering contract

- Mentions, hashtags, HTTP(S) URLs, labelled links, custom emoji markers, and
  explicit line breaks remain available to interaction and accessibility.
- Bold, italic, strike, and inline/block code become native
  `AttributedString` presentation intents.
- Quote, center, ruby, date/time, small, plain, math, and search syntax is
  converted to a legible static representation without leaving source markers.
- Motion/transform functions (`tada`, `jelly`, `twitch`, `shake`, `spin`,
  `jump`, `bounce`, `flip`, `rotate`, `position`, `scale`, `x2`-`x4`,
  `rainbow`, and `sparkle`) never execute. Their children still render.
- Color, border, font, blur, and clickable functions keep their children but do
  not introduce executable styling or event callbacks.
- Unknown or malformed syntax remains visible as literal text. Text must never
  be silently discarded.
- `<plain>` content bypasses formatting and interactive-token discovery.

## Animated custom emoji tracking

`MFM-EMOJI-ANIMATION-01` remains open. The current inline renderer composes
custom emoji through `Text(Image)`, which accepts one immutable frame. Replacing
that with independently animated views would change wrapping and baseline
geometry and is therefore not safe inside this parser change. A two-frame GIF
fixture now locks ImageIO frame-count and delay extraction so a future native
inline layout can consume every frame without changing the transport contract.
Static display intentionally uses the first decoded frame until that layout is
implemented and visually accepted. This applies equally to animated GIF, APNG,
and animated WebP when the installed ImageIO runtime exposes multiple frames.
