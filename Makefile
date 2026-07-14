PROJECT := powertoys.xcodeproj
SCHEME := powertoys
DERIVED_DATA ?= /tmp/macpowertoys-derived
XCODEBUILD := taskpolicy -c utility nice -n 10 xcodebuild -project $(PROJECT) -scheme $(SCHEME) -jobs 4 -derivedDataPath $(DERIVED_DATA)

# Default builds use a valid ad-hoc signature. SIGNED=1 uses the Apple
# Development certificate already installed in this Mac's login keychain.
SIGNING := CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS=
ifeq ($(SIGNED),1)
SIGNING := CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=GF57JXJF5A CODE_SIGN_ENTITLEMENTS= PROVISIONING_PROFILE_SPECIFIER=
endif

build:
	$(XCODEBUILD) -configuration Release $(SIGNING) build

build-for-testing:
	$(XCODEBUILD) -configuration Debug CODE_SIGNING_ALLOWED=NO build-for-testing

test:
	$(XCODEBUILD) test -destination 'platform=macOS' -only-testing:powertoysTests -skip-testing:powertoysUITests CODE_SIGNING_ALLOWED=NO

raycast:
	npm --prefix raycast ci
	npm --prefix raycast run lint
	npm --prefix raycast run build

install: build
	@test "$(ALLOW_INSTALL)" = "1" || (echo "Refusing to install. Re-run with ALLOW_INSTALL=1 after all Cloud Sync transfers finish." && exit 1)
	@! pgrep -x MacPowerToys >/dev/null || (echo "Refusing to replace a running MacPowerToys instance." && exit 1)
	rm -rf /Applications/MacPowerToys.app
	ditto "$(DERIVED_DATA)/Build/Products/Release/MacPowerToys.app" /Applications/MacPowerToys.app
	open /Applications/MacPowerToys.app

.PHONY: build build-for-testing test raycast install
