#!/bin/bash
# Requires Xcode Command Line Tools and a logged-in macOS GUI session. Uses only the public synthetic fixture.
set -euo pipefail
source_dir="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:?Usage: check-plot-tools.sh /path/to/COSI-Explorer.app [result-directory]}"
app="$(cd "$app" && pwd)"
result_dir="${2:-$(mktemp -d "${TMPDIR:-/tmp}/cosi-plot-results.XXXXXX")}"
mkdir -p "$result_dir/first" "$result_dir/restored"
result_dir="$(cd "$result_dir" && pwd)"
fixture_dir="$(mktemp -d /private/tmp/cosi-plot-tools.XXXXXX)"
pref_suite="org.local.cosiexplorer.tests.$(uuidgen)"
trap 'rm -rf "$fixture_dir"; defaults delete "$pref_suite" >/dev/null 2>&1 || true' EXIT
cp "$source_dir/examples/synthetic-events.fits" "$fixture_dir/synthetic-events.fits"
"$app/Contents/MacOS/COSIExplorer" --data-root "$fixture_dir" --open "$fixture_dir/synthetic-events.fits" --preferences-suite "$pref_suite" --plot-tools-test-dir "$result_dir/first"
result="$(cat "$result_dir/first/ui-result.txt")";printf '%s\n' "$result"
case "$result" in PASS:*) ;; *) exit 1 ;; esac
"$app/Contents/MacOS/COSIExplorer" --data-root "$fixture_dir" --preferences-suite "$pref_suite" --plot-tools-test-dir "$result_dir/restored" --check-restored-workspace
result="$(cat "$result_dir/restored/ui-result.txt")";printf '%s\n' "$result"
case "$result" in PASS:*) ;; *) exit 1 ;; esac
xcrun clang++ -fobjc-arc -framework Cocoa -framework PDFKit "$source_dir/tests/verify-plot-figures.mm" -o "$fixture_dir/check-figures"
"$fixture_dir/check-figures" "$result_dir"/first/*.pdf
printf 'Native previews and exported figures: %s\n' "$result_dir"
