#!/usr/bin/env bash
# =============================================================================
# build_archive.sh — Archive & sign FatCatPomodoro for Developer ID distribution
#
# Usage: ./scripts/build_archive.sh
#
# Strategy: archive with signing DISABLED, then apply Developer ID cert manually
# via codesign. This sidesteps Xcode 16's Automatic/Manual signing conflicts.
#
# Prerequisites:
#   • Xcode 16+
#   • "Developer ID Application: Ky Anh Pham (NZJ6XP9B66)" cert in keychain
#     Verify: security find-identity -v -p codesigning | grep "Developer ID Application"
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
ARCHIVE="$BUILD_DIR/FatCatPomodoro.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_IN_ARCHIVE="$ARCHIVE/Products/Applications/FatCatPomodoro.app"
APP_EXPORT="$EXPORT_DIR/FatCatPomodoro.app"
SCHEME="FatCatPomodoro"
PROJECT="$REPO_ROOT/FatCatPomodoro.xcodeproj"
ENTITLEMENTS="$REPO_ROOT/Sources/FatCatPomodoro/FatCatPomodoro.entitlements"
SIGN_IDENTITY="Developer ID Application: Ky Anh Pham (NZJ6XP9B66)"

echo "══════════════════════════════════════════════════"
echo " FatCatPomodoro — Archive & Sign"
echo "══════════════════════════════════════════════════"
echo "  Project  : $PROJECT"
echo "  Scheme   : $SCHEME"
echo "  Archive  : $ARCHIVE"
echo "  Export   : $EXPORT_DIR"
echo "  Identity : $SIGN_IDENTITY"
echo ""

# Verify the signing certificate is present before we start
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "❌  Developer ID Application certificate not found in keychain."
    echo "    Install it from developer.apple.com → Certificates."
    exit 1
fi

# Clean previous artefacts
rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR"

# ── Step 1: Archive (signing disabled — applied manually in step 3) ───────────
echo "▶ Step 1/4 — Archiving without signing …"
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
    echo "    Run again without '| tail -20' to see full output:"
    echo "    xcodebuild archive -project \"$PROJECT\" -scheme $SCHEME -configuration Release -archivePath \"$ARCHIVE\" CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO"
    exit 1
fi
echo "✓ Archive created."
echo ""

# ── Step 2: Copy app to export dir ───────────────────────────────────────────
echo "▶ Step 2/4 — Copying to export directory …"
ditto "$APP_IN_ARCHIVE" "$APP_EXPORT"
echo "✓ Copied: $APP_EXPORT"
echo ""

# ── Step 3: Sign with Developer ID Application (inside-out) ──────────────────
echo "▶ Step 3/4 — Signing with Developer ID Application …"

# Sign nested frameworks, dylibs, and bundles first (deepest first)
find "$APP_EXPORT" \( -name "*.framework" -o -name "*.dylib" -o -name "*.bundle" \) | sort -r | while read -r item; do
    codesign --force --sign "$SIGN_IDENTITY" --options runtime "$item" 2>/dev/null || true
done

# Sign the .app bundle itself with entitlements + hardened runtime
codesign --force --deep --sign "$SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    --timestamp \
    "$APP_EXPORT"

echo "✓ Signed."
echo ""

# ── Step 4: Verify signature ─────────────────────────────────────────────────
echo "▶ Step 4/4 — Verifying code signature …"
codesign --verify --deep --strict --verbose=2 "$APP_EXPORT"
echo ""
codesign -dv --entitlements :- "$APP_EXPORT" 2>/dev/null | head -20
echo ""
echo "══════════════════════════════════════════════════"
echo "✅  Build complete."
echo "    App: $APP_EXPORT"
echo ""
echo "Next steps:"
echo "  1. Run: ./scripts/notarize.sh   (requires APPLE_ID + APP_SPECIFIC_PASSWORD)"
echo "  2. Run: ./scripts/make_dmg.sh   (after notarization succeeds)"
echo "══════════════════════════════════════════════════"
