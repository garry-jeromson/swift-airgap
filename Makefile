.PHONY: build test clean lint format lint-check lint-fix test-coverage \
	build-swift6-consumer build-xctest-consumer \
	test-xctest-consumer test-nsprincipalclass-consumer test-swift-testing-consumer \
	test-integration test-all

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

lint-check:
	ENABLE_SWIFTLINT=1 swift package plugin --allow-writing-to-package-directory swiftlint --strict
	ENABLE_SWIFTLINT=1 swift package plugin --allow-writing-to-package-directory swiftformat --lint .

lint-fix:
	ENABLE_SWIFTLINT=1 swift package plugin --allow-writing-to-package-directory swiftlint --fix
	ENABLE_SWIFTLINT=1 swift package plugin --allow-writing-to-package-directory swiftformat .

test-coverage:
	swift test --enable-code-coverage

# Integration test builds (compile-only)
build-swift6-consumer:
	swift build --package-path IntegrationTests/Swift6Consumer

build-xctest-consumer:
	swift build --build-tests --package-path IntegrationTests/XCTestConsumer

# Integration test runs
test-xctest-consumer:
	swift test --package-path IntegrationTests/XCTestConsumer

test-nsprincipalclass-consumer:
	cd IntegrationTests/NSPrincipalClassConsumer && \
		xcodebuild test \
			-scheme NSPrincipalClassConsumer-Package \
			-destination 'platform=macOS' \
			INFOPLIST_KEY_NSPrincipalClass=AirgapObserver

test-swift-testing-consumer:
	swift test --package-path IntegrationTests/SwiftTestingConsumer

# Aggregate targets
test-integration: test-xctest-consumer test-nsprincipalclass-consumer test-swift-testing-consumer

test-all: test test-integration
