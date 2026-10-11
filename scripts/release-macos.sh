#!/usr/bin/env bash
# ==============================================================================
# release-macos.sh
# Master release script for Murmur on macOS.
# Coordinates: testing -> build -> sign -> notarize -> DMG -> verify -> checksums.
# ==============================================================================
set -euo pipefail

VERSION="${1:-1.0.0}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="${REPO_ROOT}/release"
MACOS_RELEASE_DIR="${RELEASE_DIR}/macos"
CHECKSUM_FILE="${RELEASE_DIR}/SHA256SUMS.txt"

echo "=========================================="
echo "    Murmur macOS Master Release v${VERSION}   "
echo "=========================================="

mkdir -p "${MACOS_RELEASE_DIR}"

# 1. Run full test suite
echo ""
echo ">>> [1/6] Running automated tests <<<"
make test

# 2. Build release .app
echo ""
echo ">>> [2/6] Building release bundle <<<"
"${REPO_ROOT}/scripts/build-macos-release.sh" "${VERSION}"

# 3. Sign application
echo ""
echo ">>> [3/6] Signing application <<<"
"${REPO_ROOT}/scripts/sign-macos.sh"

# 4. Notarize application (if credentials provided)
echo ""
echo ">>> [4/6] Notarizing application <<<"
"${REPO_ROOT}/scripts/notarize-macos.sh" "${HOME}/Library/Caches/MurmurBuild/Murmur.app"

# 5. Create DMG
echo ""
echo ">>> [5/6] Creating distribution DMG <<<"
"${REPO_ROOT}/scripts/create-dmg.sh" "${VERSION}"

# 6. Verify release
echo ""
echo ">>> [6/6] Verifying release package <<<"
"${REPO_ROOT}/scripts/verify-macos-release.sh" "${VERSION}"

# 7. Update SHA-256 Checksums
echo ""
echo ">>> Updating SHA-256 checksums <<<"
TEMP_CHECKSUM="$(mktemp)"

# Preserve existing Windows checksum entries
if [[ -f "${CHECKSUM_FILE}" ]]; then
    grep -v "macos/" "${CHECKSUM_FILE}" > "${TEMP_CHECKSUM}" || true
fi

# Add macOS artifacts
find "${MACOS_RELEASE_DIR}" -type f -name "*.dmg" | sort | while read -r file; do
    HASH=$(shasum -a 256 "${file}" | awk '{print $1}')
    REL_PATH="macos/$(basename "${file}")"
    echo "${HASH}  ${REL_PATH}" >> "${TEMP_CHECKSUM}"
    echo "  ${HASH}  ${REL_PATH}"
done

mv "${TEMP_CHECKSUM}" "${CHECKSUM_FILE}"
echo "Updated checksum file: ${CHECKSUM_FILE}"

echo ""
echo "=========================================="
echo " Murmur macOS Release v${VERSION} Complete! "
echo "=========================================="
