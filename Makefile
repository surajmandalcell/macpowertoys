APP := /Applications/PowerToys.app
XCB := taskpolicy -c utility nice -n 10 xcodebuild -project powertoys.xcodeproj -scheme powertoys -jobs 4 -quiet

build:
	$(XCB) -configuration Release build

test:
	$(XCB) test -destination 'platform=macOS' -only-testing:powertoysTests -skip-testing:powertoysUITests

install: build
	osascript -e 'tell application "powertoys" to quit' || true
	sleep 3
	rm -rf $(APP)
	ditto "$$(xcodebuild -project powertoys.xcodeproj -scheme powertoys -configuration Release -showBuildSettings 2>/dev/null | grep -m1 BUILT_PRODUCTS_DIR | awk '{print $$3}')/powertoys.app" $(APP)
	open $(APP)

.PHONY: build test install
