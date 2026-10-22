#!/usr/bin/env python3
"""Generate a custom-tap cask from a final, versioned arm64 DMG. Publishes nothing."""
import argparse
import hashlib
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--repo', required=True, help='GitHub OWNER/REPOSITORY hosting the public release')
parser.add_argument('--dmg', required=True, type=Path, help='Final DMG that will be uploaded unchanged')
parser.add_argument('--output', required=True, type=Path, help='Casks/cosi-explorer.rb in the custom tap')
args = parser.parse_args()
if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repo):
    parser.error('--repo must be OWNER/REPOSITORY')
match = re.fullmatch(r'COSI-Explorer-v(\d+\.\d+\.\d+)-macos-arm64\.dmg', args.dmg.name)
if not match or not args.dmg.is_file():
    parser.error('--dmg must name an existing versioned macos-arm64 DMG')
version = match[1]
checksum = hashlib.sha256(args.dmg.read_bytes()).hexdigest()
homepage = f'https://github.com/{args.repo}'
cask = '''cask "cosi-explorer" do
  version "VERSION"
  sha256 "CHECKSUM"

  url "HOMEPAGE/releases/download/v#{version}/COSI-Explorer-v#{version}-macos-arm64.dmg"
  name "COSI Explorer"
  desc "Read-only viewer for FITS and supported COSI packet data"
  homepage "HOMEPAGE"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "COSI Explorer.app"
end
'''.replace('VERSION', version).replace('CHECKSUM', checksum).replace('HOMEPAGE', homepage)
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(cask)
print(f'Cask: {args.output}\nSHA-256: {checksum}\nPublish the unchanged DMG to {homepage}/releases/tag/v{version} before installing.')
