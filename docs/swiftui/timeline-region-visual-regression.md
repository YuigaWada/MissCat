# Timeline named-region visual regression

Full-frame similarity can hide a shifted icon because most timeline pixels are
white. `scripts/compare-screenshot-regions.sh` applies the existing
`compare-screenshots.sh` metrics independently to every app-owned rectangle in
a versioned manifest. It then applies an additional bidirectional edge gate to
every action region.

The checked-in production contract is
`docs/visual-regions/timeline-home-iphone11promax-v1.json`. Its coordinates are
the exact rectangles from the region audit of the frozen 1242-by-2688 legacy
and current timeline pair. The manifest separately names:

- the timeline tabs;
- note 1–4 header/avatar and body areas that are visible in the capture;
- note 1 media;
- every visible reaction and note-action row;
- every visible row footer/divider; and
- the bottom navigation bar.

Do not replace those focused rectangles with a whole-note or whole-screen
rectangle. `required_region_ids` is an explicit completeness contract, and the
self-test pins both its order and its exact production action-region subset.

## Run the gate

Baseline and candidate must be same-size PNG files and must match the manifest's
canvas. No resizing, cropping, or automatic mask is performed before manifest
validation.

```sh
scripts/compare-screenshot-regions.sh \
  --manifest docs/visual-regions/timeline-home-iphone11promax-v1.json \
  --out artifacts/timeline-home-regions \
  artifacts/timeline-home/legacy.png \
  artifacts/timeline-home/current.png
```

The exit status is `0` only when every app-owned named region passes. Status `1`
means at least one required visual metric failed. Status `2` means the input,
manifest, dimensions, or comparison tooling was invalid.

The manifest schema is intentionally strict:

- `schema_version` is `1`;
- `canvas` pins the exact input dimensions;
- every `required_region_ids` entry has exactly one app-owned definition;
- duplicate, missing, unlisted, empty, or out-of-bounds regions are rejected;
- changed-pixel similarity and SSIM are each at least `0.90` per app region;
- `channel_delta` cannot exceed the existing comparator's `8/255` tolerance;
- action regions additionally require at least `0.90` bidirectional edge
  coverage after a two-pixel dilation; and
- amplified artifacts use a manifest-pinned integer scale from two through
  eight.

Bidirectional edge coverage is the lower of these two ratios: legacy edge
pixels found within two pixels of a current edge, and current edge pixels found
within two pixels of a legacy edge. Using the lower ratio detects both missing
and newly introduced control outlines. An action region with no edges on either
side fails rather than becoming vacuously accepted.

## Outputs

The output root contains deterministic `summary.json` and `summary.tsv` files.
Each `regions/<id>/` directory retains the existing comparator's summary,
heatmap, overlay, and side-by-side image, plus:

- `diff-amplified.png`;
- `side-by-side-amplified.png`; and
- for action regions, `edge-coverage-amplified.png` and the two source edge
  maps.

Pink marks legacy edges, cyan marks current edges, and overlap is visible in the
amplified action artifact. Paths recorded in the per-region summaries are
relative to the output root, so repeated runs over identical inputs and a fixed
manifest remain reproducible.

## Self-test

```sh
scripts/test-compare-screenshot-regions.sh
```

The self-test generates its PNGs deterministically and covers a passing pair,
metric failure, dimension and canvas mismatches, missing and duplicate regions,
out-of-bounds geometry, deterministic JSON/TSV/artifacts, and the sparse-control
case. In that last case, a small icon moves ten pixels across a white action
area: changed-pixel similarity and SSIM remain above `0.90`, but the required
two-pixel edge coverage rejects it.
