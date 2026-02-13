.PHONY: setup get clean analyze test build-windows build-linux build-android build-ios build-macos run-windows dev-windows

# First-time project setup
setup: get
	flutter doctor

# Fetch dependencies
get:
	flutter pub get

# Clean build artifacts and regenerate
clean:
	flutter clean
	flutter pub get

# Run static analysis
analyze:
	flutter analyze

# Run tests
test:
	flutter test

# Build Windows release
build-windows:
	flutter build windows

# Build Linux release
build-linux:
	flutter build linux

# Build MacOS release
build-macos:
	flutter build macos

# Build Android release
build-android:
	flutter build apk

# Build iOS release. You MUST be on an Apple device for this to work.
build-ios:
	flutter build ios

# Run on Windows (debug)
run-windows:
	flutter run -d windows

# Run on Windows (debug) with hot reload
dev-windows:
	flutter run -d windows --hot
