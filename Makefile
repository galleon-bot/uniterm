SHELL := bash -o pipefail
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:
.SUFFIXES:
MAKEFLAGS += --warn-undefined-variables

# Everything the build writes stays under the repo, so a sandboxed shell can run it.

# Xcode build output, including the .app bundle.
DERIVED_DATA ?= .build/DerivedData
# Where SwiftPM keeps checkouts for the Xcode build.
SOURCE_PACKAGES ?= .build/SourcePackages
# Where `swift build` and `swift test` keep the package build.
SWIFTPM_SCRATCH ?= .build/swiftpm
# Xcode build configuration.
CONFIGURATION ?= Debug
# Space-separated Swift paths, relative to the repo root, for fmt-select. Empty formats nothing.
FILES ?=

PACKAGE_DIR := Packages/UnitermKit
SWIFT_DIRS := App UITests $(PACKAGE_DIR)/Sources $(PACKAGE_DIR)/Tests $(PACKAGE_DIR)/Package.swift
XCODEBUILD := xcodebuild -project uniterm.xcodeproj -scheme uniterm \
	-configuration $(CONFIGURATION) \
	-derivedDataPath $(DERIVED_DATA) \
	-clonedSourcePackagesDirPath $(SOURCE_PACKAGES)

##@ Build

.PHONY: help
help: ## Show this help
	@awk 'BEGIN { FS = ":.*## " } \
		/^##@ / { printf "\n%s\n", substr($$0, 5) } \
		/^[a-zA-Z0-9_.\/-]+:([^=]|$$).*## / { printf "  %-24s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: ghostty
ghostty: ## Build the pinned GhosttyKit and link it into the package (needs Zig, only on a cold cache)
	scripts/build-ghostty.sh

.PHONY: build
build: ghostty ## Build uniterm.app
	$(XCODEBUILD) build

.PHONY: clean
clean: ## Remove Xcode and SwiftPM build output. Keeps the Ghostty cache
	rm -rf .build/DerivedData .build/SourcePackages .build/swiftpm

##@ Test

.PHONY: test
test: test-package test-app ## Run the package tests and the app UI tests

.PHONY: test-package
test-package: ghostty ## Run the package tests with swift test
	cd $(PACKAGE_DIR) && swift test --scratch-path ../../$(SWIFTPM_SCRATCH)

.PHONY: test-app
test-app: ghostty ## Run the UI tests with xcodebuild. They need a GUI session and Accessibility permission
	scripts/run-ui-tests.sh $(XCODEBUILD) -test-timeouts-enabled YES \
		-default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 test

.PHONY: ghostty-offline-check
ghostty-offline-check: ## Rebuild the pinned Ghostty with the network off, from the kept caches
	scripts/ghostty-offline-check.sh

##@ Lint

.PHONY: fmt
fmt: ## Format Swift sources in place
	swift format --configuration .swift-format --in-place --recursive $(SWIFT_DIRS)

.PHONY: fmt-check
fmt-check: ## Verify Swift formatting without changing files
	swift format lint --strict --configuration .swift-format --recursive $(SWIFT_DIRS)

.PHONY: fmt-select
fmt-select: ## Format only the named files, e.g. make fmt-select FILES='App/AppDelegate.swift'
	$(if $(filter %.swift,$(FILES)),swift format --configuration .swift-format --in-place $(filter %.swift,$(FILES)))

.PHONY: lint
lint: fmt-check ## Lint Swift sources and check the scripts parse
	for script in scripts/*.sh; do bash -n "$$script" || exit 1; done

.PHONY: check
check: ## Check that the package and the app share one Swift language mode
	scripts/check-swift-mode.sh

.PHONY: ci
ci: fmt-check lint check test ghostty-offline-check ## Run what CI runs. Includes the 4-minute offline Ghostty rebuild
