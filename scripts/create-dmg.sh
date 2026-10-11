#!/usr/bin/env bash
# Build a compressed drag-to-Applications image without opening Finder or controlling UI.
set -euo pipefail

VERSION="${1:-1.0.0}"
APPNAME="Murmur.app"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="${HOME}/Library/Caches/MurmurBuild/${APPNAME}"
RELEASE_DIR="${REPO_ROOT}/release/macos"
FINAL_DMG="${RELEASE_DIR}/Murmur-${VERSION}.dmg"

if [[ ! -d "${BUNDLE}" ]]; then
    echo "Error: App bundle not found at ${BUNDLE}. Run build-macos-release.sh first." >&2
    exit 1
fi

mkdir -p "${RELEASE_DIR}"
TMP_DIR="$(mktemp -d -t murmur-dmg-XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT
DMG_SOURCE="${TMP_DIR}/source"
mkdir -p "${DMG_SOURCE}"
cp -R "${BUNDLE}" "${DMG_SOURCE}/"
ln -s /Applications "${DMG_SOURCE}/Applications"

# UDZO is created directly from the staged directory; no read-write mount or Finder automation.
TEMP_DMG="${TMP_DIR}/Murmur.dmg"
hdiutil create -ov -srcfolder "${DMG_SOURCE}" -format UDZO -imagekey zlib-level=9 \
    -volname Murmur -fs HFS+ "${TEMP_DMG}"

SIGN_ID="${SIGN_IDENTITY:-}"
if [[ -z "${SIGN_ID}" ]]; then
    SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)
fi
if [[ -n "${SIGN_ID}" && "${SIGN_ID}" != "-" ]]; then
    codesign --force --sign "${SIGN_ID}" --timestamp "${TEMP_DMG}"
    # Do not mask actual notarization failures. The verifier rejects an unnotarized public artifact.
    bash "${REPO_ROOT}/scripts/notarize-macos.sh" "${TEMP_DMG}"
else
    if [[ "${MURMUR_RELEASE_MODE:-development}" == "public" ]]; then
        echo "Error: Public DMGs require a Developer ID Application identity." >&2
        exit 1
    fi
    echo "Creating a DEVELOPMENT DMG: no Developer ID signature or public Gatekeeper approval."
fi

# Preserve a prior working artifact if any step above fails.
mv -f "${TEMP_DMG}" "${FINAL_DMG}"
echo "DMG created: ${FINAL_DMG} ($(du -sh "${FINAL_DMG}" | cut -f1))"
