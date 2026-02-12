.PHONY: setup get clean analyze test build run dev

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
build:
	flutter build windows

# Run on Windows (debug)
run:
	flutter run -d windows

# Run on Windows (debug) with hot reload
dev:
	flutter run -d windows --hot
