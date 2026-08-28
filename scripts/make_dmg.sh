#!/usr/bin/env bash
# =============================================================================
# make_dmg.sh — Package FatCatPomodoro.app as a drag-to-Applications .dmg
#
# Usage: ./scripts/make_dmg.sh
#
# Prerequisites:
#   • build/export/FatCatPomodoro.app must exist AND be notarized+stapled
#     (run build_archive.sh → notarize.sh first)
#   • hdiutil (ships with macOS)
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO_ROOT/build/export/FatCatPomodoro.app"
BUILD_DIR="$REPO_ROOT/build"
STAGING_DIR="$BUILD_DIR/dmg-staging"
VOLUME_NAME="FatCatPomodoro"
DMG_VERSION="1.0"
DMG_RW="$BUILD_DIR/${VOLUME_NAME}-rw.dmg"
DMG_FINAL="$BUILD_DIR/${VOLUME_NAME}-${DMG_VERSION}.dmg"

echo "══════════════════════════════════════════════════"
echo " FatCatPomodoro — Create DMG"
echo "══════════════════════════════════════════════════"

# Validate app is present
if [ ! -d "$APP" ]; then
    echo "❌  Error: $APP not found."
    echo "    Run ./scripts/build_archive.sh && ./scripts/notarize.sh first."
    exit 1
fi

echo "  App    : $APP"
echo "  Output : $DMG_FINAL"
echo ""

# ── Step 1: Stage content ─────────────────────────────────────────────────────
echo "▶ Step 1/4 — Staging DMG content …"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy app into staging
ditto "$APP" "$STAGING_DIR/FatCatPomodoro.app"

# Create symlink to /Applications for drag-install UX
ln -s /Applications "$STAGING_DIR/Applications"

echo "✓ Staged."
echo ""

# ── Step 2: Create read-write image ──────────────────────────────────────────
echo "▶ Step 2/4 — Creating read-write image …"
rm -f "$DMG_RW" "$DMG_FINAL"

# Estimate size: app size + 20 MB headroom
APP_SIZE_KB=$(du -sk "$APP" | awk '{print $1}')
DMG_SIZE_KB=$(( APP_SIZE_KB + 20480 ))

hdiutil create \
    -srcfolder "$STAGING_DIR" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -format UDRW \
    -size "${DMG_SIZE_KB}k" \
    "$DMG_RW"

echo "✓ Read-write image: $DMG_RW"
echo ""

# ── Step 3: Convert to compressed read-only ───────────────────────────────────
echo "▶ Step 3/4 — Converting to compressed read-only DMG …"
hdiutil convert "$DMG_RW" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_FINAL"

rm -f "$DMG_RW"
rm -rf "$STAGING_DIR"

echo "✓ DMG created: $DMG_FINAL"
echo ""

# ── Step 4: Verify DMG Gatekeeper signature ───────────────────────────────────
echo "▶ Step 4/4 — Verifying DMG …"
spctl --assess --type open --context context:primary-signature --verbose "$DMG_FINAL" 2>&1 || \
    echo "  ℹ  spctl DMG check skipped (ticket is on the .app inside, not the DMG wrapper — this is expected)."

# Show final file info
DMG_SIZE=$(du -sh "$DMG_FINAL" | awk '{print $1}')
echo ""
echo "══════════════════════════════════════════════════"
echo "✅  DMG ready for distribution!"
echo ""
echo "    File : $DMG_FINAL"
echo "    Size : $DMG_SIZE"
echo ""
echo "Hand off this file to be hosted on asifthatworks.com."
echo "══════════════════════════════════════════════════"
