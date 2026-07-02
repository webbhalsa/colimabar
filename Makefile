PROJECT      := ColimaBar.xcodeproj
SCHEME       := ColimaBar
CONFIG       := Debug
BUILD_DIR    := build
APP          := $(BUILD_DIR)/Build/Products/$(CONFIG)/ColimaBar.app
SDK_PATH     := $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null)
SWIFT_SOURCES := $(shell find ColimaBar -name '*.swift' 2>/dev/null)

.PHONY: help regen typecheck build run relaunch release clean open

help:
	@echo "Targets:"
	@echo "  regen      Regenerate $(PROJECT) from project.yml"
	@echo "  typecheck  swiftc type-check (works with just Command Line Tools)"
	@echo "  build      xcodebuild Debug config with ad-hoc signing (needs Xcode.app)"
	@echo "  run        build + launch the .app"
	@echo "  relaunch   kill any running ColimaBar, then run"
	@echo "  release    Release build + zip artifact for cask distribution"
	@echo "  open       open the project in Xcode"
	@echo "  clean      remove $(BUILD_DIR)/ and $(PROJECT)/"

regen:
	xcodegen generate

typecheck:
	swiftc -typecheck -parse-as-library \
		-target arm64-apple-macosx14.0 \
		-sdk "$(SDK_PATH)" \
		$(SWIFT_SOURCES)

build: regen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
		build | xcbeautify 2>/dev/null || \
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
		build

run: build
	open $(APP)

relaunch:
	-pkill -x ColimaBar
	$(MAKE) run

release: regen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
		clean build
	rm -f $(BUILD_DIR)/Build/Products/Release/ColimaBar.zip
	cd $(BUILD_DIR)/Build/Products/Release && ditto -c -k --keepParent ColimaBar.app ColimaBar.zip
	@echo ""
	@echo "Artifact: $(BUILD_DIR)/Build/Products/Release/ColimaBar.zip"
	@shasum -a 256 $(BUILD_DIR)/Build/Products/Release/ColimaBar.zip

open: regen
	open $(PROJECT)

clean:
	rm -rf $(BUILD_DIR) $(PROJECT)
