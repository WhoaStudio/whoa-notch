# Whoa Stash — hexagonal chest

The purple open chest is traced geometrically from the supplied reference. All SVG artwork is made of paths, without embedded bitmaps, text or filters.

- `icon-master.svg`: colour master; named groups `lid`, `lid-interior`, `clasp`, `body`, `opening`, `eyes` can be animated independently.
- `icon-small.svg`: colour export source for 16 and 32 px.
- `menubar.svg`: black and alpha template; eye cutouts use even-odd filling. An 18 pt canvas includes clear space around the silhouette.
- `icon-1024.png`: rendered colour master.

App icon PNGs live in `whoa-stash/Resources/Assets.xcassets/AppIcon.appiconset`. Settings uses this application icon automatically. Menu bar PNGs at 18 and 36 px live in `MenuBarIcon.imageset`; both the asset and `StatusBarController` enable template rendering so AppKit supplies normal and highlighted colours.

To regenerate PNGs, render each SVG on a transparent square canvas at the destination size. App icon sizes are 16, 32, 64, 128, 256, 512 and 1024 px; use `icon-small.svg` for 16 and 32 px.

## Menu animation

`MenuBarLid.imageset` and `MenuBarBody.imageset` contain the separate vector template parts from `menubar.svg`. Keep these in sync when changing the glyph. `StatusBarController` composites them at 18 pt, lifting the lid during native menu tracking and closing it on dismissal (180 ms). Reduce Motion switches directly between states.

## Launch greeting

`LaunchChest.imageset` is the colour master without its eyes; `LaunchEyes.imageset` contains the eyes cropped to viewBox `76 148 104 48`. Keep both in sync with `icon-master.svg`. The notch shows these parts once at launch in its left wing for 3.4 seconds, with finite blink, gaze and head-tilt animations. Reduce Motion and the overlay animation setting keep the mascot still.
