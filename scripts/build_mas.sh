#!/usr/bin/env bash
# =============================================================================
# build_mas.sh — Archive & sign FatCatPomodoro for Mac App Store (MAS)
#
# Usage: ./scripts/build_mas.sh
#
# Prerequisites:
#   • Xcode 16+
#   • "Apple Distribution: Ky Anh Pham (NZJ6XP9B66)" cert in keychain
#   • "Mac Installer Distribution: Ky Anh Pham (NZJ6XP9B66)" cert in keychain
#
# Note: You MUST generate these two certificates from developer.apple.com
# and double-click to install them into your keychain before running this script.
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build_mas"
ARCHIVE="$BUILD_DIR/FatCatPomodoro.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_IN_ARCHIVE="$ARCHIVE/Products/Applications/FatCatPomodoro.app"
APP_EXPORT="$EXPORT_DIR/FatCatPomodoro.app"
PKG_OUTPUT="$BUILD_DIR/FatCatPomodoro.pkg"
SCHEME="FatCatPomodoro"
PROJECT="$REPO_ROOT/FatCatPomodoro.xcodeproj"
ENTITLEMENTS="$REPO_ROOT/Sources/FatCatPomodoro/FatCatPomodoro.entitlements"

APP_SIGN_IDENTITY="Apple Distribution: Ky Anh Pham (NZJ6XP9B66)"
PKG_SIGN_IDENTITY="Mac Installer Distribution: Ky Anh Pham (NZJ6XP9B66)"

echo "══════════════════════════════════════════════════"
echo " FatCatPomodoro — Mac App Store Build"
echo "══════════════════════════════════════════════════"

# Clean previous artefacts
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR"

# ── Step 1: Archive ─────────────────────────────────────────────────────────
echo "▶ Step 1/3 — Archiving …"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    DEVELOPMENT_TEAM=NZJ6XP9B66 2>&1 | grep -E "error:|warning:| ARCHIVE |✓|❌" || true

if [ ! -d "$APP_IN_ARCHIVE" ]; then
    echo "❌  Archive failed — app not found at $APP_IN_ARCHIVE"
    exit 1
fi
echo "✓ Archive created."
echo ""

# ── Step 2: Copy & Sign App ──────────────────────────────────────────────────
echo "▶ Step 2/3 — Signing App for MAS …"
ditto "$APP_IN_ARCHIVE" "$APP_EXPORT"

# Sign the .app bundle itself with entitlements
codesign --force --deep --sign "$APP_SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    --timestamp \
    "$APP_EXPORT"

echo "✓ App Signed."
echo ""

# ── Step 3: Build & Sign PKG ─────────────────────────────────────────────────
echo "▶ Step 3/3 — Packaging into .pkg for MAS …"
productbuild --component "$APP_EXPORT" /Applications --sign "$PKG_SIGN_IDENTITY" "$PKG_OUTPUT"

echo "✓ PKG created and signed."
echo ""
echo "══════════════════════════════════════════════════"
echo "✅  Mac App Store build complete."
echo "    App: $APP_EXPORT"
echo "    PKG: $PKG_OUTPUT"
echo ""
echo "Next step:"
echo "  Upload $PKG_OUTPUT to App Store Connect using the Transporter app!"
echo "══════════════════════════════════════════════════"
