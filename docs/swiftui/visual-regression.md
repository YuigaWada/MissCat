# SwiftUI visual regression checks

Use `scripts/compare-screenshots.sh` to compare one legacy baseline with one SwiftUI candidate. The tool uses the repository's pinned executable location, `/opt/homebrew/bin/magick`, and does not require Simulator GUI automation.

## Screenshot naming

Each accepted case owns one canonical directory. Baseline, candidate, diff, and
review paths may not be shared with another case:

```text
artifacts/visual-acceptance/cases/<surface>--<state>--<appearance>--<device>--<locale>--<content-size>/baseline.png
artifacts/visual-acceptance/cases/<surface>--<state>--<appearance>--<device>--<locale>--<content-size>/candidate.png
artifacts/visual-acceptance/cases/<surface>--<state>--<appearance>--<device>--<locale>--<content-size>/diff/
artifacts/visual-acceptance/cases/<surface>--<state>--<appearance>--<device>--<locale>--<content-size>/review.json
```

Baseline and candidate must use the same device, orientation, display scale, appearance, locale, Dynamic Type size, seeded app data, and screen state. `docs/visual-acceptance-capture-policy.tsv` pins full-resolution portrait pixels for every allowed device (`1206x2622` for iPhone 16 Pro and `750x1334` for iPhone SE 3). The verifier hard-pins that policy's digest to `a4e8ae8bbfd9476a6e44c339b0e2a4f1d7c920936b6af86444af6c746b76b048`, so a producer cannot precommit a smaller or otherwise relaxed device profile. It rejects matching but scaled images, rotated or landscape images, cropping, and differing dimensions instead of resizing either input. Orientation is also recorded explicitly in `summary.json`.

## Running a comparison

The default acceptance setting implements the product threshold: changed-pixel similarity must be at least 0.90 and SSIM must independently be at least 0.90:

```sh
scripts/compare-screenshots.sh \
  --surface-id 01 --state home --appearance light \
  --device iphone-16-pro-ios18.6 \
  --orientation portrait \
  --fixture shell-home-pager--home \
  --locale ja-jp --content-size medium \
  --visual-ready visual-ready.shell-home-pager.home \
  --record-relative-to "$PWD" \
  --out "artifacts/visual-acceptance/cases/01--home--light--iphone-16-pro-ios18.6--ja-jp--medium/diff" \
  "artifacts/visual-acceptance/cases/01--home--light--iphone-16-pro-ios18.6--ja-jp--medium/baseline.png" \
  "artifacts/visual-acceptance/cases/01--home--light--iphone-16-pro-ios18.6--ja-jp--medium/candidate.png"
```

The command reports:

- absolute changed pixels;
- changed-pixel ratio and similarity, normalized by evaluated (unmasked) pixels;
- SSIM similarity over the same app-owned evaluation area;
- absolute and normalized RMSE, normalized over evaluated pixels when a mask is used;
- input hashes, dimensions, thresholds, fuzz, and mask metadata in `summary.json`;
- `diff-heatmap.png`, `side-by-side.png`, and `overlay.png` inspection artifacts.

It exits `0` when every configured limit passes, `1` when a limit is exceeded, and `2` for invalid inputs or tooling errors. The defaults are a maximum changed-pixel ratio of `0.10`, a minimum SSIM of `0.90`, and a per-channel change threshold of `8/255`. A pixel counts as changed when any RGB channel differs by more than eight levels. A metric exactly equal to its threshold passes.

Color fuzz and thresholds must be explicit when relaxed:

```sh
scripts/compare-screenshots.sh \
  --surface-id 08 --state home --appearance dark \
  --device iphone-16-pro-ios18.6 \
  --orientation portrait \
  --fixture timeline-family--home \
  --locale ja-jp --content-size medium \
  --visual-ready visual-ready.timeline-family.home \
  --record-relative-to "$PWD" \
  --fuzz 0.5% \
  --channel-delta 8 \
  --threshold 0.10 \
  --min-ssim 0.90 \
  --max-rmse 0.01 \
  --out "artifacts/visual-acceptance/cases/08--home--dark--iphone-16-pro-ios18.6--ja-jp--medium/diff" \
  "artifacts/visual-acceptance/cases/08--home--dark--iphone-16-pro-ios18.6--ja-jp--medium/baseline.png" \
  "artifacts/visual-acceptance/cases/08--home--dark--iphone-16-pro-ios18.6--ja-jp--medium/candidate.png"
```

Do not relax thresholds merely to make a comparison pass. Both required similarities must reach `0.90`; a strong result in one metric cannot compensate for a failure in the other. Review the generated heatmap and side-by-side image first, and retain `summary.json` with the artifacts so the effective settings are auditable.

`--channel-delta` controls which pixels count as changed and which pixels appear in the heatmap. `--fuzz` applies only to the diagnostic RMSE calculation; use `--max-rmse` independently when small widespread color shifts must also fail the check. Reports and generated PNGs omit timestamps and other volatile metadata so identical inputs and settings produce deterministic metrics and artifacts.

## Dynamic status-bar content

Prefer deterministic captures: use the same Simulator model/runtime and stabilize the clock, battery, network state, locale, and appearance. The comparison tool never crops or masks anything automatically.

No mask is currently approved by
`docs/visual-acceptance-mask-policy.tsv`. If OS-owned values cannot be stabilized,
review and pin a device-specific mask hash, ignored-pixel ceiling, and minimal
allowed rectangle before using `--mask`. The exact policy digest and its earlier
policy commit must be recorded in `docs/visual-acceptance-mask-policy-approval.tsv`
before screenshot artifacts are produced. A mask, policy relaxation, or approval
record introduced by the evidence commit is rejected; evidence producers cannot
approve their own exclusions. White pixels are compared and black
pixels are ignored. The verifier recomputes the ignored count and bounds and
rejects unapproved, changed, or overbroad masks. Never mask app navigation bars,
titles, safe-area layout, sheets, keyboard-owned app content, or controls.

## Self-test

The shell self-test generates tiny fixtures, including paths containing spaces, using ImageMagick. It verifies exact matches, the default per-channel `8/255` tolerance, changed-similarity and SSIM failure/pass behavior, explicit masking, output artifacts, JSON validity, and dimension rejection:

```sh
scripts/test-compare-screenshots.sh
```

## Complete acceptance inventory

`docs/visual-acceptance-requirements.tsv` is the pinned schema-v2 visual contract
joined to the 45-row migration ledger. Its exact digest is
`165e3faaaffe757219c684eb0d910149a79f5bf68a933e11309ae7edd2bfc2e5` and it
expands to exactly 698 visual cases. Base cases cover state, appearance, device,
locale, and content-size axes. Focused cases add long Japanese and Latin text,
RTL safety, accessibility Dynamic Type, keyboard presentation, compose media
counts, settings editors, and share text/URL/one-to-four-image combinations.
Surface 34 is explicitly deferred with no remote-notification runtime or visual
case in this revision. Surface 43 alone is a removal-only route audit.

`docs/visual-acceptance-evidence.tsv` is intentionally empty today. A future row
must bind the case, deterministic fixture, locale, content size, and exact
`visualReady` signal to unique canonical repository-relative paths. Its
`evidence_commit` is the earlier, non-merge artifact-producer commit that first tracks the
baseline, candidate, summary, heatmap, side-by-side image, and overlay. That
commit must not contain `review.json`. A later descendant commit adds the
reviewer's tracked acceptance record after 100% overlay inspection. The verifier
requires every artifact blob to match the producer commit, `HEAD`, and the working
tree, and requires the reviewer record to remain unchanged since its introduction.
Baseline and candidate image content must also be unique across canonical cases
and across their baseline/candidate roles. The verifier retains each raw PNG hash
for provenance, then separately hashes a canonical decoded 8-bit sRGB RGBA stream
with its dimensions and orientation. Distinct filenames, PNG compression, or
comments cannot legitimize a copied screenshot from another state. Pixel-identical
baseline and candidate captures remain valid only inside their one canonical case.
For every recorded row, the verifier reruns `compare-screenshots.sh` from the
tracked inputs and recorded settings, compares the independently calculated JSON
metrics, and requires byte-identical regenerated heatmap, side-by-side, and
overlay artifacts. A hand-authored passing summary is not acceptance evidence.
The authoritative capture policy, mask policy, and mask-policy approval record
must all exist unchanged before the artifact-producer commit. Any used mask must
already be an identical tracked blob at the independently pinned policy commit.

Validate the inventory while migration evidence is still incomplete:

```sh
scripts/verify-visual-acceptance.sh --inventory
```

The release/acceptance gate is intentionally strict and fails until every required
case exists and the removal-only surface is SwiftUI-owned and accepted:

```sh
scripts/verify-visual-acceptance.sh --require-complete
scripts/test-verify-visual-acceptance.sh
```

Do not add a weaker, replayed, or duplicate row to make the gate green. There are
no accepted rows or real screenshot bundles in this repository yet. Add the
missing deterministic fixture and distinct captures, commit the produced
artifacts, then have a reviewer inspect the 100% overlay and add `review.json` in
a later commit.
