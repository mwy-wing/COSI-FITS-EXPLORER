# Validation for v0.1.0

This is the first public release. Earlier local prototype labels do not represent published releases.

## Reproducible checks

Run `bash build.sh` or configure/build with CMake, then run CTest. The two C++ suites generate their own small FITS and packet fixtures in a temporary directory; no mission files, network access, or private directory layout are needed.

Checks cover packet framing and malformed input, hit bit decoding, unknown APID handling, FITS scalar/vector/bit/logical/null data, exact integer display, image pixels, active-hit clipping, histogram conservation, filters, time/row versus column-value pairs, event-identity matching and rejection, common-bin overlays, normalization, and CSV provenance.

The optional native GUI regression in `tests/check-column-updates.sh` requires a macOS GUI session and an external COSI-SDC development dataset. It drives popup target/action events, checks default Time/Y values, switches Time/Row axes and Y columns, and exercises rapid changes. Its dataset is not included or required for building or running the C++ suites.

## Scope

The desktop app and bundled CFITSIO have been built and tested on Apple Silicon. Intel builds and Linux command-line builds are supported by the source layout but have not been run in this release preparation. Windows is untested. The desktop interface requires macOS; a portable C++ core is not a cross-platform GUI.

The binary is locally ad-hoc signed, not Apple Developer ID signed or notarized. See `docs/RELEASING.md` before general binary distribution. Local validation does not certify calibration, reconstruction, time correction, attitude alignment, exposure, or mission-wide packet-schema compliance.

## Release preparation checks

The v0.1.0 source ZIP was extracted into a separate directory and built with its default `build.sh` paths. Both CTest suites passed and a standalone app/ZIP was produced there. The release binary ZIP was separately extracted outside cloud-synced folders and passed strict deep signature verification. Its executable reports arm64 and a macOS 15 deployment target; CFITSIO is bundled and remaining executable dependencies are system frameworks/libraries. Both distributed ZIPs passed their SHA-256 manifest checks. The versioned app passed the extended native plot/axis regression.

Finder/iCloud can attach metadata to a live `.app` in Documents after packaging; the ZIP is produced from a signed temporary staging directory and is the verified distribution artifact. Signature verification of the freshly extracted ZIP is the relevant package check.

A native first-launch check with no configured data root showed an empty library and “Choose a data folder, or open a file.” No hard-coded home-directory data path was accessed.

## Desktop installer and Homebrew preparation

The v0.1.0 compressed read-only DMG passed `hdiutil verify`. It was mounted read-only without opening Finder; the mounted volume contained COSI Explorer.app, an Applications symlink pointing to /Applications, and INSTALL.txt. The mounted app reported version 0.1.0 and passed strict deep local signature verification. The verification mount was ejected afterward. No app installation into /Applications was performed.

The custom-tap cask generator produced a Ruby-syntax-valid draft with the real DMG SHA-256, arm64 requirement, macOS Sequoia (15) minimum, and correct app bundle name. The GitHub owner is an explicit placeholder. No public tap, Homebrew installation, Developer ID signing, or notarization has been performed. The source archive includes the DMG builder, cask generator, and publication instructions; the checksum manifest covers DMG and ZIP assets.

## README imagery

The README screenshot is rendered from the native app with generated synthetic events and a neutral temporary directory. The image was visually reviewed for legibility and absence of personal paths or observation data. The source packager includes only this reviewed PNG and the original vector banner; local development screenshots remain excluded.

## Public demo and automated build setup — 2026-10-22

- All three local CTest suites passed, including a public-demo test for time/row axes, original row preservation after class filtering, finite energies, and selected-event histogram totals.
- A fresh build from the updated source ZIP also passed all three suites. Its explicit allowlist includes only the reviewed synthetic FITS example, generator, tests, workflow, and documented public artwork.
- The generator rejected an existing output file; its SHA-256 remained unchanged.
- The original v0.1.0 source ZIP matches the existing published tag file-for-file. It is retained for release; the demo is a separate supplemental asset.
- The release DMG passed hdiutil verification, all four release assets matched the checksum manifest, and a clean extraction of the app ZIP passed strict codesign verification. The signature is ad-hoc, not Developer ID or notarization.
- GitHub CI builds the macOS app and Linux core/CLI, runs the three suites, and checks demo generation/overwrite protection. CI does not automate the desktop GUI or publish signed binaries.

The v0.1.0 release was published on GitHub. All five public asset downloads (DMG, app ZIP, original tagged source ZIP, checksum manifest, and supplemental demo) were downloaded without authentication and matched their local SHA-256 values. The uploaded asset digests also matched.

The README animation contains three native view captures: Time, Row number, and Histogram. The capture harness checked 1,200 values and the expected axis endpoints before saving; the histogram accepted all 1,200 rows. GIF metadata confirms three 1320 × 900 frames at 2.5 seconds each. The source captures were visually reviewed. Only the encoded public GIF is included in the source allowlist.
