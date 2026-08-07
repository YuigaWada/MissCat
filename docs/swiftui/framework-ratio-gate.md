# SwiftUI framework ratio gate

`scripts/verify-swiftui-framework-ratio.rb` measures the Swift sources in the
selected shipping target and prevents framework-migration debt from increasing.
It resolves `PBXSourcesBuildPhase` membership from
`MissCat.xcodeproj/project.pbxproj`; Swift files that merely exist in the
repository are not counted.

## Aggregate shipping progress

The canonical product-level progress gate is:

```sh
scripts/verify-swiftui-framework-aggregate.rb
scripts/test-verify-swiftui-framework-aggregate.sh
```

It reuses the same PBX membership resolver and source classifier for both
shipping targets, `MissCat` and `MissCatShare`, and writes one JSON document
containing each target plus their aggregate. Memberships are summed, so a Swift
file built by both targets represents two shipping memberships. The
repository-wide tracked Interface Builder count is reported for each target but
is counted only once in the aggregate.

The checked-in aggregate baseline is:

| Scope | UIKit-only | SwiftUI-only | Hybrid | Neutral | Pure SwiftUI |
| --- | ---: | ---: | ---: | ---: | ---: |
| `MissCat` | 1 | 29 | 0 | 32 | 29 / 30 (96.667%) |
| `MissCatShare` | 0 | 1 | 1 | 6 | 1 / 2 (50%) |
| All shipping memberships | 1 | 30 | 1 | 38 | 30 / 32 (93.75%) |

The aggregate JSON also reports Rx, PolioPager, active legacy-loader file and
reference counts, and tracked storyboard/XIB artifacts for both targets and the
combined gate. Its basis-point value is floored for integer ratcheting while
`percent` is calculated from the exact fraction and rounded to three decimal
places.

Run the final-state check with:

```sh
scripts/verify-swiftui-framework-aggregate.rb --require-complete
```

That mode currently fails for two explicit architectural reasons: the App
target still has one UIKit-only source member, and
`ShareViewController` is still the `NSExtensionPrincipalClass` hybrid boundary.
The JSON exposes those reasons as structured `completion_blockers`; completion
also requires zero Rx, PolioPager, active legacy-loader, and tracked IB debt.

Run the ratchet and its shell-only fixtures with:

```sh
scripts/verify-swiftui-framework-ratio.rb
scripts/test-verify-swiftui-framework-ratio.sh
```

The verifier writes one JSON document to standard output and exits with `0` when
the gate passes, `1` for a metric violation, `2` for invalid project or baseline
input, and `64` for invalid command-line usage. To test the final migration
condition, run:

```sh
scripts/verify-swiftui-framework-ratio.rb --require-complete
```

This stricter mode intentionally fails until `uikit_only`, `hybrid`, `rx_files`,
`polio_files`, both active legacy-loader counts, and `tracked_ib_artifacts` are
all zero.

## Metric definitions

Each target-member Swift file is classified exactly once by its imports:

- `uikit_only`: imports UIKit but not SwiftUI.
- `swiftui_only`: imports SwiftUI but not UIKit.
- `hybrid`: imports both UIKit and SwiftUI.
- `neutral`: imports neither framework.

`rx_files` counts files importing a module whose name begins with `Rx`, and
`polio_files` counts files importing `PolioPager`. `legacy_loader_files` and
`legacy_loader_refs` count source files and active source lines that use
`UIStoryboard`, `UINib`, `instantiateViewController(...)`, or a `nibName:`
argument; full-line `//` comments are excluded. `tracked_ib_artifacts` counts
Git-tracked `*.storyboard` and `*.xib` paths across the repository, because
retiring those versioned artifacts is independent of source build-phase
membership.

`pure_swiftui_progress` is the exact fraction:

```text
swiftui_only / (uikit_only + swiftui_only + hybrid)
```

Neutral files are excluded because they do not choose either UI framework. The
JSON also emits the floor of that fraction in basis points and as a percentage;
the ratchet compares the fraction itself by integer cross multiplication.

## Baseline policy

The checked-in `config/swiftui-framework-ratio-baseline.json` records the
current App-target state. The canonical aggregate baseline is
`config/swiftui-framework-aggregate-baseline.json`; it records both targets and
requires its aggregate counts to equal their membership sum. Default mode
rejects increases in UIKit-only,
hybrid, Rx, Polio, active legacy-loader, or tracked IB counts, and rejects any
decrease in pure-SwiftUI progress at either the target or aggregate scope.

Update the baseline only in the same reviewed change that demonstrably improves
the measured state. Do not raise a debt ceiling or lower the progress fraction
to make a regression pass.

The current App-target baseline is 62 Swift files: 1 UIKit-only, 29
SwiftUI-only, 0 hybrid, and 32 neutral. Rx, PolioPager, active legacy loaders,
and tracked Interface Builder artifacts are all zero. Pure-SwiftUI progress is
the exact fraction `29 / 30` (approximately `96.6667%`; the emitted floor is
`9666` basis points or `96.66%`).

The one UIKit-only file is an intentional, audited OS adapter rather than a
screen implementation:

- `MissCatSystemClipboardWriter.swift` preserves the custom one-tap copy action
  with one `UIPasteboard` write method.

Remote push transport is deferred and no application delegate or dormant
Firebase/APNs ingress ships. Moving OS integration, routing state, or fixture
probes into neutral files does not increase the numerator and is not counted as
migration progress. Strict completion remains honestly red with exactly this
one UIKit-only file; the default ratchet merely prevents the boundary from
growing.
