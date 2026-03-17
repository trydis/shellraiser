.PHONY: build-app run build-isolated run-isolated

PROJECT := Shellraiser.xcodeproj
SCHEME := Shellraiser
DERIVED_DATA := .xcodebuild
ISOLATED_DERIVED_DATA := .xcodebuild-isolated
CONFIGURATION := Debug
PRODUCT_NAME := Shellraiser
ISOLATED_PRODUCT_NAME := ShellraiserDev
ISOLATED_BUNDLE_IDENTIFIER := com.shellraiser.app.dev
ISOLATED_APP_SUPPORT_SUBDIRECTORY := ShellraiserDev
BUILD_FLAGS := -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION)
ISOLATED_BUILD_FLAGS := $(BUILD_FLAGS) PRODUCT_NAME=$(ISOLATED_PRODUCT_NAME) PRODUCT_BUNDLE_IDENTIFIER=$(ISOLATED_BUNDLE_IDENTIFIER)
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(PRODUCT_NAME).app
ISOLATED_APP_PATH := $(ISOLATED_DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(ISOLATED_PRODUCT_NAME).app

build-app:
	xcodebuild $(BUILD_FLAGS) -derivedDataPath $(DERIVED_DATA) build
	@test -d ghostty/zig-out/share/ghostty || (echo "Error: ghostty/zig-out/share/ghostty not found. Run 'zig build' in the ghostty directory first." && exit 1)
	@test -d ghostty/zig-out/share/terminfo || (echo "Error: ghostty/zig-out/share/terminfo not found. Run 'zig build' in the ghostty directory first." && exit 1)
	rm -rf $(APP_PATH)/Contents/Resources/ghostty $(APP_PATH)/Contents/Resources/terminfo
	cp -R ghostty/zig-out/share/ghostty $(APP_PATH)/Contents/Resources/ghostty
	cp -R ghostty/zig-out/share/terminfo $(APP_PATH)/Contents/Resources/terminfo

build-isolated:
	xcodebuild $(ISOLATED_BUILD_FLAGS) -derivedDataPath $(ISOLATED_DERIVED_DATA) build
	@test -d ghostty/zig-out/share/ghostty || (echo "Error: ghostty/zig-out/share/ghostty not found. Run 'zig build' in the ghostty directory first." && exit 1)
	@test -d ghostty/zig-out/share/terminfo || (echo "Error: ghostty/zig-out/share/terminfo not found. Run 'zig build' in the ghostty directory first." && exit 1)
	rm -rf $(ISOLATED_APP_PATH)/Contents/Resources/ghostty $(ISOLATED_APP_PATH)/Contents/Resources/terminfo
	cp -R ghostty/zig-out/share/ghostty $(ISOLATED_APP_PATH)/Contents/Resources/ghostty
	cp -R ghostty/zig-out/share/terminfo $(ISOLATED_APP_PATH)/Contents/Resources/terminfo

run: build-app
	open $(APP_PATH)

run-isolated: build-isolated
	open --env SHELLRAISER_APP_SUPPORT_SUBDIRECTORY=$(ISOLATED_APP_SUPPORT_SUBDIRECTORY) $(ISOLATED_APP_PATH)
