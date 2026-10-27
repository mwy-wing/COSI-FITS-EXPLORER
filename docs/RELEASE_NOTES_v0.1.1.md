# COSI Explorer v0.1.1

A native, read-only macOS viewer for FITS files and supported COSI packet products.

## What's new

- Click a plotted point to open its original source row and complete event fields.
- Inspect, Pan, and Box zoom tools, with two-axis rectangle zoom and Back/Reset history.
- All rows / Plotted rows table views with original row numbers, paging, and jumps.
- Summary inspector with minimum, maximum, median, mean, input counts, and full-precision copying.
- PNG and searchable vector PDF figure exports alongside CSV, with units, filters, sources, and visible ranges.
- Restore the last file/HDU, applied plot settings, X/Y view, table choice, and window/panel layout.
- New original flat vector app icon and clearer partial-data/scan-limit metadata.

## Download and install

**[Download for Mac](https://github.com/mwy-wing/COSI-FITS-EXPLORER/releases/download/v0.1.1/COSI-Explorer-v0.1.1-macos-arm64.dmg)** · [Synthetic demo data](https://github.com/mwy-wing/COSI-FITS-EXPLORER/releases/download/v0.1.1/synthetic-events.fits)

**Apple Silicon · macOS 15 or later.** No Homebrew, compiler, Python, or separate CFITSIO installation is needed.

Download **COSI-Explorer-v0.1.1-macos-arm64.dmg**, open it, drag **COSI Explorer** to **Applications**, and eject the image. Launch the app and choose **Open file…**. To try it without mission data, also download **synthetic-events.fits** (1,200 invented events).

The app ZIP is an alternative download. The source ZIP includes the editable icon and build/test/release tools. **SHA256SUMS.txt** covers the DMG, app ZIP, source ZIP, and synthetic demo.

## Platform and scientific scope

This binary is **ad-hoc signed, not Apple Developer ID signed or notarized**. macOS may block a downloaded copy; consult [Apple's guidance](https://support.apple.com/en-us/102445). A DMG does not bypass Gatekeeper. Intel Mac and Windows binaries are not included; the Linux reader/CLI is available from source.

Values retain the stored units and time reference. No calibration, clock/attitude correction, exposure correction, or sky reconstruction is applied. Processing-stage links are conservative; L0 row-order matches remain candidates. Plot scan/collection limits are explicit. This independent viewer is not endorsed by NASA or the COSI mission.

Project code is MIT; bundled CFITSIO retains its own license and notice. No observation data, user preferences, or credentials are included.
