# v0.1.1 — app icon and menu-bar artwork

Two changes, both cosmetic: the app finally has a real icon, and the menu-bar
item uses its own glyph instead of an SF Symbol.

## What's new

**App icon.** The Dock and Finder now show the glossy neon orbital A instead of
the generic default. Built from `assets/icon.png` into a full iconset
(16 → 1024 px) and compiled to `AppIcon.icns`, wired up via `CFBundleIconFile`
in the plist.

**Menu-bar glyph.** The status item now renders `assets/menubar.jpg` instead of
`bolt.shield.fill`. It's loaded from the bundle at runtime and marked as a
template image, so macOS handles light/dark menu bars and the pressed state for
free. If the file is missing the app falls back to the SF Symbol rather than
showing nothing — verified by removing the resource and relaunching.

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
