#!/usr/bin/env bash
# ==============================================================================
# notarize-macos.sh
# Notarizes an application bundle or DMG using modern Apple xcrun notarytool.
# Staples the notarization ticket upon success.
# ==============================================================================
set -euo pipefail

TARGET="${1:-${HOME}/Library/Caches/MurmurBuild/Murmur.app}"

echo "=========================================="
echo " Apple Notarization (xcrun notarytool)"
echo "=========================================="

if [[ ! -e "${TARGET}" ]]; then
    echo "Error: Target artifact not found at ${TARGET}" >&2
    exit 1
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-${KEYCHAIN_PROFILE:-}}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"

# Check if credentials are present
HAS_CREDS=false
if [[ -n "${NOTARY_PROFILE}" ]]; then
    HAS_CREDS=true
elif [[ -n "${APPLE_ID}" && -n "${APPLE_TEAM_ID}" && -n "${APPLE_PASSWORD}" ]]; then
    HAS_CREDS=true
fi

if [[ "${HAS_CREDS}" != "true" ]]; then
    echo "----------------------------------------------------------------------"
    echo " NOTICE: Apple Notarization credentials not detected."
    echo " Skipping notarization in DEVELOPMENT mode."
    echo ""
    echo " To enable notarization for PUBLIC RELEASE, configure one of the following:"
    echo " 1. Keychain Profile (Recommended):"
    echo "    xcrun notarytool store-credentials \"notary-profile\" \\"
    echo "      --apple-id \"developer@domain.com\" \\"
    echo "      --team-id \"XXXXXXXXXX\" \\"
    echo "      --password \"abcd-efgh-ijkl-mnop\""
    echo "    export NOTARY_PROFILE=\"notary-profile\""
    echo ""
    echo " 2. Environment Variables:"
    echo "    export APPLE_ID=\"developer@domain.com\""
    echo "    export APPLE_TEAM_ID=\"XXXXXXXXXX\""
    echo "    export APPLE_APP_SPECIFIC_PASSWORD=\"abcd-efgh-ijkl-mnop\""
    echo "----------------------------------------------------------------------"
    exit 0
fi

# Prepare payload: notarytool requires a zip or dmg
ZIP_TMP=""
SUBMIT_FILE="${TARGET}"

if [[ -d "${TARGET}" && "${TARGET}" == *.app ]]; then
    echo "Compressing .app into temporary zip for notarytool submission..."
    ZIP_TMP="$(mktemp -d)/app.zip"
    ditto -c -k --keepParent "${TARGET}" "${ZIP_TMP}"
    SUBMIT_FILE="${ZIP_TMP}"
fi

echo "Submitting ${SUBMIT_FILE} to Apple Notary Service..."

if [[ -n "${NOTARY_PROFILE}" ]]; then
    xcrun notarytool submit "${SUBMIT_FILE}" --keychain-profile "${NOTARY_PROFILE}" --wait
else
    xcrun notarytool submit "${SUBMIT_FILE}" \
        --apple-id "${APPLE_ID}" \
        --team-id "${APPLE_TEAM_ID}" \
        --password "${APPLE_PASSWORD}" \
        --wait
fi

# Clean temporary zip if created
if [[ -n "${ZIP_TMP}" && -f "${ZIP_TMP}" ]]; then
    rm -rf "$(dirname "${ZIP_TMP}")"
fi

# Staple ticket to artifact
echo "Stapling notarization ticket to ${TARGET}..."
xcrun stapler staple "${TARGET}"

echo "Validating stapled ticket..."
xcrun stapler validate "${TARGET}"

echo "Notarization and stapling complete for: ${TARGET}"
