#!/bin/bash
# Runs the app's own controls against a synthetic fixture; no external UI scripting.
set -euo pipefail
app="${1:?Usage: check-compliance.sh /path/COSI-Explorer.app /path/cosi-validation-tests [output]}"
helper="${2:?Pass the compiled cosi-validation-tests helper}"
result_dir="${3:-$(mktemp -d /private/tmp/cosi-compliance-results.XXXXXX)}"
mkdir -p "$result_dir"
result_dir="$(cd "$result_dir" && pwd)"
fixture_dir="$(mktemp -d /private/tmp/cosi-compliance.XXXXXX)"
trap 'rm -rf "$fixture_dir"' EXIT
"$helper" --write-faulty-fixture "$fixture_dir/compliance-demo.fits"
"$app/Contents/MacOS/COSIExplorer" --no-restore --data-root "$fixture_dir" --open "$fixture_dir/compliance-demo.fits" --compliance-test-dir "$result_dir"
result="$(cat "$result_dir/ui-result.txt")"
printf '%s\n' "$result"
case "$result" in PASS:*) ;; *) exit 1 ;; esac
