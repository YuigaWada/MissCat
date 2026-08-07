# Tracked Swift source boundary

`scripts/verify-tracked-swift-source-boundary.rb` audits every Git-tracked
first-party Swift source against every `PBXNativeTarget` in
`MissCat.xcodeproj`. It complements the per-target framework-ratio ratchet by
preventing retired code from remaining dormant outside a build phase.

Run the production gate and its isolated fixture suite with:

```sh
scripts/verify-tracked-swift-source-boundary.rb
scripts/test-verify-tracked-swift-source-boundary.rb
```

The verifier emits one JSON document. Exit status `0` means the boundary is
clean, `1` means a policy violation was found, `2` means the repository,
project, or manifest input is invalid, and `64` means command-line usage is
invalid.

## Enforced policy

- Every tracked first-party `*.swift` file belongs to at least one native
  target. Sources below `Pods`, vendor/third-party, or generated directories are
  reported separately and excluded from first-party ownership checks.
- Every tracked first-party Swift source has exactly one resolved PBX file
  reference, and every PBX Swift file reference resolves to a tracked managed
  source. Dormant, duplicate, and dangling project references are rejected.
- Every tracked or PBX-referenced `*.storyboard` and `*.xib` is rejected.
  Interface Builder artifact and project-reference counts must remain exactly
  zero.
- The retired `Entity`, `MFMEngine`, `Model`, `View`, and `ViewModel` trees,
  `SceneDelegate.swift`, legacy `ViewController.swift` names, and legacy
  `ViewModel.swift` names cannot return.
- Any import whose module begins with `Rx`, and any `PolioPager` import, is
  rejected across managed Swift sources.
- Shipping-target UIKit imports are limited to two active OS integration
  boundaries: system clipboard access and the share-extension principal
  controller. Application delegation was removed with remote push transport.
  Test-only UIKit imports do not count as shipping architecture.
- `docs/retired-swift-source-manifest.json` is the immutable pre-deletion
  checksum ledger. Reintroducing any path from that ledger fails independently
  of PBX membership.

The JSON target map includes the complete, resolved Swift membership for the
App, Share extension, unit-test, and UI-test targets. Review membership changes
alongside any source addition or removal; do not silence the gate by extending
the retired-pattern rules or UIKit allowlist without a documented OS-boundary
requirement.
