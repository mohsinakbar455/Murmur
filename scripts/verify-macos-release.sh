#!/usr/bin/env bash
# Validate the artifact users receive. Development acceptance is distinct from public distribution.
set -euo pipefail

VERSION="${1:-1.0.0}"
APPNAME="Murmur.app"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="${HOME}/Library/Caches/MurmurBuild/${APPNAME}"
DMG_PATH="${REPO_ROOT}/release/macos/Murmur-${VERSION}.dmg"
MODE="${MURMUR_RELEASE_MODE:-development}"
if [[ "${MODE}" != "development" && "${MODE}" != "public" ]]; then
    echo "Error: MURMUR_RELEASE_MODE must be development or public." >&2
    exit 1
fi
if [[ ! -d "${BUNDLE}" || ! -f "${DMG_PATH}" ]]; then
    echo "Error: Both the staged app and DMG are required: ${BUNDLE}, ${DMG_PATH}" >&2
    exit 1
fi

MOUNT_POINT="$(mktemp -d -t murmur-verify-XXXXXX)"
MOUNTED=false
cleanup() {
    if [[ "${MOUNTED}" == "true" ]]; then hdiutil detach "${MOUNT_POINT}" -force >/dev/null; fi
    rmdir "${MOUNT_POINT}" 2>/dev/null || true
}
trap cleanup EXIT
hdiutil verify "${DMG_PATH}"
hdiutil attach "${DMG_PATH}" -mountpoint "${MOUNT_POINT}" -nobrowse -noautoopen -readonly
MOUNTED=true
DELIVERED="${MOUNT_POINT}/${APPNAME}"
if [[ ! -d "${DELIVERED}" ]]; then
    echo "Error: ${APPNAME} is missing from the DMG." >&2
    exit 1
fi
if [[ ! -L "${MOUNT_POINT}/Applications" || "$(readlink "${MOUNT_POINT}/Applications")" != "/Applications" ]]; then
    echo "Error: The DMG must contain an Applications symlink targeting /Applications." >&2
    exit 1
fi

test -x "${DELIVERED}/Contents/MacOS/Murmur"
test -x "${DELIVERED}/Contents/MacOS/murmur-text-server"
test -f "${DELIVERED}/Contents/Resources/TextRuntime/provenance.json"
codesign --verify --deep --strict "${DELIVERED}"
codesign --verify --deep --strict "${BUNDLE}"
cmp "${BUNDLE}/Contents/MacOS/Murmur" "${DELIVERED}/Contents/MacOS/Murmur"
cmp "${BUNDLE}/Contents/MacOS/murmur-text-server" "${DELIVERED}/Contents/MacOS/murmur-text-server"

# Inspect the delivered image, not merely the staging tree. Weight files stay in Application Support.
python3 - "${DELIVERED}" <<'PY'
from pathlib import Path
import json
import re
import subprocess
import sys

bundle = Path(sys.argv[1])
model_suffixes = {'.gguf', '.ggml', '.safetensors', '.onnx', '.mlmodel', '.mlpackage', '.mlmodelc', '.pt', '.pth'}
macho_magic = {bytes.fromhex(x) for x in ('feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}
failures = []
binary_count = 0
for path in bundle.rglob('*'):
    if path.suffix.lower() in model_suffixes or path.name == 'weight.bin' or (path.name.startswith('ggml-') and path.suffix == '.bin'):
        failures.append('Embedded model weights: ' + str(path.relative_to(bundle)))
    if not path.is_file():
        continue
    with path.open('rb') as stream:
        magic = stream.read(4)
    if magic == b'GGUF':
        failures.append('Embedded GGUF payload: ' + str(path.relative_to(bundle)))
    if magic not in macho_magic:
        continue
    binary_count += 1
    output = subprocess.check_output(['otool', '-L', str(path)], text=True)
    for line in output.splitlines()[1:]:
        dependency = line.strip().split(' (compatibility')[0]
        if dependency.startswith(('/opt/homebrew/', '/usr/local/', '/Users/', '/private/tmp/', '/tmp/')):
            failures.append(path.name + ' links a developer-machine dependency: ' + dependency)
        elif dependency.startswith('/') and not dependency.startswith(('/System/Library/', '/usr/lib/')):
            failures.append(path.name + ' links an unbundled absolute dependency: ' + dependency)
    load_commands = subprocess.check_output(['otool', '-l', str(path)], text=True)
    for search_path in re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset', load_commands):
        if search_path.startswith('/') and not search_path.startswith(('/System/Library/', '/usr/lib/')):
            failures.append(path.name + ' has a developer-machine runtime search path: ' + search_path)
provenance = json.loads((bundle / 'Contents/Resources/TextRuntime/provenance.json').read_text())
if provenance.get('modelWeightsIncluded') is not False:
    failures.append('Writing runtime provenance does not assert an asset-free distribution.')
if failures:
    raise SystemExit('\n'.join(failures))
print(f'Checked {binary_count} Mach-O files: no embedded weights or developer-machine linkage.')
PY

# This launches only --version, never the app or inference, with no Homebrew search path.
env -i PATH=/usr/bin:/bin HOME="${HOME}" TMPDIR="${TMPDIR:-/tmp}" \
    GGML_BACKEND_PATH="${DELIVERED}/Contents/Frameworks/TextRuntime" \
    "${DELIVERED}/Contents/MacOS/murmur-text-server" --version

SIGNATURE=$(codesign -dvvv "${DELIVERED}" 2>&1)
if [[ "${SIGNATURE}" == *"Signature=adhoc"* ]]; then
    if [[ "${MODE}" == "public" ]]; then
        echo "Error: Public release rejected: the app is ad-hoc signed." >&2
        exit 1
    fi
    if spctl --assess --type execute --verbose=2 "${DELIVERED}"; then
        echo "DEVELOPMENT verification passed. This machine accepts the app; public distribution is not certified."
    else
        echo "DEVELOPMENT verification passed. Gatekeeper rejects this ad-hoc app; it is not a public release."
    fi
elif [[ "${SIGNATURE}" == *"Authority=Developer ID Application:"* ]]; then
    # A signed build never receives the ad-hoc exception, even in development mode.
    spctl --assess --type execute --verbose=2 "${DELIVERED}"
    codesign --verify --strict "${DMG_PATH}"
    xcrun stapler validate "${DMG_PATH}"
    spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG_PATH}"
    echo "DISTRIBUTION verification passed: Developer ID, Gatekeeper, and stapled DMG ticket."
else
    echo "Error: Unsupported app signature. Use explicit ad-hoc development or Developer ID distribution signing." >&2
    exit 1
fi
