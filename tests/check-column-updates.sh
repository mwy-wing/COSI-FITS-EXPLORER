#!/bin/bash
# Run on macOS with a GUI session; the fixture stays read-only.
set -euo pipefail
app="${1:?Usage: check-column-updates.sh /path/to/COSI-Explorer.app /path/to/Data [result-directory]}"
data_root="${2:?Provide the COSI-SDC Data directory}"
result_dir="${3:-$(mktemp -d "${TMPDIR:-/tmp}/cosi-column-check.XXXXXX")}"
mkdir -p "$result_dir"
rm -f "$result_dir/ui-result.txt"
"$app/Contents/MacOS/COSIExplorer" --data-root "$data_root" \
  --open "$data_root/26/10/06/v1/L2/cs20260630ged_00_l2.fits" \
  --column-test-dir "$result_dir"
result="$(cat "$result_dir/ui-result.txt")"
printf '%s\n' "$result"
case "$result" in PASS:*) ;; *) exit 1 ;; esac
