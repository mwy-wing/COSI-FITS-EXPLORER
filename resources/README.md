# COSI Explorer icon

Original flat vector artwork: an ivory C surrounding three orange spectrum bars on an ink-blue tile. The mark uses no glow, gradients, stock imagery, image-model output, or third-party logo. It follows the project's MIT license.

The editable SVG, 1024-pixel transparent PNG, and native ICNS share the geometry in `scripts/render-icon.mm`. On macOS, regenerate them with:

```sh
bash scripts/make-icon.sh
```

The renderer draws every standard/Retina icon size directly from the same curves. The app loads the packaged ICNS for its Dock and library glyph. The README banner uses the same geometry and palette.

Colors: ink `#193746`, ivory `#F6F1E7`, orange `#EE9B52`. Master canvas: 1024 × 1024; tile inset: 96; corner radius: 186. Avoid adding effects or very fine detail that disappears at Dock size.
