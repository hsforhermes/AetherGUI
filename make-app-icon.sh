#!/bin/bash
# Build the app icon (assets/AppIcon.icns) from the vector source.
#
# Renders assets/icon_pack/icon_color.svg at every size macOS needs rather than
# downscaling a single bitmap. The previously shipped assets/icon.png was a
# traced bitmap with an opaque background baked in (only 44.8% transparent,
# vs 70.1% for the vector), so the Dock icon showed that background as a solid
# plate. The vector has no such artifact at any size.
#
# Requires rsvg-convert (brew install librsvg) and iconutil (ships with Xcode).
#
# Run this after replacing the SVG with new artwork.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SVG="${1:-$DIR/assets/icon_pack/icon_color.svg}"
ICONSET="$DIR/assets/AppIcon.iconset"
OUT="$DIR/assets/AppIcon.icns"

if [ ! -f "$SVG" ]; then
  echo "source not found: $SVG" >&2
  exit 1
fi
if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert not found — install with: brew install librsvg" >&2
  exit 1
fi

# iconutil requires the directory to be named *.iconset and to use Apple's
# exact filename convention, or it fails with "Invalid Iconset".
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

for n in 16 32 128 256 512; do
  rsvg-convert -w "$n" -h "$n" "$SVG" -o "$ICONSET/icon_${n}x${n}.png"
  rsvg-convert -w $((n*2)) -h $((n*2)) "$SVG" -o "$ICONSET/icon_${n}x${n}@2x.png"
done

iconutil -c icns "$ICONSET" -o "$OUT"

# iconutil is the authority on whether the iconset is valid, so round-trip it
# back out to confirm the icns really holds every resolution.
CHECK="$(mktemp -d)/recheck.iconset"
trap 'rm -rf "$(dirname "$CHECK")"' EXIT
iconutil -c iconset "$OUT" --output "$CHECK" >/dev/null 2>&1
COUNT="$(find "$CHECK" -name 'icon_*.png' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$COUNT" -ne 10 ]; then
  echo "ERROR: icns round-trip produced $COUNT images, expected 10" >&2
  exit 1
fi

echo "wrote: $OUT ($(stat -f%z "$OUT") bytes, $COUNT resolutions verified)"
