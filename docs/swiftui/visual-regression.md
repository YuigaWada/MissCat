# SwiftUI visual regression checks

Use `scripts/compare-screenshots.sh` to compare one legacy baseline with one SwiftUI candidate. The tool uses the repository's pinned executable location, `/opt/homebrew/bin/magick`, and does not require Simulator GUI automation.

## Screenshot naming

Store equivalent captures under separate roots and keep every comparison input explicit:

```text
artifacts/screenshots/baseline/<screen>--<device>--<os>--<appearance>.png
artifacts/screenshots/candidate/<screen>--<device>--<os>--<appearance>.png
```

For example:

```text
artifacts/screenshots/baseline/start--iphone-16-pro--ios-18.6--light.png
artifacts/screenshots/candidate/start--iphone-16-pro--ios-18.6--light.png
```

Baseline and candidate must use the same device, orientation, display scale, appearance, locale, Dynamic Type size, seeded app data, and screen state. The tool rejects differing pixel dimensions instead of resizing either input.

## Running a comparison

Exact comparison is the default and is the acceptance setting for design parity:

```sh
scripts/compare-screenshots.sh \
  --out "artifacts/visual-diff/start light" \
  "artifacts/screenshots/baseline/start--iphone-16-pro--ios-18.6--light.png" \
  "artifacts/screenshots/candidate/start--iphone-16-pro--ios-18.6--light.png"
```

The command reports:

- absolute changed pixels;
- changed-pixel ratio, normalized by evaluated (unmasked) pixels;
- absolute and normalized RMSE, normalized over evaluated pixels when a mask is used;
- input hashes, dimensions, thresholds, fuzz, and mask metadata in `summary.json`;
- `diff-heatmap.png`, `side-by-side.png`, and `overlay.png` inspection artifacts.

It exits `0` when the configured limits pass, `1` when a limit is exceeded, and `2` for invalid inputs or tooling errors. A changed ratio exactly equal to the threshold passes; a larger value fails.

Color fuzz and thresholds must be explicit when relaxed:

```sh
scripts/compare-screenshots.sh \
  --fuzz 0.5% \
  --threshold 0.001 \
  --max-rmse 0.01 \
  --out "artifacts/visual-diff/timeline" \
  "artifacts/screenshots/baseline/timeline--iphone-16-pro--ios-18.6--dark.png" \
  "artifacts/screenshots/candidate/timeline--iphone-16-pro--ios-18.6--dark.png"
```

Do not relax thresholds merely to make a comparison pass. Review the generated heatmap and side-by-side image first, and retain `summary.json` with the artifacts so the effective settings are auditable.

`--fuzz` controls which pixels count as changed and which pixels appear in the heatmap. RMSE deliberately retains the residual color error, so use `--max-rmse` independently when small widespread color shifts must also fail the check. Reports and generated PNGs omit timestamps and other volatile metadata so identical inputs and settings produce deterministic metrics and artifacts.

## Dynamic status-bar content

Prefer deterministic captures: use the same Simulator model/runtime and stabilize the clock, battery, network state, locale, and appearance. The comparison tool never crops or masks anything automatically.

If OS-owned status-bar values cannot be stabilized, an explicit same-size mask may be supplied with `--mask`. White pixels are compared and black pixels are ignored; the tool converts the mask to binary at 50%. Keep the black region to the smallest device-specific rectangle containing only dynamic OS status items. Never mask app navigation bars, titles, safe-area layout, sheets, or any other app-rendered UI.

```sh
scripts/compare-screenshots.sh \
  --mask "artifacts/screenshots/masks/iphone-16-pro--portrait-status-items.png" \
  --out "artifacts/visual-diff/start masked" \
  "artifacts/screenshots/baseline/start--iphone-16-pro--ios-18.6--light.png" \
  "artifacts/screenshots/candidate/start--iphone-16-pro--ios-18.6--light.png"
```

The report records the absolute mask path, SHA-256, and ignored-pixel count. The heatmap observes the mask, while side-by-side and overlay artifacts retain the complete original screenshots so an overly broad mask remains visible during review.

## Self-test

The shell self-test generates tiny fixtures, including paths containing spaces, using ImageMagick. It verifies exact matches, threshold failure/pass behavior, fuzz, explicit masking, output artifacts, JSON validity, and dimension rejection:

```sh
scripts/test-compare-screenshots.sh
```
