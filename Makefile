EXEC     := Murmur
CONFIG   := debug

# Current Command Line Tools can expose the macOS 27 SDK without the SwiftUI
# macro plugin it requires. Its macOS 26.5 SDK builds Murmur with Swift 6.4.
# Full Xcode uses its selected SDK. An explicit SDKROOT always takes priority.
ifndef SDKROOT
ifeq ($(shell xcode-select -p 2>/dev/null),/Library/Developer/CommandLineTools)
ifneq ($(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk),)
SDKROOT := /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
endif
endif
SDKROOT ?= $(shell xcrun --sdk macosx --show-sdk-path)
endif
export SDKROOT

## Build products live OUTSIDE this directory, for the same reason the .app does.
##
## ~/Desktop is iCloud/file-provider synced, and the provider mutates files inside
## .build while the compiler is using them — producing "input file was modified during
## the build" on random object files, and occasionally a wedged swift-frontend stuck at
## 0% CPU. Moving the scratch path to ~/Library/Caches (never synced) removes the race.
SCRATCH  := $(HOME)/Library/Caches/MurmurBuild/scratch
BUILD    := $(SCRATCH)/$(CONFIG)/$(EXEC)

## The bundle is assembled and signed OUTSIDE this directory on purpose.
##
## This tree lives under ~/Desktop, which is iCloud/file-provider synced. The provider
## stamps com.apple.FinderInfo onto files inside an .app faster than we can strip them,
## and codesign hard-refuses anything carrying them ("resource fork, Finder information,
## or similar detritus not allowed"). `xattr -cr` immediately before signing is not enough
STAGE    := $(HOME)/Library/Caches/MurmurBuild
APPNAME  := Murmur.app
BUNDLE   := $(STAGE)/$(APPNAME)
CONTENTS := $(BUNDLE)/Contents

## TCC keys the Accessibility grant to the code signature, so an ad-hoc signature — which
## changes on every build — makes the user re-grant after every `make`. Signing with a
## stable Developer ID keeps the identity constant and the grant sticky. Falls back to
## ad-hoc ("-") on a machine without the cert.
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
             | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := -
endif

.PHONY: all build app run install clean icon test

all: app

TEST_PLUGIN := $(wildcard /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib)
ifneq ($(TEST_PLUGIN),)
TEST_FLAGS := -Xswiftc -load-plugin-library -Xswiftc $(TEST_PLUGIN)
endif

ICON_TARGET       := $(shell uname -m)-apple-macosx$(shell sw_vers -productVersion)
ICON_MODULE_CACHE := $(TMPDIR)murmur-icon-module-cache

test:
	swift test --scratch-path "$(SCRATCH)" $(TEST_FLAGS)

build:
	swift build -c $(CONFIG) --scratch-path "$(SCRATCH)"

## Regenerates AppIcon.icns from Tools/makeicon.swift. Not a dependency of `app` — the
## icon rarely changes and rendering 10 PNGs on every build is wasted time.
icon:
	@env -u SDKROOT xcrun swift \
		-target "$(ICON_TARGET)" \
		-module-cache-path "$(ICON_MODULE_CACHE)" \
		Tools/makeicon.swift
	@echo "wrote Resources/AppIcon.icns"

## Assemble a real .app bundle. TCC (microphone + Accessibility) keys on bundle identity
## and code signature, so the raw SwiftPM binary can't be used directly.
app: build
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	@cp $(BUILD) "$(CONTENTS)/MacOS/$(EXEC)"
	@cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(CONTENTS)/Resources/"; fi
	@for bundle in "$(SCRATCH)/$(CONFIG)/"*.bundle; do \
		if [ -d "$$bundle" ] && ! echo "$$bundle" | grep -q 'Tests.bundle'; then \
			cp -R "$$bundle" "$(CONTENTS)/Resources/"; \
		fi; \
	done
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@bash scripts/bundle-text-runtime.sh "$(BUNDLE)"
	@# Belt and braces: the staging dir isn't synced, but the copied binary can still carry
	@# xattrs inherited from the synced .build directory.
	@xattr -cr "$(BUNDLE)"
	@bash scripts/sign-macos.sh "$(BUNDLE)" "$(SIGN_ID)"
	@echo "built $(BUNDLE)  [signed: $(SIGN_ID)]"

## Install the Murmur executable and app bundle.
run: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@open "$(BUNDLE)"

## Ad-hoc signatures change on every rebuild, which resets the Accessibility grant.
## Installing to /Applications keeps the path stable and makes re-granting a one-click fix.
install: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@# $(BUNDLE) is an absolute staging path — the destination must use $(APPNAME) alone.
	@rm -rf "/Applications/$(APPNAME)"
	@cp -R "$(BUNDLE)" "/Applications/$(APPNAME)"
	@open "/Applications/$(APPNAME)"
	@echo "installed to /Applications/$(APPNAME)"

clean:
	@rm -rf .build "$(STAGE)" "$(SCRATCH)"
