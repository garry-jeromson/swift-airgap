# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `Airgap.scoped()` — manual scoping API for Swift Testing on Swift 6.0, providing the same automatic scope serialization, state save/restore, and violation reporting as the `.airgapped` trait
- `Package@swift-6.0.swift` — version-specific manifest that excludes `AirgapSwiftTestingIntegrationTests` to prevent cross-target concurrency races on Swift 6.0
- CI now runs tests on Swift 6.0 (previously build-only)

## [1.6.0] — 2026-02-28

### Added
- `Airgap.withNetworkAccessAllowed()` scoped helper (sync and async overloads) for temporarily allowing network access within a block
- `writeReport()` now returns `Bool` indicating success/failure (`@discardableResult`)
- `make check` convenience target (runs lint + tests)
- Direct `AsyncMutex` unit tests
- CI now runs tests on Swift 5.10 (previously build-only)
- CHANGELOG.md
- KMP/Ktor interception documentation in README
- Swift version compatibility section in README
- Expanded troubleshooting section in README

## [1.5.0] — 2026-02-25

### Added
- `passthroughProtocols` — let mock URLProtocol frameworks (e.g., Mocker, OHHTTPStubs) coexist with Airgap. Mocked requests go through the mock; unmocked requests are blocked.
- `writeReport()` is now called automatically by the `.airgapped` trait on scope teardown.
- Integration test infrastructure with consumer packages (`XCTestConsumer`, `SwiftTestingConsumer`, `NSPrincipalClassConsumer`).
- CI pipeline steps for building and testing consumer packages.
- Report-writing integration tests for both consumer packages.

### Fixed
- Swift Testing violation attribution — violations are now correctly attributed to the test that triggered them.
- Flaky XCTest failures — violations are delivered synchronously on the main thread.

### Migration
- If you use a mock URLProtocol library alongside Airgap, configure `passthroughProtocols` so Airgap yields to the mock for handled requests:
  ```swift
  Airgap.passthroughProtocols = [MockingURLProtocol.self]
  ```

## [1.4.0] — 2026-02-22

### Added
- Swift 5.10 support via version-specific package manifest (`Package@swift-5.10.swift`).
- Swift 6.2 (Xcode 26.2, macOS 26) to CI matrix.
- Refactored test structure: extracted helpers, deduplicated setup, split integration tests.

## [1.3.1] — 2026-02-22

### Fixed
- Swift Package Index build: flipped SwiftLint from opt-out to opt-in.

## [1.3.0] — 2026-02-19

### Added
- WebSocket interception via `URLSessionTask.resume()` swizzle — `URLSessionWebSocketTask` and `ws://`/`wss://` schemes are detected, violations reported, and tasks cancelled.
- `withConfiguration()` scoping API for temporary configuration overrides.
- Configurable `errorCode` and `responseDelay` for intercepted requests.
- `Airgap.isActive` public property.
- `violationReporter` callback for structured violation reporting with full `Violation` struct.
- Actionable hints in violation error messages.
- SwiftLint and SwiftFormat via SwiftPM plugins.
- `configure()` hook for `AirgapTestCase` subclass customization.
- `withKnownIssue` for Swift Testing warn mode.
- JSON report format (`.json` extension).
- Swift 6.1+ `TestScoping` guard for `.airgapped` trait compatibility.
- Doc comments across public API surface.
- Split tests into dedicated files by functional area.

### Fixed
- `hasSwizzled` race condition.
- Trait state leaks and environment variable handling.
- Warn mode ignoring `violationHandler`.

## [1.2.0] — 2026-02-18

### Added
- `URLSession.init` swizzle — catches sessions created from configurations obtained before `activate()` or from non-standard configs (e.g., `.background`).

## [1.1.0] — 2026-02-18

### Fixed
- Crash when `XCTFail` called from CFNetwork background thread.

### Changed
- Restructured README: separate XCTest and Swift Testing sections, documented missing APIs.

## [1.0.1] — 2026-02-17

### Added
- Caller attribution via `URLSessionTask.resume()` swizzle — call stacks now show the user's code, not URL loading system internals.
- `violationHandler` is lock-protected for thread safety.
- Trait-scoped allowed hosts documentation in README.
- tvOS and watchOS platform support in Swift Package Index metadata.

### Fixed
- `XCTExpectFailure` crash in Swift Testing context on CI.

## [1.0.0] — 2026-02-16

### Added
- Thread safety via `NSLock` for all mutable shared state.
- Host allowlist with wildcard domain matching (`allowedHosts`, `*.example.com`).
- macOS support.
- Swift 6 strict concurrency checking.
- `AIRGAP_ALLOWED_HOSTS` environment variable.
- `Violation` struct with `Equatable` and `Codable` conformance.
- `violationSummary()` API.
- Violation report with `Content-Type` header.
- Case-insensitive host matching per RFC 3986.

## [0.0.1] — 2026-02-15

### Added
- Initial release.
- `AirgapURLProtocol` for intercepting HTTP/HTTPS requests via `URLProtocol.registerClass()`.
- `URLSessionConfiguration.default` and `.ephemeral` swizzling.
- `AirgapObserver` for bundle-level activation via `NSPrincipalClass`.
- `AirgapTestCase` for per-test activation.
- `.airgapped` Swift Testing trait.
- Warning mode (`.warn`) with `XCTExpectFailure` support.
- `allowNetworkAccess()` opt-out.
- `reportPath` and `writeReport()` for violation reports.
- `configureFromEnvironment()` for environment variable configuration.

[Unreleased]: https://github.com/garry-jeromson/swift-airgap/compare/1.6.0...HEAD
[1.6.0]: https://github.com/garry-jeromson/swift-airgap/compare/1.5.0...1.6.0
[1.5.0]: https://github.com/garry-jeromson/swift-airgap/compare/1.4.0...1.5.0
[1.4.0]: https://github.com/garry-jeromson/swift-airgap/compare/1.3.1...1.4.0
[1.3.1]: https://github.com/garry-jeromson/swift-airgap/compare/1.3.0...1.3.1
[1.3.0]: https://github.com/garry-jeromson/swift-airgap/compare/1.2.0...1.3.0
[1.2.0]: https://github.com/garry-jeromson/swift-airgap/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/garry-jeromson/swift-airgap/compare/1.0.1...1.1.0
[1.0.1]: https://github.com/garry-jeromson/swift-airgap/compare/1.0.0...1.0.1
[1.0.0]: https://github.com/garry-jeromson/swift-airgap/compare/0.0.1...1.0.0
[0.0.1]: https://github.com/garry-jeromson/swift-airgap/releases/tag/0.0.1
