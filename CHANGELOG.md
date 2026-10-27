# Changelog

## 0.1.1 — 2026-10-27

- Summary inspector with column range, median, mean, collected/input counts, and full-precision copy text.
- Explicit partial-scan/collection scope and limits in plot settings and summaries.
- Flat original vector C/spectrum icon, reproducible native icon builder, and matching README banner.

- All rows / Plotted rows table views, with original row IDs, filtered paging/jumps, and restored table choice.
- Contributing-row lists for point, histogram, event-count, and source-A overlay plots, with empty-result recovery.

- Click plotted points to select their original table rows across pages and reveal all fields.
- Inspect/Pan/Box zoom controls, rectangle zoom on both axes, and undoable Back/Reset navigation.
- X/Y viewport restoration and figure provenance; selected-row highlighting in point plots.

- Point hover readouts with full-precision plotted values, original rows, and stored time; histogram bin/overlay readouts.
- PNG and searchable vector PDF figure export with applied filters, units, sources, display range, and normalization.
- Last file/HDU, plot settings, viewport, and window/panel layout restored on reopening.
- Viewer-generated notes clearly separated from the original FITS header.
- Original COSI Explorer logo and a native macOS Dock icon.

- Public synthetic FITS example and a reproducible generator that refuses overwrites.
- Automated macOS app/core builds and Linux core/CLI builds with three CTest suites.
- Direct Mac download and demo links, plus an animation of the native app, in the README.

## 0.1.0 — first public release

- Native macOS COSI/FITS and supported L0 packet inspection.
- Column values against stored time or original 1-based row numbers.
- Automatic column/axis updates, histograms, event counts, and column comparison.
- Paged tables, complete row fields, FITS headers, and first-plane images.
- Active-hit geometry and conservative cross-stage event tracing.
- Shared-bin spectrum overlays and CSV export with source/settings metadata.
- Portable C++17 reader/CLI and independent fixture-based tests.
- MIT license, bundled CFITSIO notices, and reproducible release packaging.

- Drag-to-Applications DMG and a custom Homebrew cask generator for future publication.

The earlier 0.2/0.3/0.4 labels were local prototype iterations. Public versioning starts at v0.1.0.
