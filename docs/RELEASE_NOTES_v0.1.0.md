# COSI Explorer v0.1.0

First public release of a local, read-only viewer for FITS and supported COSI L0 packet products.

- Plot column values against stored time or original 1-based row numbers.
- Browse tables, full row fields, FITS headers, and first-plane images.
- Use histograms, event-count plots, hit geometry, conservative pipeline tracing, and spectrum overlays.
- Export plotted pairs or common-bin comparisons to CSV with provenance/settings metadata.
- Build the C++17 core and CLI from MIT-licensed source with independent fixture tests.

## Downloads

- `COSI-Explorer-v0.1.0-macos-arm64.dmg`: drag-to-Applications download for macOS 15+ on Apple Silicon, with CFITSIO included.
- `COSI-Explorer-v0.1.0-macos-arm64.zip`: alternative archive of the same app.
- `COSI-Explorer-v0.1.0-source.zip`: repository-ready source and release instructions.
- `SHA256SUMS.txt`: checksums for the ZIP assets.

Open the DMG, drag the app to Applications, eject the disk image, then open a data file or select your own data folder. No observation data is included.

This initial binary is locally ad-hoc signed, **not Developer ID signed or notarized**; Gatekeeper may block downloaded copies. Build from source or consult Apple's documented handling of unnotarized software. Do not describe this build as notarized.

The GUI is macOS-only. Intel binaries, Linux CLI runtime, and Windows have not been verified in this release. Source units/timestamps are preserved; the app does not apply calibration, reconstruction, clock correction, exposure correction, or sky localization. Raw L0 row-order matches remain candidates rather than proven event identity.

Independent viewer; no NASA or COSI mission endorsement is implied. Project code is MIT; bundled CFITSIO retains its own notice and license.
