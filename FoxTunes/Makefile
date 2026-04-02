APP_NAME := FoxTunes
BUNDLE_ID := com.foxtunes.app
BUILD_DIR := .build/release
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR := /Applications

.PHONY: build bundle install uninstall clean test run

build:
	swift build -c release

bundle: build
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(BUILD_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp FoxTunes/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@cp FoxTunes/FoxTunes.entitlements "$(APP_BUNDLE)/Contents/Resources/"
	@codesign --force --sign - \
		--entitlements FoxTunes/FoxTunes.entitlements \
		"$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

install: bundle
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

uninstall:
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Removed $(INSTALL_DIR)/$(APP_NAME).app"

clean:
	swift package clean
	@rm -rf "$(APP_BUNDLE)"

test:
	swift test

run: bundle
	@open "$(APP_BUNDLE)"
