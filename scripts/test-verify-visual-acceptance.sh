#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
readonly repository_root="$(cd "${script_dir}/.." && pwd -P)"
readonly verifier="${script_dir}/verify-visual-acceptance.sh"
readonly validator="${script_dir}/validate-visual-evidence-json.rb"
readonly magick_bin="${MAGICK_BIN:-/opt/homebrew/bin/magick}"
readonly expected_digest="8c119a005579a70d5f373d3d82a0b9a33f62eabb896cfadd820487d48a087c50"

fail() {
    printf 'visual acceptance verifier self-test failed: %s\n' "$*" >&2
    exit 1
}

[[ -x "$verifier" ]] || fail "verifier is not executable"
[[ -x "$validator" ]] || fail "JSON validator is not executable"
[[ -x "$magick_bin" ]] || fail "ImageMagick is unavailable: $magick_bin"

fixture_dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/misscat-visual-verifier-test.XXXXXX")
trap 'rm -rf "$fixture_dir"' EXIT
fixture_repository="${fixture_dir}/repository"

inventory_output=$($verifier --inventory)
[[ "$inventory_output" == *"surfaces=45 visual_cases=710 recorded=0 missing=710 route_audits=1"* ]] || \
    fail "repository inventory is not the pinned 710-case contract"
[[ "$inventory_output" == *"requirements_sha256=${expected_digest}"* ]] || \
    fail "repository inventory did not report the pinned requirements digest"

incomplete_status=0
$verifier --require-complete > /dev/null 2>&1 || incomplete_status=$?
[[ "$incomplete_status" -eq 1 ]] || fail "the real repository must remain expected-red until screenshots exist"

/bin/mkdir -p "${fixture_repository}/docs" "${fixture_repository}/scripts" \
    "${fixture_repository}/artifacts/visual-acceptance/masks"
/bin/cp "${repository_root}/docs/visual-acceptance-requirements.tsv" "${fixture_repository}/docs/"
/bin/cp "${repository_root}/docs/visual-acceptance-mask-policy.tsv" "${fixture_repository}/docs/"
/bin/cp "${repository_root}/docs/visual-acceptance-capture-policy.tsv" "${fixture_repository}/docs/"
/bin/cp "$verifier" "$validator" "${repository_root}/scripts/compare-screenshots.sh" "${fixture_repository}/scripts/"
/bin/chmod +x "${fixture_repository}/scripts/verify-visual-acceptance.sh" \
    "${fixture_repository}/scripts/validate-visual-evidence-json.rb" \
    "${fixture_repository}/scripts/compare-screenshots.sh"

/usr/bin/awk -F '\t' 'BEGIN { OFS="\t" }
    /^#/ || NF == 0 { print; next }
    $1 == "id" { print; next }
    { $4="swiftui"; $5="accepted"; print }
' "${repository_root}/docs/ui-migration-surfaces.tsv" > "${fixture_repository}/docs/ui-migration-surfaces.tsv"

{
    printf '%s\n' '# schema_version=2'
    printf '%s\n' '# Empty until a unique, reviewed artifact bundle exists for a canonical case.'
    printf '%b\n' 'surface_id\tstate\tappearance\tdevice\tfixture\tlocale\tcontent_size\tvisual_ready\tbaseline\tcandidate\tdiff_dir\treview_record\tevidence_commit'
} > "${fixture_repository}/docs/visual-acceptance-evidence.tsv"

{
    printf '%s\n' '# schema_version=1'
    printf '%s\n' '# Synthetic portrait dimensions keep the exhaustive self-test fast while exercising exact policy enforcement.'
    printf '%b\n' 'device\torientation\tpixel_width\tpixel_height'
    printf '%b\n' 'iphone-16-pro-ios18.6\tportrait\t4\t6'
    printf '%b\n' 'iphone-se-3-ios18.6\tportrait\t4\t6'
} > "${fixture_repository}/docs/visual-acceptance-capture-policy.tsv"

git -C "$fixture_repository" init -q
git -C "$fixture_repository" config user.name YuigaWada
git -C "$fixture_repository" config user.email yuigawada@gmail.com
git -C "$fixture_repository" add docs scripts
git -C "$fixture_repository" commit -qm '[test] scaffold visual verifier fixture'

"$magick_bin" -size 4x6 xc:white -fill black -draw 'point 1,1' \
    "${fixture_repository}/artifacts/visual-acceptance/masks/minimal.png"
"$magick_bin" -size 4x6 xc:white -fill black -draw 'rectangle 0,0 1,1' \
    "${fixture_repository}/artifacts/visual-acceptance/masks/broad.png"

minimal_sha=$(/usr/bin/openssl dgst -sha256 -r "${fixture_repository}/artifacts/visual-acceptance/masks/minimal.png" | awk '{ print $1 }')
broad_sha=$(/usr/bin/openssl dgst -sha256 -r "${fixture_repository}/artifacts/visual-acceptance/masks/broad.png" | awk '{ print $1 }')
first_device=$(/usr/bin/awk -F '\t' '$1 == "01" { split($5, devices, "|"); print devices[1]; exit }' \
    "${fixture_repository}/docs/visual-acceptance-requirements.tsv")
{
    printf '%b\n' "${first_device}\tartifacts/visual-acceptance/masks/minimal.png\t${minimal_sha}\t1\t1\t1\t1\t1"
    printf '%b\n' "${first_device}\tartifacts/visual-acceptance/masks/broad.png\t${broad_sha}\t1\t0\t0\t1\t1"
} >> "${fixture_repository}/docs/visual-acceptance-mask-policy.tsv"

git -C "$fixture_repository" add docs/visual-acceptance-mask-policy.tsv artifacts/visual-acceptance/masks
git -C "$fixture_repository" commit -qm '[test] pin synthetic mask policy'
fixture_policy_commit=$(git -C "$fixture_repository" rev-parse HEAD)
fixture_policy_sha=$(/usr/bin/openssl dgst -sha256 -r \
    "${fixture_repository}/docs/visual-acceptance-mask-policy.tsv" | awk '{ print $1 }')
{
    printf '%s\n' '# schema_version=1'
    printf '%s\n' '# Synthetic policy approval is deliberately committed before evidence production.'
    printf '%b\n' 'policy_sha256\tpolicy_commit'
    printf '%b\n' "${fixture_policy_sha}\t${fixture_policy_commit}"
} > "${fixture_repository}/docs/visual-acceptance-mask-policy-approval.tsv"
git -C "$fixture_repository" add docs/visual-acceptance-mask-policy-approval.tsv
git -C "$fixture_repository" commit -qm '[test] approve synthetic mask policy independently'

/usr/bin/ruby -rjson -rfileutils -rzlib - "${fixture_repository}" "${fixture_dir}" <<'RUBY'
repository, fixture = ARGV
requirements = File.join(repository, "docs/visual-acceptance-requirements.tsv")
cases = []
File.foreach(requirements) do |line|
  next if line.start_with?("#") || line.strip.empty? || line.start_with?("surface_id\t")
  surface, group, states, appearances, devices, locales, sizes, focused, policy = line.chomp.split("\t", -1)
  next if policy == "route-audit"
  states.split("|").product(appearances.split("|"), devices.split("|"), locales.split("|"), sizes.split("|")).each do |state, appearance, device, locale, size|
    cases << [surface, group, state, appearance, device, locale, size]
  end
  unless focused == "none"
    focused.split("|").each do |entry|
      state, appearance, device, locale, size = entry.split("@", -1)
      cases << [surface, group, state, appearance, device, locale, size]
    end
  end
end
abort "fixture expansion did not produce 710 cases" unless cases.length == 710

def png_chunk(type, data)
  type = type.b
  data = data.b
  [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
end

def write_solid_png(path, index)
  width = 4
  height = 6
  pixel = [index & 0xff, (index >> 8) & 0xff, (index * 37) & 0xff, 255].pack("C4")
  scanlines = (("\x00".b + pixel * width) * height).b
  png = "\x89PNG\r\n\x1a\n".b
  png << png_chunk("IHDR", [width, height, 8, 6, 0, 0, 0].pack("NNC5"))
  png << png_chunk("IDAT", Zlib::Deflate.deflate(scanlines, Zlib::BEST_COMPRESSION))
  png << png_chunk("IEND", "".b)
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, png)
end

case_rows = []
cases.each_with_index do |(surface, group, state, appearance, device, locale, size), index|
  case_id = [surface, state, appearance, device, locale, size].join("--")
  root_relative = "artifacts/visual-acceptance/cases/#{case_id}"
  root = File.join(repository, root_relative)
  baseline_relative = "#{root_relative}/baseline.png"
  candidate_relative = "#{root_relative}/candidate.png"
  diff_relative = "#{root_relative}/diff"
  write_solid_png(File.join(repository, baseline_relative), index + 1)
  FileUtils.cp(File.join(repository, baseline_relative), File.join(repository, candidate_relative))
  case_rows << [surface, state, appearance, device, "#{group}--#{state}", locale, size,
                "visual-ready.#{group}.#{state}", baseline_relative, candidate_relative,
                diff_relative, "#{root_relative}/review.json"]
end
File.write(File.join(fixture, "cases.json"), JSON.generate(case_rows))
File.write(File.join(fixture, "cases.tsv"), case_rows.map { |row| row.join("\t") }.join("\n") + "\n")
RUBY

comparison_pids=()
while IFS=$'\t' read -r surface state appearance device fixture locale content_size visual_ready baseline candidate diff_dir review_record; do
    "${fixture_repository}/scripts/compare-screenshots.sh" \
        --magick "$magick_bin" \
        --surface-id "$surface" --state "$state" --appearance "$appearance" \
        --device "$device" --fixture "$fixture" --locale "$locale" \
        --orientation portrait \
        --content-size "$content_size" --visual-ready "$visual_ready" \
        --record-relative-to "$fixture_repository" \
        --out "${fixture_repository}/${diff_dir}" \
        "${fixture_repository}/${baseline}" "${fixture_repository}/${candidate}" \
        > /dev/null &
    comparison_pids+=("$!")
    if [[ "${#comparison_pids[@]}" -eq 8 ]]; then
        for comparison_pid in "${comparison_pids[@]}"; do
            wait "$comparison_pid" || fail "fixture comparator failed"
        done
        comparison_pids=()
    fi
done < "${fixture_dir}/cases.tsv"
for comparison_pid in "${comparison_pids[@]}"; do
    wait "$comparison_pid" || fail "fixture comparator failed"
done

git -C "$fixture_repository" add docs artifacts scripts
git -C "$fixture_repository" commit -qm '[test] produce immutable visual artifacts'
artifact_commit=$(git -C "$fixture_repository" rev-parse HEAD)
[[ "$artifact_commit" =~ ^[0-9a-f]{40}$ ]] || fail "fixture artifact commit is not full length"

/usr/bin/ruby -rjson -rdigest - "${fixture_repository}" "${fixture_dir}/cases.json" "$artifact_commit" <<'RUBY'
repository, cases_path, artifact_commit = ARGV
cases = JSON.parse(File.binread(cases_path))
evidence = File.join(repository, "docs/visual-acceptance-evidence.tsv")
File.open(evidence, "ab") do |manifest|
  cases.each do |row|
    surface, state, appearance, device, fixture, locale, size, ready,
      baseline, candidate, diff, review_relative = row
    overlay_relative = "#{diff}/overlay.png"
    review = {
      "schema_version" => 1,
      "case" => {
        "surface_id" => surface, "state" => state, "appearance" => appearance,
        "device" => device, "locale" => locale, "content_size" => size
      },
      "fixture" => fixture,
      "visual_ready" => ready,
      "evidence_commit" => artifact_commit,
      "overlay_sha256" => Digest::SHA256.file(File.join(repository, overlay_relative)).hexdigest,
      "reviewer" => {
        "decision" => "accepted", "identity" => "visual-verifier-self-test",
        "notes" => "Synthetic exact-match fixture inspected for verifier contract coverage.",
        "overlay_inspected_at_100_percent" => true
      }
    }
    review_path = File.join(repository, review_relative)
    File.write(review_path, JSON.pretty_generate(review) + "\n")
    manifest.puts((row + [artifact_commit]).join("\t"))
  end
end
RUBY

git -C "$fixture_repository" add docs/visual-acceptance-evidence.tsv artifacts
git -C "$fixture_repository" commit -qm '[test] record later visual reviews'

fixture_verifier="${fixture_repository}/scripts/verify-visual-acceptance.sh"
complete_output=$($fixture_verifier --require-complete --magick "$magick_bin")
[[ "$complete_output" == *"visual_cases=710 recorded=710 missing=0 route_audits=1"* ]] || \
    fail "full fixture did not pass the 710-case complete gate"

duplicate_paths=$(/usr/bin/cut -f 9-12 "${fixture_repository}/docs/visual-acceptance-evidence.tsv" | \
    /usr/bin/tail -n +2 | /usr/bin/tr '\t' '\n' | LC_ALL=C /usr/bin/sort | /usr/bin/uniq -d | /usr/bin/head -n 1)
[[ -z "$duplicate_paths" ]] || fail "successful fixture reused an evidence path: $duplicate_paths"

evidence="${fixture_repository}/docs/visual-acceptance-evidence.tsv"
requirements="${fixture_repository}/docs/visual-acceptance-requirements.tsv"
evidence_backup="${fixture_dir}/evidence.backup.tsv"
requirements_backup="${fixture_dir}/requirements.backup.tsv"
/bin/cp "$evidence" "$evidence_backup"
/bin/cp "$requirements" "$requirements_backup"

first_data=$(/usr/bin/awk -F '\t' '$1 ~ /^[0-9][0-9]$/ { print; exit }' "$evidence")
second_data=$(/usr/bin/awk -F '\t' '$1 ~ /^[0-9][0-9]$/ { count++; if (count == 2) { print; exit } }' "$evidence")
first_baseline=$(printf '%s\n' "$first_data" | /usr/bin/cut -f 9)
first_candidate=$(printf '%s\n' "$first_data" | /usr/bin/cut -f 10)
first_diff=$(printf '%s\n' "$first_data" | /usr/bin/cut -f 11)
first_review=$(printf '%s\n' "$first_data" | /usr/bin/cut -f 12)
second_baseline=$(printf '%s\n' "$second_data" | /usr/bin/cut -f 9)
second_candidate=$(printf '%s\n' "$second_data" | /usr/bin/cut -f 10)
first_summary="${fixture_repository}/${first_diff}/summary.json"

assert_failure() {
    local label="$1"
    local expected="$2"
    local output status=0
    output=$($fixture_verifier --require-complete --magick "$magick_bin" 2>&1) || status=$?
    [[ "$status" -eq 1 ]] || fail "$label must fail with status 1 (received $status)"
    [[ "$output" == *"$expected"* ]] || fail "$label failed for the wrong reason: $output"
}

rewrite_evidence() {
    local operation="$1"
    local value="${2:-}"
    /usr/bin/ruby - "$evidence" "$operation" "$value" <<'RUBY'
path, operation, value = ARGV
lines = File.readlines(path, chomp: true)
rows = lines.each_index.select { |index| lines[index].match?(/\A\d\d\t/) }
first, second = rows.fetch(0), rows.fetch(1)
case operation
when "duplicate"
  lines << lines[first]
when "unexpected"
  fields = lines[first].split("\t", -1); fields[1] = "unexpected-state"; lines[first] = fields.join("\t")
when "replay"
  source = lines[first].split("\t", -1); target = lines[second].split("\t", -1)
  (8..11).each { |column| target[column] = source[column] }
  lines[second] = target.join("\t")
when "same-images"
  fields = lines[first].split("\t", -1); fields[8] = fields[9]; lines[first] = fields.join("\t")
when "fixture"
  fields = lines[first].split("\t", -1); fields[4] = "wrong-fixture"; lines[first] = fields.join("\t")
when "commit"
  fields = lines[first].split("\t", -1); fields[12] = value; lines[first] = fields.join("\t")
else
  abort "unknown evidence rewrite"
end
File.write(path, lines.join("\n") + "\n")
RUBY
}

mutate_summary() {
    local operation="$1"
    local value="${2:-}"
    /usr/bin/ruby -rjson - "$first_summary" "$operation" "$value" <<'RUBY'
path, operation, value = ARGV
data = JSON.parse(File.binread(path))
case operation
when "similarity"
  data["comparison"]["changed_similarity"] = 0.89
when "channel"
  data["comparison"]["channel_delta"] = 9
when "numeric-string"
  data["comparison"]["ssim"] = "1.0"
when "metadata"
  data["capture"]["fixture"] = "wrong-fixture"
when "orientation"
  data["capture"]["orientation"] = "landscape"
when "forged-metric"
  data["comparison"]["ssim"] = 0.95
when "unapproved-mask"
  data["comparison"]["evaluated_pixels"] = 23
  data["mask"] = {
    "requested" => true, "applied" => true,
    "path" => "artifacts/visual-acceptance/masks/unapproved.png", "sha256" => "0" * 64,
    "ignored_pixels" => 1, "ignored_bounds" => { "x" => 1, "y" => 1, "width" => 1, "height" => 1 }
  }
when "broad-mask"
  data["comparison"]["evaluated_pixels"] = 20
  data["mask"] = {
    "requested" => true, "applied" => true,
    "path" => "artifacts/visual-acceptance/masks/broad.png", "sha256" => value,
    "ignored_pixels" => 4, "ignored_bounds" => { "x" => 0, "y" => 0, "width" => 2, "height" => 2 }
  }
else
  abort "unknown summary mutation"
end
File.write(path, JSON.pretty_generate(data) + "\n")
RUBY
}

/usr/bin/awk -F '\t' 'BEGIN { OFS="\t" } $1 == "01" { sub(/home[|]/, "", $3) } { print }' \
    "$requirements" > "${fixture_dir}/requirements.mutated.tsv"
/bin/mv "${fixture_dir}/requirements.mutated.tsv" "$requirements"
assert_failure "contract shrink" "invalid canonical requirement matrix"
/bin/cp "$requirements_backup" "$requirements"

/usr/bin/awk -F '\t' 'BEGIN { OFS="\t" } $1 == "43" { $9="visual" } { print }' \
    "$requirements" > "${fixture_dir}/requirements.mutated.tsv"
/bin/mv "${fixture_dir}/requirements.mutated.tsv" "$requirements"
assert_failure "wrong route-audit policy" "invalid canonical requirement matrix"
/bin/cp "$requirements_backup" "$requirements"

rewrite_evidence duplicate
assert_failure "duplicate evidence key" "duplicate evidence key"
/bin/cp "$evidence_backup" "$evidence"

rewrite_evidence unexpected
assert_failure "unexpected evidence state" "unexpected evidence case"
/bin/cp "$evidence_backup" "$evidence"

rewrite_evidence replay
assert_failure "replayed artifact triplet" "non-canonical baseline path"
/bin/cp "$evidence_backup" "$evidence"

rewrite_evidence same-images
assert_failure "identical baseline and candidate paths" "baseline and candidate paths must differ"
/bin/cp "$evidence_backup" "$evidence"

/bin/mv "${fixture_repository}/${second_baseline}" "${fixture_dir}/second-baseline.backup.png"
/bin/mv "${fixture_repository}/${second_candidate}" "${fixture_dir}/second-candidate.backup.png"
/bin/cp "${fixture_repository}/${first_baseline}" "${fixture_repository}/${second_baseline}"
/bin/cp "${fixture_repository}/${first_candidate}" "${fixture_repository}/${second_candidate}"
assert_failure "cross-case image-content replay" "reused or replayed baseline image content"
/bin/mv "${fixture_dir}/second-baseline.backup.png" "${fixture_repository}/${second_baseline}"
/bin/mv "${fixture_dir}/second-candidate.backup.png" "${fixture_repository}/${second_candidate}"

/bin/mv "${fixture_repository}/${first_baseline}" "${fixture_dir}/missing-baseline.png"
assert_failure "missing artifact" "missing baseline"
/bin/mv "${fixture_dir}/missing-baseline.png" "${fixture_repository}/${first_baseline}"

/bin/cp "${fixture_repository}/${first_baseline}" "${fixture_dir}/baseline-dimensions.backup.png"
/bin/cp "${fixture_repository}/${first_candidate}" "${fixture_dir}/candidate-dimensions.backup.png"
"$magick_bin" -size 20x20 xc:blue "${fixture_repository}/${first_baseline}"
"$magick_bin" -size 20x20 xc:blue "${fixture_repository}/${first_candidate}"
assert_failure "scaled 20x20 capture" "capture dimensions or orientation violate device policy"
"$magick_bin" -size 6x4 xc:blue "${fixture_repository}/${first_baseline}"
"$magick_bin" -size 6x4 xc:blue "${fixture_repository}/${first_candidate}"
assert_failure "wrong capture orientation" "capture dimensions or orientation violate device policy"
/bin/mv "${fixture_dir}/baseline-dimensions.backup.png" "${fixture_repository}/${first_baseline}"
/bin/mv "${fixture_dir}/candidate-dimensions.backup.png" "${fixture_repository}/${first_candidate}"

/bin/cp "${fixture_repository}/${first_diff}/overlay.png" "${fixture_dir}/overlay.backup.png"
"$magick_bin" -size 4x6 xc:red "${fixture_repository}/${first_diff}/overlay.png"
assert_failure "mutated artifact" "independent pixel recomputation overlay mismatch"
/bin/mv "${fixture_dir}/overlay.backup.png" "${fixture_repository}/${first_diff}/overlay.png"

/bin/cp "$first_summary" "${fixture_dir}/summary.backup.json"
mutate_summary similarity
assert_failure "below-threshold metric" "strict summary validation failed"
/bin/cp "${fixture_dir}/summary.backup.json" "$first_summary"

mutate_summary channel
assert_failure "relaxed channel tolerance" "strict summary validation failed"
/bin/cp "${fixture_dir}/summary.backup.json" "$first_summary"

mutate_summary numeric-string
assert_failure "malformed numeric type" "strict summary validation failed"
/bin/cp "${fixture_dir}/summary.backup.json" "$first_summary"

mutate_summary metadata
assert_failure "summary metadata mismatch" "strict summary validation failed"
/bin/cp "${fixture_dir}/summary.backup.json" "$first_summary"

mutate_summary orientation
assert_failure "summary orientation mismatch" "strict summary validation failed"
/bin/cp "${fixture_dir}/summary.backup.json" "$first_summary"

mutate_summary forged-metric
assert_failure "forged passing metric" "independent pixel recomputation metrics mismatch"
/bin/cp "${fixture_dir}/summary.backup.json" "$first_summary"

mutate_summary unapproved-mask
assert_failure "unapproved mask" "unapproved mask"
/bin/cp "${fixture_dir}/summary.backup.json" "$first_summary"

mutate_summary broad-mask "$broad_sha"
assert_failure "overbroad approved mask" "mask ignores too many pixels"
/bin/cp "${fixture_dir}/summary.backup.json" "$first_summary"

outside_baseline="${fixture_dir}/outside-baseline.png"
/bin/cp "${fixture_repository}/${first_baseline}" "$outside_baseline"
/bin/rm "${fixture_repository}/${first_baseline}"
/bin/ln -s "$outside_baseline" "${fixture_repository}/${first_baseline}"
assert_failure "symlink escape" "symlink or aliased baseline path"
/bin/rm "${fixture_repository}/${first_baseline}"
/bin/cp "$outside_baseline" "${fixture_repository}/${first_baseline}"

orphan_tree=$(git -C "$fixture_repository" write-tree)
orphan_commit=$(printf 'orphan artifact producer\n' | git -C "$fixture_repository" commit-tree "$orphan_tree")
rewrite_evidence commit "$orphan_commit"
assert_failure "non-ancestor evidence commit" "evidence_commit is not an ancestor"
/bin/cp "$evidence_backup" "$evidence"

rewrite_evidence commit "$(git -C "$fixture_repository" rev-parse HEAD)"
assert_failure "non-producing ancestor commit" "evidence_commit did not produce artifact"
/bin/cp "$evidence_backup" "$evidence"

rewrite_evidence fixture
assert_failure "manifest metadata mismatch" "fixture metadata mismatch"
/bin/cp "$evidence_backup" "$evidence"

/bin/mv "${fixture_repository}/${first_review}" "${fixture_dir}/missing-review.json"
assert_failure "missing review record" "missing review-record"
/bin/mv "${fixture_dir}/missing-review.json" "${fixture_repository}/${first_review}"

/bin/cp "${fixture_repository}/${first_review}" "${fixture_dir}/review.backup.json"
printf ' ' >> "${fixture_repository}/${first_review}"
assert_failure "mutated review record" "review record is mutable or drifted"
/bin/mv "${fixture_dir}/review.backup.json" "${fixture_repository}/${first_review}"

printf '%b\n' "${first_device}\tartifacts/visual-acceptance/masks/relaxed.png\t0000000000000000000000000000000000000000000000000000000000000000\t100\t0\t0\t4\t6" >> \
    "${fixture_repository}/docs/visual-acceptance-mask-policy.tsv"
git -C "$fixture_repository" add docs/visual-acceptance-mask-policy.tsv
git -C "$fixture_repository" commit -qm '[test] attempt simultaneous evidence policy relaxation'
rewrite_evidence commit "$(git -C "$fixture_repository" rev-parse HEAD)"
assert_failure "simultaneous mask policy relaxation" "mask policy digest is not independently approved"

printf 'visual acceptance verifier self-test passed (710 unique cases and 26 rejection contracts)\n'
