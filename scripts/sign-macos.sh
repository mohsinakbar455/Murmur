#!/usr/bin/env bash
# ==============================================================================
# sign-macos.sh
# Signs Murmur.app with Apple Developer ID Application (or ad-hoc for dev).
# Enables Hardened Runtime and designated TCC requirements.
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="${1:-${HOME}/Library/Caches/MurmurBuild/Murmur.app}"
EXPLICIT_IDENTITY="${2:-${SIGN_IDENTITY:-}}"
ENTITLEMENTS="${REPO_ROOT}/Resources/Murmur.entitlements"

if [[ ! -d "${BUNDLE}" ]]; then
    echo "Error: App bundle not found at ${BUNDLE}" >&2
    exit 1
fi

echo "=========================================="
echo " Signing Murmur macOS Application"
echo "=========================================="

# Auto-detect Developer ID Application certificate if none explicitly given
if [[ -n "${EXPLICIT_IDENTITY}" ]]; then
    SIGN_ID="${EXPLICIT_IDENTITY}"
else
    SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)
fi

# Clean extended attributes before signing
xattr -cr "${BUNDLE}"

# Sign every relocated inference library/backend and the helper before the outer app.
# This is required for ad-hoc development builds as well as Developer ID releases.
NESTED_ID="${SIGN_ID:--}"
NESTED_TIMESTAMP="--timestamp"
NESTED_OPTIONS="runtime"
# Ad-hoc signatures have no Team ID, so a hardened helper cannot validate its own dylibs.
# Development helpers run without hardened runtime; Developer ID release helpers retain it.
if [[ "${NESTED_ID}" == "-" ]]; then
    NESTED_TIMESTAMP="--timestamp=none"
    NESTED_OPTIONS="0"
fi
if [[ -d "${BUNDLE}/Contents/Frameworks" ]]; then
    while IFS= read -r -d '' nested; do
        codesign --force --sign "${NESTED_ID}" --options "${NESTED_OPTIONS}" "${NESTED_TIMESTAMP}" "${nested}"
    done < <(find "${BUNDLE}/Contents/Frameworks" -type f \( -name '*.dylib' -o -name '*.so' \) -print0)
    while IFS= read -r -d '' nested; do
        codesign --force --sign "${NESTED_ID}" --options "${NESTED_OPTIONS}" "${NESTED_TIMESTAMP}" "${nested}"
    done < <(find "${BUNDLE}/Contents/Frameworks" -depth -type d -name '*.framework' -print0)
fi
if [[ -f "${BUNDLE}/Contents/MacOS/murmur-text-server" ]]; then
    codesign --force --sign "${NESTED_ID}" --options "${NESTED_OPTIONS}" "${NESTED_TIMESTAMP}" \
        "${BUNDLE}/Contents/MacOS/murmur-text-server"
fi

if [[ -n "${SIGN_ID}" && "${SIGN_ID}" != "-" ]]; then
    echo "Using Developer ID identity: ${SIGN_ID}"
    echo "Signing with Hardened Runtime and secure timestamp..."

    # Sign main application bundle
    codesign --force --sign "${SIGN_ID}" \
        --requirements '=designated => identifier "ai.pivotstudio.murmur"' \
        --entitlements "${ENTITLEMENTS}" \
        --options runtime \
        --timestamp \
        "${BUNDLE}"

    echo "Verifying signature..."
    codesign --verify --deep --strict --verbose=2 "${BUNDLE}"
    echo "Successfully signed with Developer ID Application: ${SIGN_ID}"
else
    echo "----------------------------------------------------------------------"
    echo " NOTICE: No Apple Developer ID Application certificate found."
    echo " Falling back to ad-hoc signature ('-') for DEVELOPMENT testing."
    echo " This build will work locally but will trigger Gatekeeper on other Macs."
    echo "----------------------------------------------------------------------"
    codesign --force --sign "-" \
        --requirements '=designated => identifier "ai.pivotstudio.murmur"' \
        --entitlements "${ENTITLEMENTS}" \
        --options runtime \
        --timestamp=none \
        "${BUNDLE}"
    echo "Ad-hoc signature complete: ${BUNDLE}"
fi
