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

## Audited syntax matrix

| Family | Native result | Executable behavior |
| --- | --- | --- |
| Mention, hashtag | MissCat route link | Native app route only |
| HTTP(S) URL, `<URL>`, labelled and silent link | `AttributedString.link` | System URL action |
| Local/remote custom emoji marker | Marker preserved for emoji substitution and VoiceOver | None |
| `**`, `__`, `<b>` | Strong presentation intent | None |
| `*`, `_`, `<i>` | Emphasis presentation intent | None |
| `~~`, `<s>` | Strikethrough presentation intent | None |
| Inline/block code and inline/block math | Code presentation intent | None |
| Quote | Static leading quote rule | None |
| `<center>` | Markers removed; content preserved | None |
| `<small>` | Markers removed; content preserved | None |
| `$[ruby base reading]` | `base（reading）` | None |
| `$[unixtime seconds]` | Stable UTC detail timestamp | None |
| Search line | Query plus native search indicator | None |
| `$[tada]`, `$[jelly]`, `$[twitch]`, `$[shake]`, `$[spin]`, `$[jump]`, `$[bounce]` | Static children | Motion disabled |
| `$[flip]`, `$[rotate]`, `$[position]`, `$[scale]`, `$[x2]`, `$[x3]`, `$[x4]` | Static children | Transform disabled |
| `$[font]`, `$[blur]`, `$[rainbow]`, `$[sparkle]`, `$[fg]`, `$[bg]`, `$[border]` | Static children | Dynamic styling disabled |
| `$[clickable]` | Static children | Callback disabled |
| `<plain>` | Exact literal content | Parsing and routing disabled |
| Unknown/malformed syntax | Exact visible literal | None |

Every row is represented in `MissCatNativeMFMTests`, including nested
functions, explicit newlines, plain escaped source, remote emoji markers, and
literal fallback.

## Animated custom emoji playback

ImageIO decoding is format-neutral and extracts every frame exposed by GIF,
APNG, and animated WebP sources. Format-specific unclamped/clamped delays and
loop counts are normalized into `MissCatCustomEmojiAnimation`; frame-count,
decoded-pixel, source-dimension, and payload bounds prevent animation bombs.
The cache and store retain the full animation while keeping `firstFrame` as a
source-compatible static fallback.

`MissCatAnimatedEmojiView` performs SwiftUI-only playback with `TimelineView`
and honors Reduce Motion. All frames share a fixed intrinsic box, so playback
cannot change wrapping:

| Context | Point size | First text baseline |
| --- | ---: | ---: |
| `.timelineBody` | 30 pt | 27 pt |
| `.timelineAuthor` | 25 pt | 22 pt |
| `.reaction` | 30 pt | 30 pt |

When `store.animationByName[name]` is present, body integration uses
`MissCatAnimatedEmojiView(animation: animation, context: .timelineBody,
accessibilityLabel: ":name:")`; author text uses `.timelineAuthor`, and reaction
chips use `.reaction`. A caller may also pass a custom point-size/baseline
context without changing the playback model.
The full animation and geometry contracts are unit-tested with a deterministic
two-frame GIF plus GIF/APNG/WebP timing dictionaries.
