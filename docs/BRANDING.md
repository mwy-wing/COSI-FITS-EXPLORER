# COSI Explorer icon

![COSI Explorer icon](../resources/COSIExplorer.png)

The current icon is original flat vector artwork: an ivory C and three orange spectrum bars on an ink-blue tile. This is an independent app identity, not the official COSI mission or NASA logo. It is a decorative mark, not a physical detector diagram.

- `resources/COSIExplorer.svg`: editable 1024 × 1024 vector master.
- `resources/COSIExplorer.png`: transparent 1024 × 1024 PNG.
- `resources/COSIExplorer.icns`: standard and Retina macOS representations from 16 through 1024 pixels.

Run `bash scripts/make-icon.sh` on macOS to regenerate the three assets. The native renderer in `scripts/render-icon.mm` shares the SVG and PNG geometry; iconutil assembles the ICNS. No image-model service or network access is needed. See [the artwork notes](../resources/README.md) for the palette and geometry.

CMake packages the ICNS, Info.plist selects it, and the app uses it for the Dock and library glyph. The README banner follows the same mark and palette. The icon is included in v0.1.1; the older v0.1.0 release assets retain their original artwork.
