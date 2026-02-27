.PHONY: build test clean lint format

build:
	swift build

test:
	swift test

clean:
	swift package clean

lint:
	ENABLE_SWIFTLINT=1 swift package plugin --allow-writing-to-package-directory swiftlint

format:
	ENABLE_SWIFTLINT=1 swift package plugin --allow-writing-to-package-directory swiftformat .
