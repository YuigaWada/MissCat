#!/usr/bin/env bash

set -euo pipefail

readonly script_dir="$(cd "$(dirname "$0")" && pwd -P)"
exec /usr/bin/ruby "$script_dir/compare-screenshot-regions.rb" "$@"
