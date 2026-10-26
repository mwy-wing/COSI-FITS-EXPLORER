#!/bin/bash
# Rebuild the original vector, PNG and ICNS with macOS tools; no network or image model.
set -euo pipefail
source_dir="$(cd "$(dirname "$0")/.." && pwd)"
staging="$(mktemp -d "${TMPDIR:-/tmp}/cosi-icon.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/COSIExplorer.iconset"
xcrun clang++ -std=c++17 -fobjc-arc -framework Cocoa "$source_dir/scripts/render-icon.mm" -o "$staging/render-icon"
"$staging/render-icon" "$source_dir/resources" "$staging/COSIExplorer.iconset"
iconutil -c icns "$staging/COSIExplorer.iconset" -o "$source_dir/resources/COSIExplorer.icns"
printf 'Updated original SVG, PNG and ICNS in %s/resources\n' "$source_dir"
