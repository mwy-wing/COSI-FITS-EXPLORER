# Homebrew installation for COSI Explorer

COSI Explorer is a desktop app, so the Homebrew route is a **cask**. A custom tap lets the project distribute a cask without first joining Homebrew's main catalog. Nothing is published or installed by the local release scripts.

## Current status

The v0.1.1 DMG is distributed through GitHub Releases. A cask generator is included, but no custom tap has been published. A tap must be published before an installation command will work. Homebrew does not bypass Gatekeeper or notarization.

## Publish a custom tap

1. Use the app repository and its v0.1.1 GitHub Release. Keep the attached `COSI-Explorer-v0.1.1-macos-arm64.dmg` unchanged.
2. Create a public repository named `homebrew-tap` under your GitHub account.
3. In a local checkout of that tap, create `Casks/cosi-explorer.rb` with the included generator. From the app source folder, run the following, replacing the tap checkout path:

```sh
python3 scripts/make-homebrew-cask.py \
  --repo mwy-wing/COSI-FITS-EXPLORER \
  --dmg dist/COSI-Explorer-v0.1.1-macos-arm64.dmg \
  --output /path/to/homebrew-tap/Casks/cosi-explorer.rb
```

4. Commit and push the cask to `homebrew-tap`. It records the actual DMG checksum, release URL, macOS 15 minimum, Apple Silicon requirement, and app bundle name.
5. Test the public URL and installation on a separate Mac. After the release and tap are public, users can run:

```sh
brew install --cask mwy-wing/tap/cosi-explorer
```

This is not a working command until the custom tap is published. Users do not need to install CFITSIO separately. Future cask versions can be installed with `brew upgrade --cask cosi-explorer` after the tap is updated. There is no built-in in-app auto-updater in v0.1.1.

The draft cask is not submitted to the main Homebrew catalog. For distribution now, use the DMG directly. For a smooth first launch, complete Developer ID signing/notarization before finalizing the DMG and generating its checksum/cask.

Sources: [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook), [Creating and maintaining a tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap).
