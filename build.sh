#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${1:-$source_dir/build}"
output_dir="${2:-$source_dir/dist}"
version="$(sed -n 's/^project(COSIExplorer VERSION \([^ ]*\).*/\1/p' "$source_dir/CMakeLists.txt")"
cmake_args=(-S "$source_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release)
if [[ "$(uname -s)" == Darwin ]]; then
  cmake_args+=(-DCMAKE_OSX_DEPLOYMENT_TARGET="${COSI_MACOS_DEPLOYMENT_TARGET:-15.0}")
fi
cmake "${cmake_args[@]}"
cmake --build "$build_dir" -j "${COSI_BUILD_JOBS:-4}"
ctest --test-dir "$build_dir" --output-on-failure
if [[ "$(uname -s)" != Darwin ]]; then
  bash "$source_dir/scripts/package-linux.sh" "$build_dir" "$output_dir"
  exit 0
fi
mkdir -p "$output_dir"
package_dir="$(mktemp -d "${TMPDIR:-/tmp}/cosi-explorer-package.XXXXXX")"
trap 'rm -rf "$package_dir"' EXIT
app="$package_dir/COSI Explorer.app"
# Sign in a temporary directory to avoid cloud/Finder metadata during signing.
ditto --norsrc --noextattr "$build_dir/COSIExplorer.app" "$app"
mkdir -p "$app/Contents/Frameworks" "$app/Contents/Resources"
dependency="$(otool -L "$app/Contents/MacOS/COSIExplorer" | awk '/libcfitsio/{print $1; exit}')"
if [[ ! -f "$dependency" ]]; then
  printf 'Cannot resolve CFITSIO dependency: %s\n' "$dependency" >&2
  exit 1
fi
# Reject unbundled non-system dependencies instead of shipping a broken app.
while IFS= read -r linked; do
  case "$linked" in /usr/lib/*|/System/Library/*|*libcfitsio*) ;;
    *) printf 'CFITSIO has an additional dependency that must be bundled: %s\n' "$linked" >&2; exit 1 ;;
  esac
done < <(otool -L "$dependency" | awk 'NR>1 {print $1}')
lib_name="$(basename "$dependency")"
cp -L "$dependency" "$app/Contents/Frameworks/$lib_name"
chmod u+w "$app/Contents/Frameworks/$lib_name"
install_name_tool -id "@executable_path/../Frameworks/$lib_name" "$app/Contents/Frameworks/$lib_name"
install_name_tool -change "$dependency" "@executable_path/../Frameworks/$lib_name" "$app/Contents/MacOS/COSIExplorer"
cp "$source_dir/THIRD_PARTY_NOTICES.txt" "$source_dir/LICENSE" "$app/Contents/Resources/"
for attribute in com.apple.FinderInfo com.apple.ResourceFork; do
  xattr -dr "$attribute" "$app" 2>/dev/null || true
  xattr -d "$attribute" "$app" 2>/dev/null || true
done
identity="${COSI_SIGN_IDENTITY:--}"
sign_args=(--force --sign "$identity")
if [[ "$identity" != '-' ]]; then sign_args+=(--options runtime --timestamp); fi
codesign "${sign_args[@]}" "$app/Contents/Frameworks/$lib_name"
codesign "${sign_args[@]}" "$app"
codesign --verify --deep --strict "$app"
ditto --norsrc --noextattr "$app" "$output_dir/COSI Explorer.app"
archive="$output_dir/COSI-Explorer-v$version-macos-$(uname -m).zip"
ditto --norsrc --noextattr -c -k --keepParent "$app" "$archive"
xattr -d com.apple.FinderInfo "$output_dir/COSI Explorer.app" 2>/dev/null || true
printf 'Built: %s\nArchive: %s\n' "$output_dir/COSI Explorer.app" "$archive"
