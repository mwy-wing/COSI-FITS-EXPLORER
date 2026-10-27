# User guide

[← COSI Explorer](../README.md)

## Platforms

Downloads cover Apple Silicon / macOS 15+ and x86_64 Ubuntu 22.04 or 24.04. Choose the `.deb` matching your Ubuntu version; Qt/CFITSIO dependencies differ between releases. Install with `sudo apt install ./COSI-Explorer-*.deb` (one matching file), then run `cosi-explorer` or use the application menu. Remove with `sudo apt remove cosi-explorer`. Other Linux distributions can build from source; they are not validated binary targets.

The Linux Qt app supports all four plot modes, array reduction, class/quality/value/time filters, original-row paging/jumps, Plotted rows, point selection, rectangle/wheel zoom, Back/Reset, summaries, PNG/PDF/CSV, headers, images, spectrum comparisons, stored hit coordinates, and conservative trace reports. Linux hit coordinates/trace reports are text views. The Mac app additionally offers the folder library, geometry projections, interactive trace stage navigation, pan mode, and fuller workspace restoration. On Linux the last file and window geometry are restored; plot settings start at defaults. `--no-restore` skips that state for a session, and `cosi-explorer FILE` opens a specific file.

## Open and inspect

Open a FITS or supported COSI packet file, or drop one onto the window. On Mac, choose a data folder for the library; search filters the catalog by filename/path and FITS / L0 / All narrows the file types. Use the HDU menu to choose a table or image extension.

- **Explore:** plot data and browse the paged table. **All rows** shows the source table; **Plotted rows** shows unique rows contributing to the applied plot. Row numbers stay original and 1-based. **Row # / Go** jumps to an original source row; in Plotted rows it must belong to the applied plot.
- **Header:** original FITS cards plus separately labeled viewer notes; packet files show framing/decoder information.
- **Hit geometry:** selected-event X/Y, X/Z, Y/Z projections. Connections require a valid `SEQHIT` permutation. Raw electronics IDs are not detector positions.
- **Trace event:** inspect related processing-stage records and their match/candidate status.

On Mac the inspector has **Plot**, **Selection**, and **Summary** tabs; Linux uses the controls at left and **Row detail**, **Summary**, **Header**, and **Event tools** tabs below the plot. The toolbar opens files, compares spectra, exports plots, and toggles the library/inspector. Choose a table row to inspect all fields, including complete hit arrays.

## Plot and filter

Column, chart type, reduction, class, and quality selections update automatically. After editing numeric ranges or bin counts, click **Apply to plot** or press ⌘Return on Mac / Ctrl+Return on Linux. Blank limits are unbounded; value/time bounds are inclusive and use stored units. Class/quality controls are enabled only when supported columns exist.

| Chart type | What it shows |
| --- | --- |
| Column values | Selected Y values against stored time or original row number. Row number is used when no supported time column exists. |
| Histogram | Selected values per bin. ENERGY with All elements shows active interaction energies; Sum row / hits shows total deposited energy per event. |
| Event counts vs time | One count per row when at least one reduced gate value passes the cuts. Choose a scalar gate such as TIME or EVENTID to include rows irrespective of hit multiplicity. Counts have no exposure correction. |
| Column comparison | Selected reduction on X and the first stored element on Y. This is not paired per-hit correlation. |

Use **Reset filters** to clear value/time ranges, class, and quality cuts in one step while keeping the chart and columns. Controls for unrelated chart modes and unsupported class/quality fields are hidden. The Linux settings sidebar scrolls in smaller windows.

**All elements**, **First element**, and **Sum row / hits** control array reduction. Recognized hit fields honor NUMHIT/NUMSTRIPHIT, excluding padded slots. Empty active arrays or non-finite active inputs contribute no sum. PHA/TAC remain uncalibrated channels. Value filters act on the selected column after reduction; in Column values this is Y.

- **Inspect:** hover near a displayed point for its values/source row, or click to reveal that row and all fields. Aggregate-bin hover shows the bin interval/counts, without assigning an individual event.
On Linux, drag a rectangle to zoom, scroll to zoom X, click a point to select its source row, or double-click to reset. The following additional gestures describe the Mac interface:

- **Pan:** drag the X range without selecting a row. Inspect also supports dragging to pan.
- **Box zoom:** drag a rectangle to zoom both axes; Shift-drag is the shortcut. Scroll zooms X around the pointer.
- **Back** (⌘[) returns to a previous view. **Reset** (⌘0 or double-click) fits the full plot. Escape cancels a drag. New plot data/settings clear zoom history.

Log Y displays histogram values as log10(1+y). Zooming and display thinning do not change Plotted rows or statistics. Amber rings mark visible points belonging to the selected row.

## Summary and export

**Summary** shows minimum, maximum, median, mean, collected values, and contributing rows for the applied column, before binning/thinning. Column comparison summarizes X from accepted pairs. Event-count plots summarize the first accepted gate value per counted event. Overlays summarize source A's original values, independently of count normalization or logarithmic display.

Non-finite items and empty rows are counted after class/quality/time cuts and before value gating. A sum containing a non-finite active input counts as one invalid reduced value; no active values counts as an empty row. Invalid hit-count rows are separate. No accepted values produces unavailable statistics, rather than zero. **Copy summary** includes full plotted precision, units, source, settings, and limits. Calculations use double precision; the table/Selection inspector preserve exact integer identifiers.

On Linux, Summary also has statistic cards and **Copy summary**, with full precision and units. An amber ring marks the selected row’s displayed points.

Use **Export plot** for PNG, PDF, or CSV. Figures include axes/units, sources, applied filters, visible X/Y ranges, scan limits, and overlay normalization. PNG is 2× resolution; PDF retains searchable text/vector drawing. Hover cards, selection rings, zoom rectangles, and UI controls are excluded. The figure is captured before the Save panel opens. CSV retains collected plot values, not a raw-table export; histograms export bin centers/counts.

## Compare spectra

Open source A, choose Histogram and its column/reduction, then **Overlay file…** for B. Select B's HDU when necessary. Both spectra use shared bin edges and matching declared column units; mismatches are rejected rather than converted. Time-gated comparisons also require compatible declared time references. **Unit area** normalizes counts for shape comparison; it does not correct exposure. A is teal and B is orange. Clear removes the overlay.

## Trace an event

Select a FITS event row, open **Trace event**, and click a stage card for its record and match context. **Open stage row** navigates to that record. **Choose L0…** supplies a raw stream explicitly.

Discovery searches immediate L1a/L1b/L2/L0 sibling folders within the selected run and matching filename stems. It does not infer observation identity from file dates. Custom directory layouts may need manual file selection.

Confirmed FITS links require a unique exact EVENTID, matching OBS_ID/TELESCOP/INSTRUME and declared time system/unit/reference, plus stored TIME matching within one microsecond in seconds. Missing metadata, repeated IDs, or inconsistent times produce candidates or withheld links.

L0 has no EVENTID. A row-order candidate requires one matched L1a product, equal row/packet counts, standalone GeD packets, and comparison of nonempty PHA/TAC arrays. Agreement remains a candidate; it does not prove event identity, convert epochs, or map electronics IDs to strips.

## Data scope and reopening

Files are opened read-only. Values preserve declared units and time reference; the app applies no calibration, reconstruction, clock/attitude correction, exposure correction, or sky localization. This independent viewer is not endorsed by NASA or the COSI mission.

Plots scan at most two million source rows and collect at most five million values; partial results are labeled. Dense point displays retain at most 50,000 points in the visible region, while CSV retains collected values. Hover identifies displayed points within 12 screen points. Packet indexing rejects streams above five million packets. FITS images show the first plane, limited to 16 million pixels.

On Mac, reopening restores the last file/HDU, applied settings, X/Y view, table choice, window layout, and panel visibility. Missing/incompatible files/settings fall back to defaults. Comparisons must be reopened separately. Preferences stay local; `--no-restore` skips restoring/saving the workspace for that session.

## Build, tests, and releases

See the [README](../README.md) for dependencies and `bash build.sh`. The Linux GUI requires Qt 6.2+ Widgets/Concurrent and CFITSIO; `bash build.sh` also creates a dependency-tracked `.deb` using CPack/dpkg-shlibdeps. A reader-only build can use `-DCOSI_BUILD_GUI=OFF`. The Mac download requires Apple Silicon and macOS 15+; it is ad-hoc signed and not Apple-notarized. No Homebrew tap or in-app updater is published.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j4
ctest --test-dir build --output-on-failure
bash tests/check-plot-tools.sh "dist/COSI Explorer.app"
```

The three reader/workflow CTest suites, Linux GUI suite, and Mac GUI regression use synthetic fixtures. Linux GUI tests run with the offscreen Qt backend; CI also exercises X11 under Xvfb on Ubuntu 22.04 and 24.04, installs each package, and smoke-tests its launcher. The GUI check requires a logged-in macOS session. Reader/plot changes should preserve units, exact table IDs, scan limits, and conservative provenance checks. Report bugs through [GitHub Issues](https://github.com/mwy-wing/COSI-FITS-EXPLORER/issues), with version/platform, expected behavior, and a shareable reproduction.

For a release, update CMakeLists.txt/Info.plist and the changelog, increase the bundle build number, and run `bash release.sh`. Verify checksums and the packaged app, build each Linux package on its named Ubuntu release, then attach the DMG, app/source ZIPs, Linux `.deb` files, demo, and SHA256SUMS.txt to a GitHub Release at the matching tested tag. Preserve existing release tags/assets. Signing can use `COSI_SIGN_IDENTITY`; Developer ID signing and [Apple notarization](https://developer.apple.com/developer-id/) are separate steps from creating a DMG.

[Demo data and generator](../examples/README.md) · [Icon source and renderer](../resources/README.md) · [Release history](https://github.com/mwy-wing/COSI-FITS-EXPLORER/releases)
