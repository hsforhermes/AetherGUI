# v0.1.1 — app icon and menu-bar artwork

Two changes, both cosmetic: the app finally has a real icon, and the menu-bar
item uses its own glyph instead of an SF Symbol.

## What's new

**App icon.** The Dock and Finder now show the glossy neon orbital A instead of
the generic default. Built from `assets/icon.png` into a full iconset
(16 → 1024 px) and compiled to `AppIcon.icns`, wired up via `CFBundleIconFile`
in the plist.

**Menu-bar glyph.** The status item now renders its own artwork instead of
`bolt.shield.fill`. It's loaded from the bundle at runtime and marked as a
template image, so macOS handles light/dark menu bars and the pressed state for
free. If the file is missing the app falls back to the SF Symbol rather than
showing nothing — verified by removing the resource and relaunching.

**Both icons are generated from vector art.** `assets/icon_pack/` is the source
of truth, and two scripts turn it into what the app ships:

```bash
./make-app-icon.sh       # icon_color.svg    -> AppIcon.icns  (10 resolutions)
./make-menubar-icon.sh   # icon_template.svg -> menubar_18.png
```

Each renders the SVG at its exact target size with `rsvg-convert` and verifies
its own output — the icon script round-trips the `.icns` through `iconutil` to
confirm all 10 resolutions are present, and the menu-bar script refuses to emit
a file with no alpha channel rather than shipping an opaque box.

**Why bitmaps were rejected, in case the artwork changes again.** Two earlier
attempts are worth recording so nobody repeats them:

- `assets/menubar.jpg` (the original Gemini image) **cannot work**: JPEG has no
  alpha channel, so its light-gray background is baked into the pixels and the
  menu bar renders a gray square behind the glyph.
- Chroma-keying that gray back out fails too. The glyph is a dark, shaded
  symbol, and keying on colour destroys the shading — 11 of 324 pixels survived
  at 18 px.
- The photo-derived `removebg` PNG was better but still soft: a mid-gray glyph
  (36/255) with 25.6% semi-transparent edge pixels, against 0/255 and 21.0% for
  the vector template.
- `assets/icon.png` was a traced bitmap with an opaque background baked in
  (44.8% transparent, vs 70.1% for the vector), so the Dock icon showed that
  background as a solid plate.

Verified on the running app: the bundle copies are byte-identical to the built
assets, and `lsof` shows the live process has `MenuBarIcon.png` mapped — proof
it loads from the bundle and does not silently fall back to the SF Symbol.

## Housekeeping

- Version bumped to `0.1.1` in `build.sh`.
- README documents how to rebuild the iconset after changing the source art.
- Added a **Versioning** section explaining the `0.x` scheme.

## Why `0.1.1` and not `1.0.0`

The first release was tagged `v2.3.0`, which tracked the version of the Aether
*client* it wraps — misleading, since this app's own history had barely begun.
From here the version tracks the GUI only, and it stays in `0.x` until the app
has real-world use on restricted networks. `1.0.0` will mean "feature-complete
and stable", not "we got round to it".

## Upgrade

Rebuild and relaunch:

```bash
./build.sh
```

The icon only appears after a fresh build, since it lives in the bundle.
