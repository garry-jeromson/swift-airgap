.PHONY: build test clean lint format

build:
	swift build

test:
	swift test

clean:
	swift package clean

lint:
	swift package plugin --allow-writing-to-package-directory swiftlint

format:
	swift package plugin --allow-writing-to-package-directory swiftformat .
