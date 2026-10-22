<div align="center">

![COSI Explorer — Your mission data, in view](docs/assets/banner.svg)

[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-18181b?logo=apple&logoColor=white)](#get-started)
[![Build and test](https://github.com/mwy-wing/COSI-FITS-EXPLORER/actions/workflows/build.yml/badge.svg)](https://github.com/mwy-wing/COSI-FITS-EXPLORER/actions/workflows/build.yml)
[![v0.1.0](https://img.shields.io/badge/version-0.1.0-4f64e8)](https://github.com/mwy-wing/COSI-FITS-EXPLORER/releases/tag/v0.1.0)
[![MIT License](https://img.shields.io/badge/license-MIT-10b981)](LICENSE)

**[Download for Mac ↓](https://github.com/mwy-wing/COSI-FITS-EXPLORER/releases/download/v0.1.0/COSI-Explorer-v0.1.0-macos-arm64.dmg)** · [Try demo data](https://github.com/mwy-wing/COSI-FITS-EXPLORER/releases/download/v0.1.0/synthetic-events.fits) · [User guide](docs/USER_GUIDE.md) · [Contribute](CONTRIBUTING.md)

</div>

A native macOS app for browsing FITS files, visualizing columns, and exploring COSI events.

![COSI Explorer switching between energy versus time, original row number, and a histogram](docs/assets/demo.gif)

<p align="center"><sub>Time → Row number → Histogram · Synthetic demo data</sub></p>

## What you can do

- **Inspect** FITS tables, headers, images, and supported COSI packet files.
- **Plot** column values against time or row number, with filters and histograms.
- **Compare** spectra and export your plots to CSV.
- **Explore** hit geometry and trace events across processing stages.

Your files stay on your computer and are opened read-only.

## Get started

**Apple Silicon · macOS 15+**

1. [Download the DMG](https://github.com/mwy-wing/COSI-FITS-EXPLORER/releases/download/v0.1.0/COSI-Explorer-v0.1.0-macos-arm64.dmg), open it, and drag **COSI Explorer** to **Applications**.
2. Open the app, then choose **Open file…** with your own file or the [synthetic demo](https://github.com/mwy-wing/COSI-FITS-EXPLORER/releases/download/v0.1.0/synthetic-events.fits).
3. Choose **X axis → Time / Row number** and pick a **Y column**.

This initial download is **not Apple-notarized**; macOS may block it. See [Apple's guidance](https://support.apple.com/en-us/102445) or build from source below.

<details>
<summary>Build from source</summary>

Install [Xcode Command Line Tools](https://developer.apple.com/xcode/resources/) first, then:

```sh
git clone https://github.com/mwy-wing/COSI-FITS-EXPLORER.git
cd COSI-FITS-EXPLORER
brew install cmake pkg-config cfitsio
bash build.sh
open "dist/COSI Explorer.app"
```

</details>

---

[User guide](docs/USER_GUIDE.md) · [Release guide](docs/RELEASING.md) · [Contributors](AUTHORS.md) · [MIT license](LICENSE)
