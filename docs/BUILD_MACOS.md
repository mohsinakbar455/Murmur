# Building Murmur on macOS

This guide covers building, testing, signing, notarizing, and packaging Murmur on macOS.

---

## Prerequisites

- **macOS**: macOS 26.0 or higher on Apple Silicon.
- **Xcode Command Line Tools / Swift**: Swift 6.2 or newer with a macOS 26 SDK.
  Install via:
  ```bash
  xcode-select --install
  ```
- **SDK selection**: On Command Line Tools installations that expose macOS 27 without its SwiftUI macro plugin, the Makefile uses the installed macOS 26.5 SDK. Full Xcode uses its selected SDK. Set `SDKROOT` explicitly to override this choice.
- **File System Notice**:
  The build scratch path and staging directory are deliberately placed in `~/Library/Caches/MurmurBuild/` outside any iCloud-synced or Desktop folders to prevent filesystem race conditions mid-compile.

---

## Quick Start (Local Development)

To run the local unit and contract tests:
```bash
make test
```

To build the debug application bundle in `~/Library/Caches/MurmurBuild/Murmur.app`:
```bash
make app
```

To install and launch the local build into `/Applications`:
```bash
make install
```

---

## Release Build & DMG Packaging

Murmur includes automated release scripts in `scripts/`:

### 1. Build Release `.app`
Compiles with optimizations (`-c release`) and packages a pristine bundle:
```bash
./scripts/build-macos-release.sh 1.1.0
```

### 2. Sign with Developer ID or Ad-Hoc
Signs the bundle, embedded frameworks, and designated requirements with Hardened Runtime enabled:
```bash
./scripts/sign-macos.sh
```
*Note: If no Developer ID Application certificate is present in Keychain, this script automatically falls back to ad-hoc (`-`) for local testing.*

### 3. Notarize with Apple Notary Service
Submits the application to Apple via `xcrun notarytool` and staples the ticket:
```bash
./scripts/notarize-macos.sh ~/Library/Caches/MurmurBuild/Murmur.app
```
*Credentials can be provided via `NOTARY_PROFILE` or environment variables `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD`. If not configured, notarization is gracefully skipped in DEVELOPMENT mode.*

### 4. Create Distribution DMG
Generates a polished Apple Disk Image with drag-and-drop to `/Applications`:
```bash
./scripts/create-dmg.sh 1.1.0
```
Output:
```
release/macos/Murmur-1.1.0.dmg
```

### 5. Verify Release
Performs complete bundle verification, codesign checks, and DMG mount tests:
```bash
./scripts/verify-macos-release.sh 1.1.0
```

---

## One-Step Master Release Command

To run the entire pipeline (tests, build, sign, notarize, DMG, verification, and checksums) in one command:
```bash
./scripts/release-macos.sh 1.1.0
```

The final disk image will be placed in `release/macos/Murmur-1.1.0.dmg`, and its SHA-256 hash will be recorded in `release/SHA256SUMS.txt`.
