#!/bin/bash
# Build a local release; does not create a repository, push, or publish.
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${1:-$source_dir/build}"
output_dir="${2:-$source_dir/dist}"
bash "$source_dir/build.sh" "$build_dir" "$output_dir"
if [[ "$(uname -s)" == Darwin ]]; then bash "$source_dir/scripts/create-dmg.sh" "$output_dir"; fi
python3 "$source_dir/scripts/package-source.py" "$output_dir"
