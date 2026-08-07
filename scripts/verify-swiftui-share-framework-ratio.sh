#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(cd -- "$script_dir/.." && pwd)

exec ruby "$script_dir/verify-swiftui-framework-ratio.rb" \
  --repository-root "$repository_root" \
  --target MissCatShare \
  --baseline "$repository_root/config/swiftui-share-framework-ratio-baseline.json" \
  "$@"
