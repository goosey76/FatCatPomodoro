#!/usr/bin/env bash
# =============================================================================
# notarize.sh — Notarize & staple FatCatPomodoro.app
#
# Usage:
#   export APPLE_ID="you@example.com"
#   export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"   # from appleid.apple.com
#   ./scripts/notarize.sh
#
# Alternatively, store credentials in the keychain:
#   xcrun notarytool store-credentials "FatCatPomodoro-notarize" \
#       --apple-id "$APPLE_ID" \
#       --team-id NZJ6XP9B66 \
#       --password "$APP_SPECIFIC_PASSWORD"
#   Then set: export NOTARYTOOL_KEYCHAIN_PROFILE="FatCatPomodoro-notarize"
#
# Prerequisites:
#   • build/export/FatCatPomodoro.app must exist (run build_archive.sh first)
#   • Xcode 13+ (notarytool shipped in Xcode 13)
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO_ROOT/build/export/FatCatPomodoro.app"
ZIP="$REPO_ROOT/build/FatCatPomodoro-notarize.zip"
TEAM_ID="NZJ6XP9B66"

echo "══════════════════════════════════════════════════"
echo " FatCatPomodoro — Notarize & Staple"
echo "══════════════════════════════════════════════════"

# Validate that the app was built first
if [ ! -d "$APP" ]; then
    echo "❌  Error: $APP not found."
    echo "    Run ./scripts/build_archive.sh first."
    exit 1
fi

# ── Credential resolution ─────────────────────────────────────────────────────
if [ -n "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]; then
    echo "  Auth   : Keychain profile → $NOTARYTOOL_KEYCHAIN_PROFILE"
    NOTARY_AUTH=(--keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE")
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APP_SPECIFIC_PASSWORD:-}" ]; then
    echo "  Auth   : Apple ID → $APPLE_ID"
    NOTARY_AUTH=(
        --apple-id "$APPLE_ID"
        --team-id "$TEAM_ID"
        --password "$APP_SPECIFIC_PASSWORD"
    )
else
    echo "❌  Error: No notarytool credentials found."
    echo ""
    echo "  Option A — env vars:"
    echo "    export APPLE_ID=\"you@example.com\""
    echo "    export APP_SPECIFIC_PASSWORD=\"xxxx-xxxx-xxxx-xxxx\""
    echo ""
    echo "  Option B — store in keychain (do once):"
    echo "    xcrun notarytool store-credentials \"FatCatPomodoro-notarize\" \\"
    echo "        --apple-id \"\$APPLE_ID\" --team-id $TEAM_ID \\"
    echo "        --password \"\$APP_SPECIFIC_PASSWORD\""
    echo "    export NOTARYTOOL_KEYCHAIN_PROFILE=\"FatCatPomodoro-notarize\""
    exit 1
fi

echo "  App    : $APP"
echo "  Zip    : $ZIP"
echo ""

# ── Step 1: Zip for submission ────────────────────────────────────────────────
echo "▶ Step 1/4 — Zipping .app for submission …"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "✓ Zipped: $ZIP"
echo ""

# ── Step 2: Submit to Apple notary service ────────────────────────────────────
echo "▶ Step 2/4 — Submitting to Apple notary service (this can take 1–5 min) …"
SUBMISSION_OUTPUT=$(xcrun notarytool submit "$ZIP" \
    "${NOTARY_AUTH[@]}" \
    --wait \
    --output-format json)

STATUS=$(echo "$SUBMISSION_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',''))")
SUBMISSION_ID=$(echo "$SUBMISSION_OUTPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))")

echo ""
echo "  Submission ID : $SUBMISSION_ID"
echo "  Status        : $STATUS"
echo ""

if [ "$STATUS" != "Accepted" ]; then
    echo "❌  Notarization failed! Fetching log …"
    xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_AUTH[@]}" 2>&1 || true
    exit 1
fi

echo "✓ Notarization accepted."
echo ""

# ── Step 3: Staple ticket to .app ────────────────────────────────────────────
echo "▶ Step 3/4 — Stapling ticket …"
xcrun stapler staple "$APP"
echo "✓ Ticket stapled."
echo ""

# ── Step 4: Gatekeeper assessment ────────────────────────────────────────────
echo "▶ Step 4/4 — Verifying Gatekeeper assessment …"
spctl --assess --type execute --verbose "$APP"
echo ""
echo "══════════════════════════════════════════════════"
echo "✅  Notarization & stapling complete."
echo "    App is ready for DMG packaging."
echo ""
echo "Next step: ./scripts/make_dmg.sh"
echo "══════════════════════════════════════════════════"
