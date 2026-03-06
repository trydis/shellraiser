.PHONY: build-app run

PROJECT := Shellraiser.xcodeproj
SCHEME := Shellraiser
DERIVED_DATA := .xcodebuild
APP_PATH := $(DERIVED_DATA)/Build/Products/Debug/Shellraiser.app

build-app:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED_DATA) build

run: build-app
	open $(APP_PATH)
