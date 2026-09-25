PROJECT := powertoys.xcodeproj
SCHEME := powertoys
TEST_SCHEME := powertoys-desktop-tests
DERIVED_DATA ?= /tmp/macpowertoys-derived
SOURCE_COMMIT := $(shell git rev-parse HEAD)
XCODEBUILD := taskpolicy -c utility nice -n 10 xcodebuild -project $(PROJECT) -jobs 4 -derivedDataPath $(DERIVED_DATA) MPT_SOURCE_COMMIT=$(SOURCE_COMMIT)
LOCAL_ENTITLEMENTS := $(abspath powertoys/Local.entitlements)

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

install: raycast-assets install-preflight raycast-install build
	@test -z "$$(git status --porcelain)" || (echo "Refusing to install because the worktree changed during the build." && exit 1)
	@CURRENT_COMMIT="$$(git rev-parse HEAD)"; BUILT_COMMIT="$$(plutil -extract MPTSourceCommit raw "$(DERIVED_DATA)/Build/Products/Release/MacPowerToys.app/Contents/Info.plist" 2>/dev/null)"; test "$(SOURCE_COMMIT)" = "$$CURRENT_COMMIT" && test "$$BUILT_COMMIT" = "$$CURRENT_COMMIT" || (echo "Refusing to install a stale build. Re-run make install from the current HEAD." && exit 1)
	@! pgrep -f '^/Applications/MacPowerToys.app/Contents/MacOS/MacPowerToys$$' >/dev/null || (echo "Refusing to replace the running installed MacPowerToys app." && exit 1)
	rm -rf /Applications/MacPowerToys.app
	ditto "$(DERIVED_DATA)/Build/Products/Release/MacPowerToys.app" /Applications/MacPowerToys.app

.PHONY: build build-for-testing test raycast-assets raycast raycast-install install install-preflight
