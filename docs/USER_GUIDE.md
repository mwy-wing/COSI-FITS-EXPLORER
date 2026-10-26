# User guide

[← COSI Explorer](../README.md)

## The workspace

The toolbar provides Open, Compare spectra, Export CSV, and library/inspector toggles. The file header summarizes the selected product, row/event/packet count, field count, and file size.

In **Explore**, the right inspector has two tabs: **Plot settings** contains plot controls, filters, and comparison-file controls (scroll for additional settings); **Selection** contains the selected event's full fields or the comparison report. **Apply to plot** is fixed at the bottom of the settings inspector. Column, chart-type, array-reduction, event-class, and quality selections update the plot automatically. Use Apply to plot or Command-Return after editing bins or numeric ranges; Command-0 resets plot zoom. The View menu can hide the library or inspector to give plots and tables more room.

In **Trace event**, click a processing-stage card to inspect that stage's record and match context, then use **Open stage row** to navigate. The cards retain distinct matched, candidate, missing-event, and selected-source states. Full field values remain selectable text below the cards.

## Explore your data

- The catalog searches relative paths as well as filenames. Its FITS / L0 / All buttons narrow the list. Select a file to open it. Use Choose folder again to refresh an updated directory.
- Select an HDU from the popup to inspect event tables, telemetry tables, spacecraft attitude/orbit tables, or an image plane.
- **Explore** combines a plot with a paged, horizontally scrollable table. The table always displays **raw, unfiltered rows**. Arrow buttons change pages; **Row # / Go** jumps to a 1-based row. Select a row for all column values in the inspector.
- **Header** shows the selected HDU's FITS cards, including units and time-reference metadata. For L0 it shows framing, APID counts, sequence jumps, and decoder notes.
- **Hit geometry** shows X/Y, X/Z, Y/Z projections for the selected calibrated event. Choose the event in Explore first. Connections appear only when `SEQHIT` is a valid 1…NUMHIT permutation. Raw readout IDs are not interpreted as positions.

### Plots

Choose a numeric column and array reduction; these selections update automatically. Edit optional numeric ranges or histogram bins, then click **Apply to plot**. Blank limits are unbounded. Value and time limits are inclusive and use the stored column units. The EVENTCLASS and Clean only controls activate only when their corresponding columns exist.

- **Column values (default):** choose **X axis → Time** or **Row number (1, 2, 3…)**, then choose a **Y column**. Each point uses a source value, without histogram binning. Time retains its stored units and reference; no epoch or clock correction is applied. Row numbers are the original 1-based table positions, retained after filters. When there is no supported time column, Row number is selected automatically and Time is unavailable. **All elements** plots each active array value at its source row/time; **First element** or **Sum row / hits** gives one reduced Y value per valid row. Value filters act on Y.
- **Histogram / All elements:** one entry per finite array element. Recognized hit fields honor NUMHIT/NUMSTRIPHIT so padded storage slots do not contribute. Select ENERGY to inspect individual interaction energies; PHA/TAC remain uncalibrated channels.
- **Histogram / Sum row / hits:** sum each row's active values. For ENERGY this gives total deposited event energy. A row with zero active hits or nonfinite active values contributes no sum.
- **Event counts vs time:** use TIME (or TimeTags / GeD GPS_SECONDS) as the horizontal axis. The selected X column acts as a value gate. A row contributes **one** count if at least one reduced value passes the gate. To count all rows irrespective of hit multiplicity, select a scalar column such as TIME or EVENTID as the gate. Counts are per time bin, without live-time/exposure correction.
- **Column comparison:** selected reduction on X, first stored element on Y. This is an explicitly labeled column comparison, not paired per-hit correlation. Select X/Y/Z columns with First element for first-hit coordinate comparisons.

Scroll over the plot to zoom X, drag to pan, and double-click to reset. **Log Y** changes the histogram display to log10(1+count). Export plot CSV writes linear plotted values, bin centers for histograms, source path, HDU, filters, reduction, and scan counts. It does not export the raw table.

### Trace an event through the pipeline

1. Open an L1a, L1b, or L2 FITS product, select a row in Explore, and choose **Trace event**.
2. Read the pipeline summary: related L1a/L1b/L2 files show their matching row, multiplicity, event class, total active energy where available, and quality flags. Missing events and ambiguous IDs are explicit.
3. Select a stage in the popup and click **Open stage row** to navigate to that product and event. This works for L0 candidates too, with the candidate status retained in the trace report.
4. Use **Choose L0…** to inspect an explicitly selected raw stream when it is not available as a sibling product.

Automatic discovery is intentionally local: it searches immediate L1a/L1b/L2/L0 sibling folders under the selected run, and requires the same filename stem after removing the processing-level suffix. It does not silently borrow a product from a different run. Several compatible filename variants are listed separately. Custom layouts without these sibling folders can still inspect the selected source, but need a future explicit product-bundle selector for additional FITS links.

Cross-file FITS links require a unique exact integer/string EVENTID, matching OBS_ID, TELESCOP, INSTRUME, declared time system/unit/reference, and matching stored TIME within one microsecond. The TIME column must use seconds. Missing metadata, repeated IDs, and inconsistent times produce candidates or withheld links rather than assumed matches. The selected source row is identified separately. File dates do not establish observation dates.

L0 packets have no EVENTID. If there is exactly one matched L1a product and the L0 packet count equals the L1a row count, the viewer can show the packet at the L1a row position. It requires standalone GeD packets and compares nonempty PHA/TAC arrays. **This remains a row-order candidate even when the arrays agree**: it does not establish source provenance, apply an epoch conversion, or map electronics IDs to strip positions. Start a trace from a FITS event table.

For a concrete example, open `26/10/06/v1/L1b/cs20260630ged_00_l1b.fits`, select row 1, and choose Trace event. EVENTID 1 has L1a strip data, an L1b strip-pairing quality flag, and no corresponding L2 row. The report displays that evidence without claiming that absence alone proves a particular screening decision. The canonical L0 example can be chosen from `26/06/10/v1/L0/STTC_HP52542_Cs137_100k_l0.bin`.

### Compare two spectra

1. Open reference file **A**, select Histogram, the numeric column, and reduction. For total deposited event energies choose ENERGY and **Sum row / hits**.
2. Click **Overlay file…** and choose comparison file **B**. The matching HDU name is selected when available; otherwise select the comparison HDU explicitly if several exist.
3. Both histograms use identical bin edges, the same reduction/cuts, and the same declared column units. A is teal; B is orange. Mismatched units are rejected rather than converted implicitly. Changing columns, reduction, or event selections recomputes both spectra automatically. Use Apply to plot after editing bins or numeric ranges.
4. Toggle **Unit area** for a shape comparison: each spectrum's bin values sum to one. Leave it off to compare raw counts. Neither mode applies exposure or background correction.
5. The right inspector shows source paths, HDUs, counts, means, mean difference, and effective settings. Selecting a table row replaces that inspector with the row's fields; Apply to plot restores the comparison summary.
6. **Export plot CSV…** saves the common bin centers, A, B, and B−A, along with both paths, HDUs, effective settings, and normalization. **Clear** returns to the single-file plot. Changing the reference file/HDU clears the previous overlay.

Time-gated overlays and TIME/TimeTags column overlays require comparable FITS event time-reference metadata. The viewer does not assume that matching energy units imply matching exposure, input event sets, or calibration. Table browsing continues to show raw rows from reference A only.

### Supported formats and scientific boundaries

- FITS binary/ASCII tables, scalar and vector numeric columns, strings, logical values, and fixed/variable bit arrays (including PX). Null/nonfinite values are identified. Full 64-bit integer identifiers remain exact in table text; plot coordinates use double precision.
- FITS images: a linear-color preview of the **first plane**, up to 16 million pixels. No WCS sky projection or image cube slicing.
- Bare CCSDS SPP streams and COSI 20-byte L0 file containers, with optional file CRC-16 trailer verification. Framing and declared packet counts are checked; malformed/truncated streams report an error. A CRC mismatch is labeled in the status.
- GeD APIDs 0x0DD, 0x0E2, 0x0E3: local Nuclearizer secondary/event headers and normal, neighbor, guard-ring, and type-3 bit-packed hits. PHA/TAC and electronics READOUT_ID are preserved. Other APID payloads are available as hex; no unverified timestamp/payload schema is assigned.
- Text `.dat` models, `.tra`, `.sim`, `.roa`, HDF5, and sync/CRC transport frames are outside this first version. A filename extension alone is not treated as proof of packet format.

The viewer does not apply calibration, strip maps, clock corrections, spacecraft attitude, event reconstruction, or sky localization. It preserves source timestamps and metadata. In particular, the October 6 run's documented TT-offset correction and the September test attitude's documented unit issue are **not silently repaired**. Test files retain their TEST filenames.

Table pages contain 250 rows. Plots scan at most two million source rows / five million plotted values; partial scans are explicitly marked. Point plots show at most 50,000 evenly selected points in the visible X range, while CSV export retains the collected points. Packet indexing stops with an explicit error above five million packets. There is no implicit random sampling.

## Build and verify

Requires CMake, pkg-config, CFITSIO development files, and Xcode Command Line Tools for the macOS interface. The automated C++ suites generate synthetic fixtures and need no mission dataset.

```sh
bash build.sh
```

The script builds, runs the core tests, and packages the app in `dist/` with CFITSIO included and an ad-hoc local signature. It does not install anything or modify your source data. The included CFITSIO has only macOS system-library dependencies; recheck this if rebuilding against a different installation.

The portable C++ reader and CLI can also be built separately:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j 4
ctest --test-dir build --output-on-failure
./build/cosi-inspect /absolute/path/example.fits --plot ENERGY
```

`src/Data.cpp` contains the reader and plotting logic. `src/App.mm` contains the macOS interface. `tests/core_tests.cpp` builds independent byte/FITS fixtures for meaningful decoding and scientific-count checks. See [VALIDATION.md](../VALIDATION.md) for reproducible checks and validation scope.

`src/Workflow.cpp` implements trace discovery, identity checks, shared-bin overlays, and comparison CSV output. `tests/workflow_tests.cpp` covers these workflows, including cases where an automatic match must be withheld. The CLI also supports:

```sh
./build/cosi-inspect /absolute/path/product.fits --trace 1
./build/cosi-inspect /absolute/path/reference.fits --compare /absolute/path/comparison.fits --normalize
```

The CLI comparison chooses the first table in each file and uses summed ENERGY when present, otherwise per-hit PHA. The desktop interface provides explicit HDU/column selection.

A native GUI regression drives the actual popup target/action events and checks rendered plot data against source values, including rapid changes and scatter Y selections:

```sh
bash tests/check-column-updates.sh "dist/COSI Explorer.app" /path/to/COSI-SDC/Data
```

Run it from this source folder in a macOS GUI session. It writes a pass/fail report and application-rendered preview to a temporary directory, or the optional third argument.

In Column values mode, CSV exports the actual time/row and Y-value pairs. The plot shows points in source order and may thin its display to 50,000 points; all collected pairs remain in the CSV. Histogram and Event counts vs time remain available under Chart type.

COSI Explorer is an independent viewer; no endorsement by NASA or the COSI mission is implied. Observation data, calibration files, and other mission software are not included or relicensed by the project.

## Homebrew

A custom-tap cask generator is included. A live `brew install --cask` command requires publishing the final DMG to a public release and publishing a tap under your real GitHub account; neither has been published yet. See [docs/HOMEBREW.md](HOMEBREW.md). Homebrew installs the same desktop app and does not replace Apple signing/notarization.

## Try it without mission files

Download the [synthetic demo](https://github.com/mwy-wing/COSI-FITS-EXPLORER/releases/download/v0.1.0/synthetic-events.fits) and open it with **Open file…**. Start with Column values, ENERGY, and Time; switch to Row number or Histogram. These invented values contain no observation data. See [the example notes](../examples/README.md) for its columns and generator.

## Plot tools in v0.1.1 (current source and local build)

Move the pointer near a displayed point to inspect X/Y at full plotted precision, its original 1-based row, and its stored time when available. Filters preserve source row numbers. For array columns, points retain their parent row after active-hit clipping and reduction. Hovering a histogram shows the bin interval, center, and plotted values/counts; an overlay adds B's value. The final bin includes the upper edge.

Choose **Inspect** above the plot and click a displayed point to select its original row in the event table and open the Selection inspector. The app loads the correct table page automatically. Selected rows have an amber ring on their visible points; table selection also updates the ring. Histogram and event-count bins describe aggregated values and do not select individual rows. Above the table, choose **All rows** for the full source table or **Plotted rows** for the unique source rows behind the applied plot. Each row appears once, including rows that contribute multiple hits. This works with column plots, histograms, and event-count plots; overlays show rows from source A. The Row column and **Row #** jump always use original 1-based source numbers. In Plotted rows, a jump must name a contributing row; switch to All rows to inspect excluded rows. Table paging counts positions within the chosen list.

Plotted rows follows the last successful plot's value/time/class/quality filters, array reduction, finite-value checks, and scan/collection limits. It includes collected values before the display's point thinning. Panning or zooming does not filter the table. Empty selections clear row/geometry/trace details and disable paging; All rows remains available.

Choose **Box zoom** and drag a rectangle to zoom both axes. **Shift-drag** does the same from Inspect or Pan. **Pan** drags the X range without selecting a row; Inspect also supports dragging to pan. Scroll to zoom X around the pointer. **Back** (⌘[) returns to the preceding view; **Reset** (⌘0 or double-click) fits all plotted values. A reset can be undone with Back. Press **Escape** to cancel a drag. New plot data/settings clear navigation history. On logarithmic plots, the rectangle follows the displayed logarithmic Y scale while labels and exports retain the original Y units.

Hover identifies displayed points within 12 screen points. Dense views retain the existing 50,000-point display limit; zoom in to inspect more of the collected points. Plot coordinates use double precision; the table and Selection inspector preserve exact integer identifiers.

Use the toolbar's **Export plot** button for PNG, PDF, or CSV, or **File → Export Plot PNG/PDF…**. Figures include axis labels/units, the original source path, applied filters/reduction, visible X/Y ranges, logarithmic display state, scan limits, and overlay normalization. PNG is rendered at 2× resolution; PDF retains searchable text and vector plot drawing. Hover cards, selection rings, zoom rectangles, toolbar buttons, and the data table are excluded. The figure is captured when export starts, before the Save panel opens. Figure export is available for Explore's table plots; CSV export keeps the collected plotted values.

On reopening, the app restores the last successfully loaded file/HDU, applied plot settings, X/Y viewport, All rows/Plotted rows table choice, window size/position, and library/inspector visibility. Source files are reopened read-only. Missing files or incompatible stored settings fall back to the usual empty/default view. Comparisons must be reopened separately. Settings are saved locally through macOS preferences; launch with `--no-restore` to skip workspace restoration and saving for that session. The published v0.1.0 download does not include these new plot tools.
