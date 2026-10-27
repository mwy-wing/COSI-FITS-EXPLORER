#!/bin/bash
# Wrap the verified app ZIP in a drag-to-Applications disk image.
set -euo pipefail
source_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$source_dir/dist}"
version="$(sed -n 's/^project(COSIExplorer VERSION \([^ ]*\).*/\1/p' "$source_dir/CMakeLists.txt")"
architecture="${COSI_DMG_ARCH:-$(uname -m)}"
archive="$output_dir/COSI-Explorer-v$version-macos-$architecture.zip"
image="$output_dir/COSI-Explorer-v$version-macos-$architecture.dmg"
if [[ ! -f "$archive" ]]; then printf 'Build the app ZIP first: %s\n' "$archive" >&2; exit 1; fi
stage="$(mktemp -d "${TMPDIR:-/tmp}/cosi-dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/volume"
# Use the signed ZIP, not a live .app that Finder/iCloud may have decorated.
ditto --norsrc --noextattr -x -k "$archive" "$stage/volume"
codesign --verify --deep --strict "$stage/volume/COSI Explorer.app"
ln -s /Applications "$stage/volume/Applications"
cat > "$stage/volume/INSTALL.txt" <<TXT
COSI Explorer v$version

1. Drag COSI Explorer.app onto Applications.
2. Eject this disk image.
3. Open COSI Explorer from Applications, then choose your own data file/folder.

Requires an Apple Silicon Mac with macOS 15 or later.
No Homebrew, compiler, or CFITSIO installation is needed.

This build is locally ad-hoc signed, not Developer ID signed or
Apple notarized. Downloaded copies may be blocked by Gatekeeper. A DMG does
not remove that requirement. Use the trusted project release/source and
consult Apple's guidance: https://support.apple.com/en-us/102445

No observation data is included. Project code: MIT; CFITSIO retains its
own license in the app's Contents/Resources/THIRD_PARTY_NOTICES.txt.
TXT
# A compressed, read-only image; no installer scripts or system changes.
hdiutil create -volname "COSI Explorer $version" -srcfolder "$stage/volume" -fs HFS+ -format UDZO -ov "$stage/release.dmg"
hdiutil verify "$stage/release.dmg"
cp "$stage/release.dmg" "$image"
printf 'DMG: %s\n' "$image"
