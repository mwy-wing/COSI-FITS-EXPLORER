# Releasing COSI Explorer v0.1.0

The first public release is v0.1.0. Earlier prototype labels were local iterations. This folder is the repository root; it contains source, MIT licensing, CFITSIO notices, tests, and build/release scripts. The repository owner's existing MIT copyright notice names WingYeung Ma. Equal project credit with ChatGPT is documented in AUTHORS.md.

## Create the local release

On an Apple Silicon Mac with Xcode Command Line Tools, CMake, pkg-config, CFITSIO, and Python 3:

```sh
bash release.sh
```

This runs both CTest suites and creates:

- `dist/COSI Explorer.app`
- `dist/COSI-Explorer-v0.1.0-macos-arm64.zip`
- `dist/COSI-Explorer-v0.1.0-macos-arm64.dmg` (app, Applications link, install instructions)
- `dist/COSI-Explorer-v0.1.0-source.zip`
- `dist/SHA256SUMS.txt`

To verify, run `cd dist`, then `shasum -a 256 -c SHA256SUMS.txt`. The manifest records filenames relative to the asset directory.

The binary bundles CFITSIO and its notice. Only macOS system libraries remain external. Packaging stops if CFITSIO introduces another non-system dependency that the script does not bundle. The source archive uses an explicit allowlist and excludes mission files, local screenshots, build trees, certificates, and Git metadata. Local screenshots stay ignored in the development folder.

The release targets macOS 15+. The bundled CFITSIO here has a macOS 15 deployment target, so changing only the app's minimum version cannot make this binary run on older systems. Intel binaries need a native Intel CFITSIO/build and separate testing; a universal app needs compatible arm64 and x86_64 dependencies. An arm64 ZIP is not an Intel or Windows release.

## Open-source repository and release

1. The source repository is `mwy-wing/COSI-FITS-EXPLORER`. Keep its existing MIT license and history when preparing future changes.
2. Upload the contents of the source archive, or initialize Git in this source folder. Review `git status` before adding files; generated data, screenshots, build output, and archives are ignored.
3. Commit the source, tag the commit `v0.1.0`, and push it to your repository.
4. On GitHub, open **Releases → Draft a new release**, select `v0.1.0`, paste the notes from `docs/RELEASE_NOTES_v0.1.0.md`, and attach the DMG, binary ZIP, and checksum file. The source ZIP is also available if you want to attach it; GitHub generates tagged source archives automatically.
5. Preview the draft and publish it when the source, platform requirements, and signing status are correct.

For a fresh checkout of the source repository:

```sh
git clone git@github.com:mwy-wing/COSI-FITS-EXPLORER.git
cd COSI-FITS-EXPLORER
bash release.sh
```

Keep future release tags on the corresponding tested source commit, and never overwrite a published version tag. Push new commits and the new version tag before attaching release assets.

The packaging scripts do not create or push repositories/tags, upload assets, or publish releases. [GitHub's release documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) describes tagged releases and attached binaries.

## Developer ID signing and notarization

The default `-` identity makes a local ad-hoc signature. It is not a Developer ID signature and does not make a downloaded app pass Gatekeeper. For wider binary distribution, use your Apple Developer Program membership and Developer ID Application certificate, then submit the app to Apple's notary service. Certificate creation and credentials remain in your Apple account/Keychain.

The build script supports a signing identity and enables hardened runtime/timestamping for it:

```sh
COSI_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' bash release.sh
```

After setting up a notarytool Keychain profile named COSI_NOTARY, submit the ZIP:

```sh
xcrun notarytool submit dist/COSI-Explorer-v0.1.0-macos-arm64.zip --keychain-profile COSI_NOTARY --wait
```

Only after Apple returns Accepted, staple and verify the ticket, recreate the ZIP from the stapled app, and regenerate checksums:

```sh
xcrun stapler staple "dist/COSI Explorer.app"
xcrun stapler validate "dist/COSI Explorer.app"
codesign --verify --deep --strict "dist/COSI Explorer.app"
spctl --assess --type execute --verbose "dist/COSI Explorer.app"
ditto --norsrc --noextattr -c -k --keepParent "dist/COSI Explorer.app" dist/COSI-Explorer-v0.1.0-macos-arm64.zip
bash scripts/create-dmg.sh dist
python3 scripts/package-source.py dist
```

Test the downloaded release on a separate Mac before describing it as a generally tested download. The Developer ID and notarization branch is documented but has not been executed for this local release. [Apple's Developer ID guide](https://developer.apple.com/developer-id/) explains certificates, hardened runtime, notarytool, and stapling.

## Future releases

Update the version in CMakeLists.txt and Info.plist, increase CFBundleVersion, update the changelog/notes, run the C++ suites and relevant GUI checks, then create the matching tag. For 0.x releases, document any incompatible data interpretation or workflow changes explicitly.

## Homebrew and desktop downloads

The DMG is the primary desktop download: open it, drag the app to Applications, then eject the image. It contains no installer scripts. The image is compressed and read-only. A disk image does not provide a trusted Developer ID signature or notarization by itself.

For a future `brew install --cask` route, publish the final DMG and a custom tap as described in [HOMEBREW.md](HOMEBREW.md). Rebuild the DMG from the stapled app ZIP after notarization, regenerate checksums, and generate the cask from that final DMG. The application repository URL is configured; the custom Homebrew tap and binary release assets still need publication.
