# Time Tracker: every command a contributor, an agent and CI run. The targets follow the build
# contract the j23n apps share (j23n/apple-ci); .apple-ci/apple.mk is a copy of its rules
# (`make update-apple-ci` refreshes it).

SHELL := /bin/bash

PROJECT_SPEC := project.yml
XCODEPROJ := TimeTracker.xcodeproj
SCHEME := TimeTracker
PLATFORMS := ios mac
SWIFT_PACKAGES := Packages/TrackerCore Packages/TrackerKit
# The app target has no tests of its own: the packages hold them.
TEST_APP_PLATFORMS := none

include .apple-ci/apple.mk

.PHONY: help bootstrap test test-core ci-linux ci-macos clean

help:
	@echo "make bootstrap   XcodeGen and the Xcode project"
	@echo "make test        TrackerCore's and TrackerKit's tests (macOS; make test-core on Linux)"
	@echo "make build       the app for the iOS Simulator and the Mac, unsigned"
	@echo "make ci-linux | ci-macos   what CI runs"

bootstrap: tools project

test: swift-test

# TrackerCore alone, which builds on Linux too.
test-core:
	$(SWIFT) test --package-path Packages/TrackerCore

ci-linux: test-core

ci-macos: test build

clean:
	rm -rf $(XCODEPROJ) .build Packages/*/.build
