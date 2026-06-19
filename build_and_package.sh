#!/usr/bin/env bash
# build_and_package.sh
# FaceGuard — One-shot build, archive, and package creation script.
#
# Usage: bash build_and_package.sh
# Output: ~/Downloads/FaceGuard-1.0.0.pkg

set -euo pipefail

# Function to log with timestamp
log_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to log step start with timing
log_step_start() {
    log_timestamp "▶ START: $1"
    STEP_START_TIME=$(date +%s)
}

# Function to log step end with timing
log_step_end() {
    STEP_END_TIME=$(date +%s)
    STEP_DURATION=$((STEP_END_TIME - STEP_START_TIME))
    log_timestamp "✓ COMPLETE: $1 (took ${STEP_DURATION}s)"
}

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
log_timestamp "Build started at: $(date '+%Y-%m-%d %H:%M:%S')"
log_timestamp "Project directory: $PROJECT_DIR"
log_timestamp "Build directory: $BUILD_DIR"
log_timestamp "Target version: $VERSION"
echo ""

# ── Step 1: Generate Xcode Project ─────────────────────────────────────────
log_step_start "Step 1/5 — Generating Xcode project with XcodeGen"
cd "$PROJECT_DIR/FaceGuard"
log_timestamp "Current directory: $(pwd)"
log_timestamp "Running: xcodegen generate --spec project.yml"
xcodegen generate --spec project.yml
log_timestamp "Xcode project generation completed"
log_step_end "Step 1/5 — Generating Xcode project with XcodeGen"

# ── Step 2: Archive ─────────────────────────────────────────────────────────
echo ""
log_step_start "Step 2/5 — Archiving (Release build)"
mkdir -p "$BUILD_DIR"
log_timestamp "Build directory created: $BUILD_DIR"
log_timestamp "Archive path: $ARCHIVE_PATH"
log_timestamp "Running xcodebuild archive (this may take several minutes)..."
log_timestamp "Command: xcodebuild archive -project $PROJECT_DIR/FaceGuard/$PROJECT_NAME.xcodeproj -scheme $PROJECT_NAME -configuration Release -archivePath $ARCHIVE_PATH -destination platform=macOS,arch=arm64"

xcodebuild archive \
    -project "$PROJECT_DIR/FaceGuard/$PROJECT_NAME.xcodeproj" \
    -scheme "$PROJECT_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "platform=macOS,arch=arm64" \
    CODE_SIGN_STYLE=Automatic \
    ONLY_ACTIVE_ARCH=NO \
    2>&1 | tee "$BUILD_DIR/archive.log" | grep -E "(error:|warning:|Build succeeded|Archive succeeded|FAILED|Compiling|Linking|Signing)" || true

log_timestamp "Archive build output saved to: $BUILD_DIR/archive.log"
log_timestamp "Archive created at: $ARCHIVE_PATH"
log_step_end "Step 2/5 — Archiving (Release build)"

# ── Step 3: Export .app ─────────────────────────────────────────────────────
echo ""
log_step_start "Step 3/5 — Exporting .app bundle"
mkdir -p "$EXPORT_DIR"
log_timestamp "Export directory created: $EXPORT_DIR"

# Create a minimal ExportOptions.plist for a direct developer export
log_timestamp "Creating ExportOptions.plist..."
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
log_timestamp "ExportOptions.plist created at: $BUILD_DIR/ExportOptions.plist"

# Export the archive to a .app bundle
log_timestamp "Running xcodebuild -exportArchive..."
log_timestamp "Expected app path: $APP_PATH"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    2>&1 | tee "$BUILD_DIR/export.log" | grep -E "(error:|Exported|FAILED|Copying|Processing)" || true

# Fallback: directly copy the .app from the archive if export fails
if [ ! -d "$APP_PATH" ]; then
    log_timestamp "⚠ Export step incomplete — copying .app directly from archive…"
    log_timestamp "Source: $ARCHIVE_PATH/Products/Applications/$PROJECT_NAME.app"
    log_timestamp "Destination: $EXPORT_DIR/"
    cp -R "$ARCHIVE_PATH/Products/Applications/$PROJECT_NAME.app" "$EXPORT_DIR/"
    log_timestamp "Direct copy completed"
fi

log_timestamp ".app exported to: $APP_PATH"
log_step_end "Step 3/5 — Exporting .app bundle"

# ── Step 4: Build .pkg with pkgbuild ────────────────────────────────────────
echo ""
log_step_start "Step 4/5 — Creating installer package (.pkg)"
mkdir -p "$STAGING_DIR/Applications"
log_timestamp "Staging directory created: $STAGING_DIR"
log_timestamp "Copying .app to staging directory..."
log_timestamp "Source: $APP_PATH"
log_timestamp "Destination: $STAGING_DIR/Applications/"
cp -R "$APP_PATH" "$STAGING_DIR/Applications/"
log_timestamp ".app copied to staging directory"

log_timestamp "Running pkgbuild..."
log_timestamp "Bundle ID: $BUNDLE_ID"
log_timestamp "Version: $VERSION"
pkgbuild \
    --root "$STAGING_DIR" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location "/" \
    --component-plist /dev/null \
    "$BUILD_DIR/${PROJECT_NAME}-${VERSION}-unsigned.pkg" \
    2>&1 | tee "$BUILD_DIR/pkgbuild.log"

log_timestamp "Unsigned package created: $BUILD_DIR/${PROJECT_NAME}-${VERSION}-unsigned.pkg"

# Wrap with productbuild for a polished installer (no signing required for local use)
log_timestamp "Running productbuild to create final package..."
log_timestamp "Final package output: $PKG_OUTPUT"
productbuild \
    --package "$BUILD_DIR/${PROJECT_NAME}-${VERSION}-unsigned.pkg" \
    "$PKG_OUTPUT" \
    2>&1 | tee "$BUILD_DIR/productbuild.log"

log_timestamp "Package built: $PKG_OUTPUT"
log_step_end "Step 4/5 — Creating installer package (.pkg)"

# ── Step 5: Verify and Open ─────────────────────────────────────────────────
echo ""
log_step_start "Step 5/5 — Verifying package"
log_timestamp "Checking if package exists at: $PKG_OUTPUT"
if [ -f "$PKG_OUTPUT" ]; then
    PKG_SIZE=$(du -sh "$PKG_OUTPUT" | cut -f1)
    log_timestamp "✓ Package verified: $PKG_OUTPUT ($PKG_SIZE)"
    log_timestamp "Build completed successfully!"
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  ✅  BUILD COMPLETE!                                 ║"
    printf "║  📦  Package: %-38s║\n" "${PROJECT_NAME}-${VERSION}.pkg"
    printf "║  📁  Saved to: ~/Downloads %-26s║\n" ""
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    log_timestamp "Opening Downloads folder..."
    # Open the Downloads folder
    open "$HOME/Downloads"
    log_timestamp "Revealing package in Finder..."
    # Reveal the file in Finder
    open -R "$PKG_OUTPUT"
    log_step_end "Step 5/5 — Verifying package"
else
    log_timestamp "✗ Package not found at expected path. Check build logs above."
    log_timestamp "Build logs available in: $BUILD_DIR/"
    exit 1
fi
