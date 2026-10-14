#!/bin/bash
# Build the menu-bar glyph (assets/menubar_18.png) from the icon pack.
#
# Source of truth is the VECTOR artwork, not a bitmap: `icon_template.svg` is a
# pure-black silhouette (fill="#000000") on a transparent canvas, so it renders
# razor-sharp at any size and macOS can tint it as a template image. Rendering
# from the SVG at the exact target resolution avoids every blur that comes from
# downscaling a large PNG.
#
# Bitmap alternatives in the pack were measured and rejected:
#   - Gemini_Generated_Image_...-removebg-preview.png (the previous glyph):
#     a photo-derived cutout with a mid-gray glyph (36/255) and 25.6%
#     semi-transparent edge pixels — visibly soft in the menu bar.
#   - preview_1024.png: no alpha channel at all, unusable.
#   - icon_1024_transparent.png: colour, but we want the pure-black template.
#
# Run this after replacing the SVG with new artwork.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SVG="${1:-$DIR/assets/icon_pack/icon_template.svg}"
OUT="$DIR/assets/menubar_18.png"

if [ ! -f "$SVG" ]; then
  echo "source not found: $SVG" >&2
  exit 1
fi
if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert not found — install with: brew install librsvg" >&2
  exit 1
fi

# Render the vector straight to 18px. No intermediate downscale, so the alpha
# edge stays as crisp as the vector describes it.
rsvg-convert -w 18 -h 18 "$SVG" -o "$OUT"

ALPHA="$(sips -g hasAlpha "$OUT" | tail -1 | awk '{print $2}')"
if [ "$ALPHA" != "yes" ]; then
  echo "ERROR: $OUT has no alpha channel — the icon will render as a solid box" >&2
  exit 1
fi

echo "wrote: $OUT ($(sips -g pixelWidth "$OUT" | tail -1 | awk '{print $2}')px, alpha ok)"
