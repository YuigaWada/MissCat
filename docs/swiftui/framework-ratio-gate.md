# SwiftUI framework ratio gate

`scripts/verify-swiftui-framework-ratio.rb` measures the Swift sources in the
`MissCat` shipping target and prevents framework-migration debt from increasing.
It resolves `PBXSourcesBuildPhase` membership from
`MissCat.xcodeproj/project.pbxproj`; Swift files that merely exist in the
repository are not counted.

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
current shipping-target state. Default mode rejects increases in UIKit-only,
hybrid, Rx, Polio, active legacy-loader, or tracked IB counts, and rejects any
decrease in pure-SwiftUI progress.

Update the baseline only in the same reviewed change that demonstrably improves
the measured state. Do not raise a debt ceiling or lower the progress fraction
to make a regression pass.

The current App-target baseline is 64 Swift files: 2 UIKit-only, 25
SwiftUI-only, 3 hybrid, and 34 neutral. Rx, PolioPager, active legacy loaders,
and tracked Interface Builder artifacts are all zero. Pure-SwiftUI progress is
the exact fraction `25 / 30` (approximately `83.3333%`; the emitted floor is
`8333` basis points or `83.33%`).
