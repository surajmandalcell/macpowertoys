PROJECT := powertoys.xcodeproj
SCHEME := powertoys
TEST_SCHEME := powertoys-desktop-tests
DERIVED_DATA ?= /tmp/macpowertoys-derived
SOURCE_COMMIT := $(shell git rev-parse HEAD)
XCODEBUILD := taskpolicy -c utility nice -n 10 xcodebuild -project $(PROJECT) -jobs 4 -derivedDataPath $(DERIVED_DATA) MPT_SOURCE_COMMIT=$(SOURCE_COMMIT)
LOCAL_ENTITLEMENTS := $(abspath powertoys/Local.entitlements)
PREBUILT_APP ?=
ifeq ($(PREBUILT_APP),)
INSTALL_APP := $(DERIVED_DATA)/Build/Products/Release/MacPowerToys.app
INSTALL_BUILD := build
else
INSTALL_APP := $(PREBUILT_APP)
INSTALL_BUILD :=
endif

# Builds use the Apple Development certificate in this Mac's login keychain.
# ADHOC=1 is the explicit fallback for Macs without that identity.
SIGNING := CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=GF57JXJF5A CODE_SIGN_ENTITLEMENTS=$(LOCAL_ENTITLEMENTS) PROVISIONING_PROFILE_SPECIFIER=
ifeq ($(ADHOC),1)
SIGNING := CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS=$(LOCAL_ENTITLEMENTS)
endif

build:
	$(XCODEBUILD) -scheme $(SCHEME) -configuration Release $(SIGNING) build

build-for-testing:
	$(XCODEBUILD) -scheme $(TEST_SCHEME) -configuration Debug CODE_SIGNING_ALLOWED=NO build-for-testing

test:
	@test "$(TEST_SESSION)" = "isolated" || (echo "Xcode tests launch MacPowerToys on the desktop. Use make build-for-testing here; run TEST_SESSION=isolated make test in a separate macOS account or VM." && exit 1)
	$(XCODEBUILD) -scheme $(TEST_SCHEME) test -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:powertoysTests -skip-testing:powertoysUITests $(SIGNING)

raycast-assets:
	sh raycast/sync-icons.sh

raycast: raycast-assets
	npm --prefix raycast ci
	npm --prefix raycast run lint
	npm --prefix raycast run build

raycast-install: raycast
	sh raycast/reload-local.sh

install-preflight:
	@test "$(ALLOW_INSTALL)" = "1" || (echo "Refusing to install. Re-run with ALLOW_INSTALL=1 after all Cloud Sync transfers finish." && exit 1)
	@test -z "$$(git status --porcelain)" || (echo "Refusing to install from a dirty worktree. Commit the complete source state first." && exit 1)

install: raycast-assets install-preflight raycast-install $(INSTALL_BUILD)
	@test -z "$$(git status --porcelain)" || (echo "Refusing to install because the worktree changed during the build." && exit 1)
	@CURRENT_COMMIT="$$(git rev-parse HEAD)"; BUILT_COMMIT="$$(plutil -extract MPTSourceCommit raw "$(INSTALL_APP)/Contents/Info.plist" 2>/dev/null)"; test "$(SOURCE_COMMIT)" = "$$CURRENT_COMMIT" && test "$$BUILT_COMMIT" = "$$CURRENT_COMMIT" || (echo "Refusing to install a stale build. Re-run make install from the current HEAD." && exit 1)
	@codesign --verify --deep --strict "$(INSTALL_APP)"
	@test "$$(codesign -dv --verbose=4 "$(INSTALL_APP)" 2>&1 | sed -n 's/^TeamIdentifier=//p')" = "GF57JXJF5A" || (echo "Refusing to install an app without the configured signing team." && exit 1)
	@HELPER="$(INSTALL_APP)/Contents/Library/LoginItems/MacPowerToysNetHelper.app"; test "$$(plutil -extract MPTSourceCommit raw "$$HELPER/Contents/Info.plist" 2>/dev/null)" = "$(SOURCE_COMMIT)" && test "$$(codesign -dv --verbose=4 "$$HELPER" 2>&1 | sed -n 's/^TeamIdentifier=//p')" = "GF57JXJF5A" || (echo "Refusing to install a stale or differently signed helper." && exit 1)
	@! pgrep -f '^/Applications/MacPowerToys.app/Contents/MacOS/MacPowerToys$$' >/dev/null || (echo "Refusing to replace the running installed MacPowerToys app." && exit 1)
	rm -rf /Applications/MacPowerToys.app
	ditto "$(INSTALL_APP)" /Applications/MacPowerToys.app

.PHONY: build build-for-testing test raycast-assets raycast raycast-install install install-preflight
