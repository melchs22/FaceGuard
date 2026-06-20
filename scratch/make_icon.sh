#!/usr/bin/env bash
# make_icon.sh — Converts Icon.jpeg to AppIcon.icns

set -euo pipefail

# Find the project directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_JPEG="$PROJECT_DIR/Icon.jpeg"
OUTPUT_DIR="$PROJECT_DIR/FaceGuard/Resources"
ICONSET_DIR="/tmp/FaceGuard_AppIcon.iconset"

echo "Creating iconset directory..."
mkdir -p "$ICONSET_DIR"

# Generate the various sizes
echo "Generating resized images..."
sips -s format png -z 16 16     "$ICON_JPEG" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
sips -s format png -z 32 32     "$ICON_JPEG" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
sips -s format png -z 32 32     "$ICON_JPEG" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
sips -s format png -z 64 64     "$ICON_JPEG" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
sips -s format png -z 128 128   "$ICON_JPEG" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
sips -s format png -z 256 256   "$ICON_JPEG" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
sips -s format png -z 256 256   "$ICON_JPEG" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
sips -s format png -z 512 512   "$ICON_JPEG" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
sips -s format png -z 512 512   "$ICON_JPEG" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
sips -s format png -z 1024 1024 "$ICON_JPEG" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null

echo "Converting iconset to icns..."
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_DIR/AppIcon.icns"

echo "Cleaning up..."
rm -rf "$ICONSET_DIR"

echo "Icon generated successfully at $OUTPUT_DIR/AppIcon.icns"
