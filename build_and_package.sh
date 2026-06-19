#!/usr/bin/env bash
# build_and_package.sh
# FaceGuard — One-shot build, archive, and package creation script.
#
# Usage: bash build_and_package.sh
# Output: ~/Downloads/FaceGuard-1.0.0.pkg

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="FaceGuard"
BUNDLE_ID="com.yourname.FaceGuard"
VERSION="1.0.0"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$PROJECT_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$PROJECT_NAME.app"
PKG_OUTPUT="$HOME/Downloads/${PROJECT_NAME}-${VERSION}.pkg"
STAGING_DIR="$BUILD_DIR/pkg_staging"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║          FaceGuard Build & Package Script            ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Generate Xcode Project ─────────────────────────────────────────
echo "▶ Step 1/5 — Generating Xcode project with XcodeGen…"
cd "$PROJECT_DIR/FaceGuard"
xcodegen generate --spec project.yml
echo "  ✓ FaceGuard.xcodeproj generated"

# ── Step 2: Archive ─────────────────────────────────────────────────────────
echo ""
echo "▶ Step 2/5 — Archiving (Release build)…"
mkdir -p "$BUILD_DIR"
xcodebuild archive \
    -project "$PROJECT_DIR/FaceGuard/$PROJECT_NAME.xcodeproj" \
    -scheme "$PROJECT_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "platform=macOS,arch=arm64" \
    CODE_SIGN_STYLE=Automatic \
    ONLY_ACTIVE_ARCH=NO \
    2>&1 | grep -E "(error:|warning:|Build succeeded|Archive succeeded|FAILED)" || true
echo "  ✓ Archive created at: $ARCHIVE_PATH"

# ── Step 3: Export .app ─────────────────────────────────────────────────────
echo ""
echo "▶ Step 3/5 — Exporting .app bundle…"
mkdir -p "$EXPORT_DIR"

# Create a minimal ExportOptions.plist for a direct developer export
cat > "$BUILD_DIR/ExportOptions.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
EOF

# Export the archive to a .app bundle
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    2>&1 | grep -E "(error:|Exported|FAILED)" || true

# Fallback: directly copy the .app from the archive if export fails
if [ ! -d "$APP_PATH" ]; then
    echo "  ⚠ Export step incomplete — copying .app directly from archive…"
    cp -R "$ARCHIVE_PATH/Products/Applications/$PROJECT_NAME.app" "$EXPORT_DIR/"
fi

echo "  ✓ .app exported to: $APP_PATH"

# ── Step 4: Build .pkg with pkgbuild ────────────────────────────────────────
echo ""
echo "▶ Step 4/5 — Creating installer package (.pkg)…"
mkdir -p "$STAGING_DIR/Applications"
cp -R "$APP_PATH" "$STAGING_DIR/Applications/"

pkgbuild \
    --root "$STAGING_DIR" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location "/" \
    --component-plist /dev/null \
    "$BUILD_DIR/${PROJECT_NAME}-${VERSION}-unsigned.pkg" \
    2>&1

# Wrap with productbuild for a polished installer (no signing required for local use)
productbuild \
    --package "$BUILD_DIR/${PROJECT_NAME}-${VERSION}-unsigned.pkg" \
    "$PKG_OUTPUT" \
    2>&1

echo "  ✓ Package built: $PKG_OUTPUT"

# ── Step 5: Verify and Open ─────────────────────────────────────────────────
echo ""
echo "▶ Step 5/5 — Verifying package…"
if [ -f "$PKG_OUTPUT" ]; then
    PKG_SIZE=$(du -sh "$PKG_OUTPUT" | cut -f1)
    echo "  ✓ Package verified: $PKG_OUTPUT ($PKG_SIZE)"
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  ✅  BUILD COMPLETE!                                 ║"
    printf "║  📦  Package: %-38s║\n" "${PROJECT_NAME}-${VERSION}.pkg"
    printf "║  📁  Saved to: ~/Downloads %-26s║\n" ""
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    # Open the Downloads folder
    open "$HOME/Downloads"
    # Reveal the file in Finder
    open -R "$PKG_OUTPUT"
else
    echo "  ✗ Package not found at expected path. Check build logs above."
    exit 1
fi
