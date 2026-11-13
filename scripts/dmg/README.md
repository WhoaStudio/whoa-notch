# DMG presentation

Package an already-built app without changing its signature or notarization:

```bash
./scripts/package-dmg.sh "/path/to/whoa-notch.app" "Build/whoa-notch.dmg"
```

`scripts/build-dmg.sh` uses this same packaging step for GitHub Releases. The
Applications symlink and app at the volume root are also usable by Homebrew casks.
The script prints the finished DMG's SHA-256. It refuses to overwrite an existing
output. Run on macOS in a logged-in graphical session with permission to automate
Finder; a headless session cannot save the presentation.

The background is black with purple pixel accents, an arrow and a drag hint.
`background.png` is 720 × 440 at 72 dpi; `background@2x.png` is 1440 × 880 at
144 dpi. Packaging combines them into a multi-resolution TIFF using macOS's
`tiffutil -cathidpicheck`. No third-party packaging dependency is required.

Finder uses a 720 × 440 content area (plus its 32-point macOS 26 title bar), 96-point icons
at (180, 229) and (540, 229), and no toolbar, sidebar or status bar. Geometry lives
in `layout.applescript`; update it together with both images if the art changes.

To check a packaged image, open it in Finder, confirm the presentation and drag
target, then eject it. `hdiutil attach -nobrowse` intentionally suppresses Finder
opening and is useful for automated checks of the contents instead.

The artwork was generated from the supplied purple pixel reference as style
inspiration; the app and Applications icons are real Finder items, not baked into
the image. This packaging script does not publish releases or update the cask.
