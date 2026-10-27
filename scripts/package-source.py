#!/usr/bin/env python3
"""Create a source-only release from an explicit allowlist; never bundle user data."""
from pathlib import Path
import hashlib
import re
import shutil
import sys
import zipfile

source = Path(__file__).resolve().parents[1]
output = Path(sys.argv[1] if len(sys.argv) > 1 else source / 'dist').resolve()
output.mkdir(parents=True, exist_ok=True)
version = re.search(r'project\(COSIExplorer VERSION ([^ ]+)', (source / 'CMakeLists.txt').read_text())[1]
files = [source / name for name in (
    '.gitignore', 'AUTHORS.md', 'CMakeLists.txt', 'Info.plist', 'LICENSE', 'THIRD_PARTY_NOTICES.txt',
    'README.md', 'CHANGELOG.md', 'build.sh', 'release.sh')]
for folder in ('src', 'tests', 'docs', 'scripts', 'examples'):
    files.extend(path for path in (source / folder).rglob('*') if path.is_file() and path.suffix in ('.cpp', '.hpp', '.mm', '.md', '.sh', '.py'))
# Include only the reviewed public README artwork and synthetic-data preview.
files.extend(source / name for name in ('resources/README.md', 'resources/COSIExplorer.svg', 'resources/COSIExplorer.png', 'resources/COSIExplorer.icns', 'docs/assets/overview.png', 'docs/assets/banner.svg', 'docs/assets/demo.gif', 'examples/synthetic-events.fits', '.github/workflows/build.yml', 'resources/linux/cosi-explorer.desktop', 'docs/assets/linux.png'))
archive = output / f'COSI-Explorer-v{version}-source.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as bundle:
    for path in sorted(files):
        bundle.write(path, f'cosi-explorer-{version}/{path.relative_to(source)}')
artifacts = sorted(path for path in output.glob(f'COSI-Explorer-v{version}-*') if path.suffix in ('.zip', '.dmg', '.deb'))
# A separate demo asset lets binary users try the app without building sources.
demo = output / 'synthetic-events.fits'
shutil.copyfile(source / 'examples/synthetic-events.fits', demo)
artifacts.append(demo)
manifest = output / 'SHA256SUMS.txt'
manifest.write_text(''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n' for path in artifacts))
print(f'Source: {archive}\nChecksums: {manifest}')
