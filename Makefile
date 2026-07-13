PROJECT := powertoys.xcodeproj
SCHEME := powertoys
DERIVED_DATA ?= /tmp/macpowertoys-derived
XCODEBUILD := taskpolicy -c utility nice -n 10 xcodebuild -project $(PROJECT) -scheme $(SCHEME) -jobs 4 -derivedDataPath $(DERIVED_DATA)

build:
	$(XCODEBUILD) -configuration Release CODE_SIGNING_ALLOWED=NO build

build-for-testing:
	$(XCODEBUILD) -configuration Debug CODE_SIGNING_ALLOWED=NO build-for-testing

test:
	$(XCODEBUILD) test -destination 'platform=macOS' -only-testing:powertoysTests -skip-testing:powertoysUITests

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
