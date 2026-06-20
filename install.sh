#!/usr/bin/env bash
# install.sh
# FaceGuard — Simple installation script that bypasses XcodeGen
#
# Usage: sudo bash install.sh

set -euo pipefail

# Function to log with timestamp
log_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="FaceGuard"
VERSION="1.0.0"
APP_NAME="FaceGuard.app"
INSTALL_DIR="/Applications"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║          FaceGuard Simple Installer                  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
log_timestamp "Installation started at: $(date '+%Y-%m-%d %H:%M:%S')"
log_timestamp "Project directory: $PROJECT_DIR"
log_timestamp "Target version: $VERSION"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    log_timestamp "⚠ Warning: Not running as root. Installation may require sudo privileges."
    log_timestamp "Please run: sudo bash install.sh"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_timestamp "Installation cancelled."
        exit 1
    fi
fi

log_timestamp "Step 1/3 — Building FaceGuard using Swift Package Manager..."
cd "$PROJECT_DIR"

# Build using Swift Package Manager
log_timestamp "Running: swift build -c release"
swift build -c release

if [ $? -eq 0 ]; then
    log_timestamp "✓ Build completed successfully"
else
    log_timestamp "✗ Build failed. Please check the errors above."
    exit 1
fi

log_timestamp "Step 2/3 — Creating application bundle..."
BUILD_OUTPUT=".build/release/$PROJECT_NAME"
APP_BUNDLE="$INSTALL_DIR/$APP_NAME"

# Create app bundle structure
log_timestamp "Creating .app bundle structure at: $APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy the binary
log_timestamp "Copying binary to: $APP_BUNDLE/Contents/MacOS/"
cp "$BUILD_OUTPUT" "$APP_BUNDLE/Contents/MacOS/$PROJECT_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$PROJECT_NAME"

# Copy the icon
log_timestamp "Copying AppIcon.icns to: $APP_BUNDLE/Contents/Resources/"
cp "$PROJECT_DIR/FaceGuard/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Create Info.plist
log_timestamp "Creating Info.plist..."
cat > "$APP_BUNDLE/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FaceGuard</string>
    <key>CFBundleIdentifier</key>
    <string>com.yourname.FaceGuard</string>
    <key>CFBundleName</key>
    <string>FaceGuard</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>FaceGuard uses your camera to detect who is looking at your screen…</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>FaceGuard needs this to lock your screen.</string>
</dict>
</plist>
EOF

log_timestamp "✓ Application bundle created"

log_timestamp "Step 3/3 — Setting permissions and completing installation..."
# Set proper permissions
if [ "$EUID" -eq 0 ]; then
    chown -R root:wheel "$APP_BUNDLE"
    log_timestamp "✓ Ownership set to root:wheel"
else
    log_timestamp "⚠ Skipping ownership change (not running as root)"
fi
chmod -R 755 "$APP_BUNDLE"
log_timestamp "✓ Permissions set to 755"

log_timestamp "✓ Installation completed successfully"
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✅  INSTALLATION COMPLETE!                         ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
log_timestamp "FaceGuard installed to: $APP_BUNDLE"
log_timestamp "You can now launch FaceGuard from your Applications folder"
echo ""
log_timestamp "Installation completed at: $(date '+%Y-%m-%d %H:%M:%S')"
