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

## Application logo

The generated RGBA logo was preserved unchanged. Standard/Retina icon derivatives were assembled with macOS iconutil; the ICNS container contains all expected sizes through 1024 pixels. CMake builds and packages the icon in Resources, and the built Info.plist selects it. The local app was rebuilt and all three CTest suites passed. A clean extraction of its ZIP passed strict signature verification. Both PNG and ICNS are in the source allowlist. The published v0.1.0 assets were not replaced.

## v0.1.1 plot tools

Core fixture tests check point-to-source provenance through hit expansion, reductions, value/time filters, and missing time columns. All three CTest suites pass.

`bash tests/check-plot-tools.sh /path/to/COSI-Explorer.app result-directory` requires a logged-in macOS GUI session and uses only the public synthetic FITS example. It dispatches a native mouse-move event to a displayed point, verifies row/time/value readouts, exports linear time and filtered-row plots plus logarithmic/raw and normalized overlays, and verifies histogram readouts. It uses a unique preferences suite, restarts the app to verify file/HDU/controls/viewport/window/panel restoration, and removes its fixture and test preference domain afterward. App-generated notes are checked separately from the original header text.

Exported PNGs were visually reviewed. PDFKit confirmed one page per PDF with searchable plot labels, source filename, units, applied filters, visible range, log display, and overlay normalization. A native bitmap check verifies 2400-pixel PNG width and pale histogram fills. The PDF renderer uses opaque pale gradient stops so PDF shading matches the on-screen chart. These checks do not certify physical interpretation of mission time or calibration.

The final packaged v0.1.1 app passed the synthetic native regression, including an independent expected viewport/window frame on a second launch. The bundled app ZIP was extracted into a clean temporary directory and passed strict signature verification; it reports 0.1.1 and contains the new Dock icon. Figure serialization and file writes were exercised automatically; native Save-panel clicking was not completed because the computer-use session reported that the foreground application had changed. The Save-panel handlers and captured-output/protected-source paths were reviewed in source. Public v0.1.0 release assets were left intact.


## Point selection and rectangle zoom — 2026-10-26

The public synthetic native regression now dispatches mouse-down/drag/up events to the application's canvas. It checks original-row selection across table pages, latest-click ordering when a pending request is superseded by an existing page, filtered-row provenance, and rejection of busy/outside/bin clicks. Native target/action checks cover Inspect/Pan/Box zoom and Back/Reset. Rectangle checks cover both axes, reversed drags, Shift-drag, chart-edge clamping, tiny rectangles, cancellation, and the inverse logarithmic Y transform. The shared wheel-zoom handler is checked for pointer anchoring, rapid-step history grouping, unchanged Y bounds, and rejection outside the chart.

The minimum 1150 × 780 window layout is rendered and checked for separation between the new controls, table, and paging buttons. A second isolated launch checks independent expected X and Y bounds. Exported PDFs must now include searchable visible Y ranges as well as X ranges. Navigation history clears for new plot data; selected-row rings and transient rectangles remain excluded from figure snapshots. All fixtures are synthetic and test preferences are isolated from the user's saved workspace.


## Plotted-row tables — 2026-10-26

Core tests check unique contributing rows through active-hit expansion, reduction, value/time/quality filters, null values, empty selections, and partial scans. Sparse FITS/packet reads retain source numbers and exact integer cell values, reject invalid requested rows, and handle empty/end pages. The synthetic demo checks noncontiguous class-filtered pages and consistent contributors in aggregate plots.

The native public-fixture regression switches between All rows and Plotted rows, pages through 900 filtered source rows, checks a displayed original row number, jumps to source row 1000, and clicks a plotted point into its corresponding filtered page. It checks latest-request ordering during table-mode changes, combined filters, clearing selection/geometry/trace on empty results, recovery through All rows, histogram and source-A overlay row counts, event-count contributors, and the table choice on a separate launch. Existing zoom, hover, figure-export, and workspace checks remain included. Native previews were visually inspected for table mode/count labels and the empty-result state. No mission files are used.


## Column summaries and vector icon — 2026-10-26

Fixture tests cover odd/even medians, means/ranges, finite zeros, null/infinite inputs, overflow-safe means, empty statistics, active-hit clipping, reductions, invalid hit-count rows, partial scans, and light-curve gate values rather than timestamps. Computing a summary preserves the original point order. The native public-fixture harness checks an independently sorted median/range, the Summary tab, full-precision text with units/settings, combined filters, unavailable empty statistics, source-A normalized overlays, and event-count gate summaries. It builds summary copy text without changing the user's clipboard. The existing paging/selection, plot navigation, figure exports, and restart checks remain included.

The replacement icon is original geometric SVG/native drawing, not generated raster imagery. Its renderer shares coordinates between SVG and PNG and renders all ten standard/Retina representations before iconutil builds the ICNS. The master and 32-pixel version were visually inspected, along with the actual Summary inspector. The app uses the packaged ICNS for both its Dock icon and library glyph; bundle build number is 8. The README banner follows the same flat palette and mark. Icon sources and regeneration scripts are included in the source archive; published v0.1.0 assets remain unchanged.
