#!/usr/bin/env bash
# Developer build step only: package a pinned inference engine, never model weights.
# No Homebrew installation or dependency lookup occurs on an end user's Mac.
set -euo pipefail
TARGET_BUNDLE="${1:?Usage: bundle-text-runtime.sh /path/to/Murmur.app}"
python3 - "${TARGET_BUNDLE}" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import tarfile
import urllib.request

TAG = 'b11146'
COMMIT = '7fe450e19305b828c199d602c23a8337aaa1f03b'
ARTIFACTS = {
    'arm64': '1ad3f9eff80edb9dbef4259ad564d1720612ef7eea48fa4afed0e54f5f3d5711',
    'x86_64': '305f0e3a17d2c01eb205cd0a62128357f1ec3b55329cb084d94e5ec0115d7a3b',
}
machine = platform.machine()
if machine not in ARTIFACTS:
    raise SystemExit('Unsupported writing runtime architecture: ' + machine)
architecture = 'arm64' if machine == 'arm64' else 'x64'
name = f'llama-{TAG}-bin-macos-{architecture}.tar.gz'
url = f'https://github.com/ggml-org/llama.cpp/releases/download/{TAG}/{name}'
cache = Path(os.environ.get('MURMUR_TEXT_RUNTIME_CACHE', f'/tmp/murmur-text-runtime-{TAG}-{architecture}'))
cache.mkdir(parents=True, exist_ok=True)
archive = cache / name
expected = ARTIFACTS[machine]

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

if not archive.exists() or digest(archive) != expected:
    print(f'Downloading pinned writing runtime {TAG} ({architecture}); no model weights.', flush=True)
    temporary = archive.with_suffix('.download')
    with urllib.request.urlopen(url, timeout=120) as response, temporary.open('wb') as target:
        shutil.copyfileobj(response, target)
    if digest(temporary) != expected:
        temporary.unlink(missing_ok=True)
        raise SystemExit('Writing runtime archive failed its SHA-256 check.')
    temporary.replace(archive)

source = cache / 'extracted'
if not (source / '.verified-archive').exists():
    if source.exists():
        shutil.rmtree(source)
    source.mkdir()
    with tarfile.open(archive) as package:
        # The download is pinned, but also reject escaping paths on Python versions without data_filter.
        for member in package.getmembers():
            path = Path(member.name)
            if path.is_absolute() or '..' in path.parts:
                raise SystemExit('Unsafe path in writing runtime archive.')
        if hasattr(tarfile, 'data_filter'):
            package.extractall(source, filter='data')
        else:
            package.extractall(source)
    (source / '.verified-archive').write_text(expected)

executables = list(source.rglob('llama-server'))
if len(executables) != 1:
    raise SystemExit('Pinned runtime archive does not contain exactly one llama-server.')
original_executable = executables[0].resolve()
bundle = Path(__import__('sys').argv[1]).resolve()
contents = bundle / 'Contents'
runtime = contents / 'Frameworks/TextRuntime'
runtime.mkdir(parents=True, exist_ok=True)
macos = contents / 'MacOS'
macos.mkdir(parents=True, exist_ok=True)
main = macos / 'murmur-text-server'
notices = contents / 'Resources/TextRuntime'
notices.mkdir(parents=True, exist_ok=True)

def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)

def rpaths(path):
    return re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset', run('otool', '-l', str(path)))

def dependencies(path):
    return [line.strip().split(' (compatibility')[0] for line in run('otool', '-L', str(path)).splitlines()[1:]]

def expand(value, loader):
    return Path(value.replace('@loader_path', str(loader.parent)).replace('@executable_path', str(original_executable.parent)))

def resolve(value, loader):
    if value.startswith('@rpath/'):
        candidates = [expand(p, loader) / value[len('@rpath/'):] for p in rpaths(loader) + rpaths(original_executable)]
        candidates += [loader.parent / Path(value).name]
        candidates += list(source.rglob(Path(value).name))
        for candidate in candidates:
            if candidate.exists():
                resolved = candidate.resolve()
                if resolved.is_relative_to(source.resolve()):
                    return resolved
    elif value.startswith('@'):
        candidate = expand(value, loader)
        if candidate.exists() and candidate.resolve().is_relative_to(source.resolve()):
            return candidate.resolve()
    elif Path(value).exists() and Path(value).resolve().is_relative_to(source.resolve()):
        return Path(value).resolve()
    raise SystemExit(f'Unbundled dependency {value} from {loader.name}. Refusing a machine-dependent app.')

mapping = {original_executable: main}
# Include dynamically loaded GGML backend libraries and their transitive dependencies.
for library in source.rglob('*'):
    if library.suffix in ('.dylib', '.so'):
        resolved = library.resolve()
        mapping[resolved] = runtime / resolved.name

queue = list(mapping)
edges = {}
while queue:
    original = queue.pop()
    edges[original] = []
    for dependency in dependencies(original):
        if dependency.startswith(('/usr/lib/', '/System/Library/')):
            continue
        resolved = resolve(dependency, original)
        # A dylib's own install name appears as the first otool entry.
        if resolved == original:
            continue
        edges[original].append((dependency, resolved))
        if resolved not in mapping:
            mapping[resolved] = runtime / resolved.name
            queue.append(resolved)

minimum_os = tuple(int(x) for x in plistlib.loads((contents / 'Info.plist').read_bytes())['LSMinimumSystemVersion'].split('.')[:2])
for original, destination in mapping.items():
    versions = re.findall(r'minos (\d+)\.(\d+)', run('vtool', '-show-build', str(original)))
    if any(tuple(map(int, version)) > minimum_os for version in versions):
        raise SystemExit(f'{original.name} requires a newer macOS than the app. Rebuild the pinned runtime for the supported OS.')
    shutil.copy2(original, destination)
    destination.chmod(0o755)
    # Relocation invalidates upstream signatures; the release signer signs all nested code afterward.
    subprocess.run(['codesign', '--remove-signature', str(destination)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if destination != main:
        run('install_name_tool', '-id', '@rpath/' + destination.name, str(destination))
    for old, resolved in edges[original]:
        replacement = ('@executable_path/../Frameworks/TextRuntime/' if destination == main else '@loader_path/') + mapping[resolved].name
        run('install_name_tool', '-change', old, replacement, str(destination))
    for old in rpaths(destination):
        run('install_name_tool', '-delete_rpath', old, str(destination))
    run('install_name_tool', '-add_rpath', '@executable_path/../Frameworks/TextRuntime' if destination == main else '@loader_path', str(destination))

for resource in source.rglob('*'):
    if resource.suffix in ('.metal', '.metallib'):
        shutil.copy2(resource, runtime / resource.name)
for license_file in source.rglob('*'):
    if license_file.is_file() and (license_file.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE'))):
        shutil.copy2(license_file, notices / ('-'.join(license_file.relative_to(source).parts)))
license_url = f'https://raw.githubusercontent.com/ggml-org/llama.cpp/{COMMIT}/LICENSE'
license_cache = cache / 'llama-LICENSE.txt'
if not license_cache.exists():
    with urllib.request.urlopen(license_url, timeout=30) as response:
        license_cache.write_bytes(response.read())
shutil.copy2(license_cache, notices / 'llama-LICENSE.txt')
(notices / 'provenance.json').write_text(json.dumps({
    'release': TAG, 'commit': COMMIT, 'archive': url, 'archiveSHA256': expected,
    'architecture': architecture, 'modelWeightsIncluded': False,
}, indent=2) + '\n')
for destination in mapping.values():
    if any('/opt/homebrew' in dep or '/usr/local' in dep for dep in dependencies(destination)):
        raise SystemExit('A developer-machine runtime dependency escaped relocation.')
# SwiftPM can embed an unused absolute PackageFrameworks path even in an otherwise standalone app.
# Retain system and bundle-relative searches; shipping builds must never search a developer's checkout.
app_info = plistlib.loads((contents / 'Info.plist').read_bytes())
app_executable = contents / 'MacOS' / app_info['CFBundleExecutable']
if app_executable.exists():
    for search_path in rpaths(app_executable):
        if search_path.startswith('/') and not search_path.startswith(('/System/Library/', '/usr/lib/')):
            run('install_name_tool', '-delete_rpath', search_path, str(app_executable))
print(f'Bundled writing runtime {TAG}: {len(mapping)} executables/libraries, no weights.', flush=True)
PY
