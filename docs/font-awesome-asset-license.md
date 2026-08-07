# Font Awesome font asset license

MissCat retains two desktop-font assets from Font Awesome Free 5.9.0 because
the SwiftUI shell and note rows render the legacy glyphs with the
`FontAwesome5Free-Regular` and `FontAwesome5Free-Solid` font families. The font
version is embedded in both OTF name tables as `5.9.0`.

Font Awesome's official 5.9.0 repository states that desktop and web font files
are licensed under the SIL Open Font License 1.1. The checked-in notice is an
exact copy of the upstream 5.9.0 `LICENSE.txt`:

- source tag: <https://github.com/FortAwesome/Font-Awesome/tree/5.9.0>
- source notice: <https://raw.githubusercontent.com/FortAwesome/Font-Awesome/5.9.0/LICENSE.txt>
- checked-in notice: `ThirdPartyNotices/Font-Awesome-Free-LICENSE.txt`
- notice SHA-256: `e779748dfe75e84f974df3c7bc07f842011a100159158b0f1f49b2f2a5a515cb`

`scripts/verify-font-awesome-asset-license.rb` requires the notice, both OTFs,
their `UIAppFonts` declarations, PBX resource memberships, embedded 5.9.0
version marker, and shipping SwiftUI family usage to remain consistent. Its
fixture test proves that a missing notice, missing plist declaration, or an
unreviewed extra Font Awesome font fails the gate.

`Font Awesome 5 Brands-Regular-400.otf` was removed after the tracked-file,
PBX-resource, plist, and runtime-string audit found no shipping use. The
Regular and Solid fonts remain to preserve the legacy visual contract.
