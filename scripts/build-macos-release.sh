#!/usr/bin/env bash
# ==============================================================================
# build-macos-release.sh
# Builds Murmur in Release configuration and packages a clean .app bundle.
# ==============================================================================
set -euo pipefail

VERSION="${1:-1.0.0}"
EXEC="Murmur"
APPNAME="Murmur.app"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH="${HOME}/Library/Caches/MurmurBuild/scratch"
STAGE="${HOME}/Library/Caches/MurmurBuild"
BUNDLE="${STAGE}/${APPNAME}"
CONTENTS="${BUNDLE}/Contents"

echo "=========================================="
echo " Building Murmur macOS Release v${VERSION}"
echo "=========================================="

if [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk" ]]; then
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
fi

echo "--> [1/4] Compiling SwiftPM package (release configuration)..."
# Build outside iCloud synced tree to prevent "input file was modified during the build"
swift build -c release --scratch-path "${SCRATCH}"

BUILD_BINARY="${SCRATCH}/release/${EXEC}"
if [[ ! -f "${BUILD_BINARY}" ]]; then
    echo "Error: Compiled binary not found at ${BUILD_BINARY}" >&2
    exit 1
fi

echo "--> [2/4] Assembling .app bundle in ${BUNDLE}..."
rm -rf "${BUNDLE}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"

cp "${BUILD_BINARY}" "${CONTENTS}/MacOS/${EXEC}"
chmod +x "${CONTENTS}/MacOS/${EXEC}"

# Copy resources
cp "${REPO_ROOT}/Resources/Info.plist" "${CONTENTS}/Info.plist"
if [[ -f "${REPO_ROOT}/Resources/AppIcon.icns" ]]; then
    cp "${REPO_ROOT}/Resources/AppIcon.icns" "${CONTENTS}/Resources/"
fi
# Copy SwiftPM runtime resource bundles (excluding test bundles) so Bundle.module works on other Macs
for bundle in "${SCRATCH}/release/"*.bundle; do
    if [[ -d "${bundle}" && "${bundle}" != *Tests.bundle ]]; then
        cp -R "${bundle}" "${CONTENTS}/Resources/"
    fi
done
printf 'APPL????' > "${CONTENTS}/PkgInfo"

# The runtime is part of every distribution; weights remain an explicit in-app download.
bash "${REPO_ROOT}/scripts/bundle-text-runtime.sh" "${BUNDLE}"

# Inject release version into Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${CONTENTS}/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${VERSION}" "${CONTENTS}/Info.plist"

echo "--> [3/4] Cleaning quarantine and filesystem attributes..."
# Strip FinderInfo / resource fork metadata
xattr -cr "${BUNDLE}"

echo "--> [4/4] Verifying bundle structure..."
test -x "${CONTENTS}/MacOS/${EXEC}"
test -f "${CONTENTS}/Info.plist"
test -f "${CONTENTS}/PkgInfo"

echo "Successfully assembled: ${BUNDLE}"
