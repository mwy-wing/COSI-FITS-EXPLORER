#!/bin/bash
# Build on Ubuntu 22.04 for the published amd64 package's minimum runtime.
set -euo pipefail
source_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${1:-$source_dir/build}"
output_dir="${2:-$source_dir/dist}"
if [[ "$(uname -s)" != Linux ]]; then
  printf 'Linux packaging requires a Linux build environment.\n' >&2
  exit 1
fi
if [[ ! -x "$build_dir/cosi-explorer" ]]; then
  printf 'Build the Qt graphical app before packaging.\n' >&2
  exit 1
fi
version="$(sed -n 's/^project(COSIExplorer VERSION \([^ ]*\).*/\1/p' "$source_dir/CMakeLists.txt")"
architecture="$(dpkg --print-architecture)"
# CFITSIO/Qt package names can change between Ubuntu releases; label each build.
. /etc/os-release
flavor="${ID}-${VERSION_ID}"
mkdir -p "$output_dir"
cpack --config "$build_dir/CPackConfig.cmake" -B "$build_dir/packages"
package="$build_dir/packages/cosi-explorer_${version}_${architecture}.deb"
target="$output_dir/COSI-Explorer-v${version}-linux-${flavor}-${architecture}.deb"
cp "$package" "$target"
dpkg-deb --info "$target"
printf 'Linux graphical app: %s\n' "$target"
