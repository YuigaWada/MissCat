# Timeline visual fixture sources

The timeline acceptance fixture uses component-only crops from the immutable legacy
home screenshot. The complete screenshot is never rendered in the app. Each crop is
rendered through the same avatar or media view path used by production notes.

- Source: `images/ScreenShot/iPhoneX/Simulator Screen Shot - iPhone 11 Pro Max - 2020-03-28 at 19.32.36.png`
- Source SHA-256: `ee5a674eb56d347233addc3d644b42b7eb0fde4f87e5d628934a92309cfa974f`
- `TimelineFixtureAvatarSyuilo.png`: `150x150+60+303`
- `TimelineFixtureAvatarLiquid.png`: `150x150+60+1201`
- `TimelineFixtureAvatarWada.png`: `150x150+60+1691`
- `TimelineFixtureAvatarAqz.png`: `150x150+60+2227`
- `TimelineFixtureTerminal.png`: `940x390+240+519`
- `TimelineFixtureEmojiVerified.png`: `75x75+326+1184`
- `TimelineFixtureEmojiYellow.png`: `75x75+400+1676`
- `TimelineFixtureEmojiErai.png`: `80x90+550+1658`

Component SHA-256 values, in the same order, are
`1555692e8c86e5595f5f47a531b92a22f052cc246c59948b046bbfd579d598c3`,
`ebc734405aade210a3611d6c65c54de0e504b50063bb6fc6adaef3dec4d6f719`,
`fb24496e44f2abaa30e2706620d4bd64f1383f5ce7fe6f0436987c9dd13fc3b5`,
`9aa74790ccb59be963827e11231747d0ac206686566d7c7eaa0a2d79c8debbb9`, and
`1284f1b8a017ef4ffcb8a24a74ca6ac0a1209e778fa6ff2463c8dd9df20699cd`.
The three custom-emoji component hashes are
`93cbdfdd81ed5d06dc5870611ceb198be192e50640306a4363d6fcb96be4baa3`,
`caf88202974b03c78413605ca7b51a6e759e5a4905b8d615cc4c7b247d7dcf0a`, and
`38262e0373cd78c64f248e479523bb3c23588bb434aa5a6c70f37da1b46cd248`.

Coordinates are ImageMagick crop geometry in source pixels. These assets are only
selected by the DEBUG launch fixture; network/API notes never populate local image names.
