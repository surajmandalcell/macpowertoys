PROJECT := powertoys.xcodeproj
SCHEME := powertoys
TEST_SCHEME := powertoys-desktop-tests
TEST_ARGS ?= -only-testing:powertoysTests
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

# Every build signs the app and helper with Developer ID, the hardened runtime, and no get-task-allow, so the
# signature (and every privacy grant macOS keeps for it) never changes between installs.
# Tests keep the Apple Development identity. ADHOC=1 is the fallback for Macs without these identities.
SIGNING := CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM=GF57JXJF5A CODE_SIGN_ENTITLEMENTS=$(LOCAL_ENTITLEMENTS) PROVISIONING_PROFILE_SPECIFIER= ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
TEST_SIGNING := CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=GF57JXJF5A CODE_SIGN_ENTITLEMENTS=$(LOCAL_ENTITLEMENTS) PROVISIONING_PROFILE_SPECIFIER=
ifeq ($(ADHOC),1)
SIGNING := CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS=$(LOCAL_ENTITLEMENTS)
TEST_SIGNING := $(SIGNING)
endif
# NOTARIZE=1 also notarizes and staples before install, so macOS offers Touch ID for the helper install.
# It needs the notarytool profile the owner stores once with
# `xcrun notarytool store-credentials MacPowerToysNotary`.
NOTARY_PROFILE := MacPowerToysNotary
NOTARY_ZIP := $(DERIVED_DATA)/MacPowerToys-notarize.zip

build:
	$(XCODEBUILD) -scheme $(SCHEME) -configuration Release $(SIGNING) build

build-for-testing:
	$(XCODEBUILD) -scheme $(TEST_SCHEME) -configuration Debug CODE_SIGNING_ALLOWED=NO build-for-testing

test:
	@test "$(TEST_SESSION)" = "isolated" || (echo "Xcode tests launch MacPowerToys on the desktop. Use make build-for-testing here; run TEST_SESSION=isolated make test in a separate macOS account or VM." && exit 1)
	$(XCODEBUILD) -scheme $(TEST_SCHEME) test -destination 'platform=macOS' -parallel-testing-enabled NO $(TEST_ARGS) -skip-testing:powertoysUITests $(TEST_SIGNING)

raycast-assets:
	sh raycast/sync-icons.sh

raycast: raycast-assets
	npm --prefix raycast ci
	npm --prefix raycast run lint
	npm --prefix raycast run build

raycast-install: raycast
	sh raycast/reload-local.sh

install-preflight:
	@test "$(ALLOW_INSTALL)" = "1" || (echo "Refusing to install. Re-run with ALLOW_INSTALL=1 after all RSync UI transfers finish." && exit 1)
	@test -z "$$(git status --porcelain)" || (echo "Refusing to install from a dirty worktree. Commit the complete source state first." && exit 1)
ifeq ($(NOTARIZE),1)
	@xcrun notarytool history --keychain-profile $(NOTARY_PROFILE) >/dev/null 2>&1 || (echo "No notary profile. Run once: xcrun notarytool store-credentials $(NOTARY_PROFILE)" && exit 1)
endif

verify-app:
	@test -z "$$(git status --porcelain)" || (echo "Refusing to install because the worktree changed during the build." && exit 1)
	@CURRENT_COMMIT="$$(git rev-parse HEAD)"; BUILT_COMMIT="$$(plutil -extract MPTSourceCommit raw "$(INSTALL_APP)/Contents/Info.plist" 2>/dev/null)"; test "$(SOURCE_COMMIT)" = "$$CURRENT_COMMIT" && test "$$BUILT_COMMIT" = "$$CURRENT_COMMIT" || (echo "Refusing to install a stale build. Re-run make install from the current HEAD." && exit 1)
	@codesign --verify --deep --strict "$(INSTALL_APP)"
	@test "$$(codesign -dv --verbose=4 "$(INSTALL_APP)" 2>&1 | sed -n 's/^TeamIdentifier=//p')" = "GF57JXJF5A" || (echo "Refusing to install an app without the configured signing team." && exit 1)
	@HELPER="$(INSTALL_APP)/Contents/Library/LaunchServices/com.surajmandal.macpowertoys.helper"; launchctl plist __TEXT,__info_plist "$$HELPER" 2>/dev/null | grep -q "\"MPTSourceCommit\" = \"$(SOURCE_COMMIT)\"" && codesign --verify --strict -R='identifier "com.surajmandal.macpowertoys.helper" and anchor apple generic and certificate leaf[subject.OU] = "GF57JXJF5A"' "$$HELPER" && codesign --verify --strict -R='identifier "com.surajmandal.macpowertoys" and anchor apple generic and certificate leaf[subject.OU] = "GF57JXJF5A"' "$(INSTALL_APP)" || (echo "Refusing to install a stale helper or one whose signature does not match SMPrivilegedExecutables and SMAuthorizedClients." && exit 1)
ifneq ($(ADHOC),1)
	@codesign -dv --verbose=4 "$(INSTALL_APP)" 2>&1 | grep -q '^Authority=Developer ID Application' || (echo "Refusing to install an app without a Developer ID signature; a new identity drops every privacy grant." && exit 1)
endif

notarize-app:
	ditto -c -k --keepParent "$(INSTALL_APP)" "$(NOTARY_ZIP)"
	xcrun notarytool submit "$(NOTARY_ZIP)" --keychain-profile $(NOTARY_PROFILE) --wait 2>&1 | tee "$(NOTARY_ZIP).log"; grep -q 'status: Accepted' "$(NOTARY_ZIP).log" || (echo "Notarization was not accepted. Read the log with: xcrun notarytool log <id> --keychain-profile $(NOTARY_PROFILE)" && exit 1)
	xcrun stapler staple "$(INSTALL_APP)"
	xcrun stapler validate "$(INSTALL_APP)"
	rm -f "$(NOTARY_ZIP)" "$(NOTARY_ZIP).log"

install: raycast-assets install-preflight raycast-install $(INSTALL_BUILD) verify-app $(if $(filter 1,$(NOTARIZE)),notarize-app)
	@! pgrep -f '^/Applications/MacPowerToys.app/Contents/MacOS/MacPowerToys$$' >/dev/null || (echo "Refusing to replace the running installed MacPowerToys app." && exit 1)
	rm -rf /Applications/MacPowerToys.app
	ditto "$(INSTALL_APP)" /Applications/MacPowerToys.app

# make release: a notarized, stapled MacPowerToys-<version>.dmg and its .sha256 in RELEASE_DIR, built from a clean HEAD.
RELEASE_DIR ?= $(CURDIR)/release
DMG_STAGE := $(DERIVED_DATA)/dmg-stage

release-preflight:
	@test "$(ADHOC)" != "1" || (echo "A release needs the Developer ID signature, not ADHOC=1." && exit 1)
	@test -z "$(PREBUILT_APP)" || (echo "A release builds its own app; drop PREBUILT_APP." && exit 1)
	@test -z "$$(git status --porcelain)" || (echo "Refusing to release from a dirty worktree. Commit the complete source state first." && exit 1)
	@xcrun notarytool history --keychain-profile $(NOTARY_PROFILE) >/dev/null 2>&1 || (echo "No notary profile. Run once: xcrun notarytool store-credentials $(NOTARY_PROFILE)" && exit 1)

release: release-preflight build verify-app notarize-app
	@set -e; \
	VERSION="$$(plutil -extract CFBundleShortVersionString raw "$(INSTALL_APP)/Contents/Info.plist")"; \
	DMG="$(RELEASE_DIR)/MacPowerToys-$$VERSION.dmg"; \
	IDENTITY="$$(codesign -dv --verbose=4 "$(INSTALL_APP)" 2>&1 | sed -n 's/^Authority=\(Developer ID Application.*\)/\1/p')"; \
	rm -rf "$(DMG_STAGE)"; rm -f "$$DMG" "$$DMG.sha256"; mkdir -p "$(DMG_STAGE)" "$(RELEASE_DIR)"; \
	ditto "$(INSTALL_APP)" "$(DMG_STAGE)/MacPowerToys.app"; \
	ln -s /Applications "$(DMG_STAGE)/Applications"; \
	hdiutil create -volname MacPowerToys -srcfolder "$(DMG_STAGE)" -format UDZO -ov "$$DMG"; \
	rm -rf "$(DMG_STAGE)"; \
	codesign --sign "$$IDENTITY" --timestamp "$$DMG"; \
	xcrun notarytool submit "$$DMG" --keychain-profile $(NOTARY_PROFILE) --wait 2>&1 | tee "$$DMG.log"; \
	grep -q 'status: Accepted' "$$DMG.log" || (echo "The DMG was not notarized. Read the log with: xcrun notarytool log <id> --keychain-profile $(NOTARY_PROFILE)" && exit 1); \
	rm -f "$$DMG.log"; \
	xcrun stapler staple "$$DMG"; \
	xcrun stapler validate "$$DMG"; \
	spctl -a -vv -t open --context context:primary-signature "$$DMG"; \
	cd "$(RELEASE_DIR)" && shasum -a 256 "MacPowerToys-$$VERSION.dmg" | tee "MacPowerToys-$$VERSION.dmg.sha256"

.PHONY: build build-for-testing test raycast-assets raycast raycast-install install install-preflight verify-app notarize-app release release-preflight
