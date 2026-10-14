#!/bin/bash
# Build the menu-bar glyph (assets/menubar_18.png) from the icon pack.
#
# Source of truth is the VECTOR artwork, not a bitmap: `icon_template.svg` is a
# pure-black silhouette (fill="#000000") on a transparent canvas, so it renders
# razor-sharp at any size and macOS can tint it as a template image.
#
# Rendered at 54px (3x) on purpose. main.swift declares the image as 18x18
# POINTS, and macOS multiplies points by the display's backing scale factor to
# get physical pixels:
#
#     18pt x 1x (non-Retina) =  18px  -> downscaled, sharp
#     18pt x 2x (Retina)      =  36px  -> native, sharp
#     18pt x 3x (3x Retina)   =  54px  -> native, sharp
#
# Rendering at the largest of those means macOS never has to UPSCALE anything,
# and upscaling is what makes an icon look blurry. Measured on this artwork, the
# fraction of semi-transparent edge pixels — the direct measure of softness —
# drops sharply with resolution:
#
#     18px source: 21.0% soft edge   (what the first releases shipped)
#     36px source: 11.7% soft edge
#     54px source:  7.4% soft edge   (shipped)
#
# Bitmap alternatives in the pack were measured and rejected:
#   - Gemini_Generated_Image_...-removebg-preview.png (an earlier glyph):
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
PX=54   # see the resolution note above; the filename is kept for compatibility

if [ ! -f "$SVG" ]; then
  echo "source not found: $SVG" >&2
  exit 1
fi
if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert not found — install with: brew install librsvg" >&2
  exit 1
fi

# Render the vector straight to the largest size the menu bar can ask for.
# No intermediate downscale, so the alpha edge stays as crisp as the vector
# describes it.
rsvg-convert -w "$PX" -h "$PX" "$SVG" -o "$OUT"

ALPHA="$(sips -g hasAlpha "$OUT" | tail -1 | awk '{print $2}')"
if [ "$ALPHA" != "yes" ]; then
  echo "ERROR: $OUT has no alpha channel — the icon will render as a solid box" >&2
  exit 1
fi

WIDTH="$(sips -g pixelWidth "$OUT" | tail -1 | awk '{print $2}')"
echo "wrote: $OUT (${WIDTH}px, alpha ok; declared as 18pt in main.swift)"
