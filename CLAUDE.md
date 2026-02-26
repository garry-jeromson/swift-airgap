# CLAUDE.md — Swift Airgap

## Project Description

Airgap is a test-time network interceptor for Swift that blocks real HTTP/HTTPS requests during unit tests, catching accidental network access via URLProtocol registration, URLSessionConfiguration swizzling, and URLSessionTask.resume() swizzling.

## Build & Test

```bash
swift build
swift test
```

No external dependencies. No Xcode project file — pure SwiftPM.

## Architecture

Five interception mechanisms work together:

1. **URLProtocol registration** (`URLProtocol.registerClass`) — catches requests made via `URLSession.shared`
2. **URLSessionConfiguration swizzling** — swizzles `.default` and `.ephemeral` getters to inject `AirgapURLProtocol` into `protocolClasses`, catching sessions created from standard configurations
3. **URLSession.init swizzling** — swizzles the designated initializer `initWithConfiguration:delegate:delegateQueue:` to inject `AirgapURLProtocol` at session creation time, catching sessions created from configs obtained before `activate()` or from non-standard configs (e.g., `.background`)
4. **URLSessionTask.resume() swizzling** — captures accurate call stacks at the point where user code initiates the request (not deep inside URLProtocol machinery); also intercepts WebSocket tasks directly since URLProtocol cannot intercept WebSocket connections
5. **WebSocket interception** — `URLSessionWebSocketTask` and `ws://`/`wss://` schemes are detected in the resume swizzle, violations are reported, and the task is cancelled

Intercepted requests receive a configurable error code (default `NSURLErrorNotConnectedToInternet`). Non-HTTP schemes (file://, data://) pass through.

## Key Files

| File | Purpose |
|---|---|
| `Sources/Airgap/Airgap.swift` | Main API: activate/deactivate, mode, allowed hosts, violation reporting (text and JSON formats), `isActive`, `violationReporter`, `errorCode`, `responseDelay`, `withConfiguration()` |
| `Sources/Airgap/AirgapURLProtocol.swift` | URLProtocol subclass that intercepts HTTP/HTTPS requests |
| `Sources/Airgap/AirgapObserver.swift` | XCTestObservation-based lifecycle hook (bundle-level activation) |
| `Sources/Airgap/AirgapTestCase.swift` | XCTestCase subclass for per-test activation; `configure()` hook for subclass customization |
| `Sources/Airgap/AirgapTrait.swift` | Swift Testing trait for `.airgapped` annotation; warn mode uses `withKnownIssue` |
| `Sources/Airgap/Violation.swift` | Sendable/Codable data model for captured violations |

## Conventions

- **Swift 6.0** with strict concurrency checking
- **No external dependencies**
- **Thread safety** via `NSLock` — all mutable shared state is lock-protected
- **Platforms**: iOS 16+, macOS 13+, tvOS 16+, watchOS 9+
- **`nonisolated(unsafe)`** used for lock-protected static vars (Swift 6 concurrency pattern)
- **`@unchecked Sendable`** used sparingly for lock-protected helper types in tests

## Test Targets

| Target | Framework | Purpose |
|---|---|---|
| `AirgapTests` | XCTest | Unit tests for all core functionality |
| `AirgapXCTestIntegrationTests` | XCTest | Integration tests for XCTest-based activation flows |
| `AirgapSwiftTestingTests` | Swift Testing | Integration tests for the `.airgapped` trait |

## KMP (Kotlin Multiplatform) Network Interception Analysis

### Summary

Airgap's existing swizzling already catches most KMP network requests on Apple platforms because Ktor's Darwin engine uses `NSURLSession` with standard `URLSessionConfiguration` under the hood.

### How Ktor Works on Apple Platforms

- Ktor's Darwin engine creates `NSURLSession` instances from `URLSessionConfiguration` (typically `.default`)
- All HTTP requests go through Apple's networking stack via `NSURLSession`
- Ktor also supports custom preconfigured sessions via `usePreconfiguredSession()`

### What Already Works

- `swizzleSessionConfigurations()` injects `AirgapURLProtocol` into `.default` and `.ephemeral` config getters
- Since Ktor's Darwin engine creates sessions from standard configurations, requests are intercepted
- `URLProtocol.registerClass()` also covers `URLSession.shared`

### Known Gaps

1. **Sessions created before `activate()` with non-standard configs** — sessions created before `Airgap.activate()` bypass all swizzling since the session already exists. The `URLSession.init` swizzle closes the gap for sessions created *after* activation, even from pre-activation configs or non-standard configs (e.g., `.background`).
2. **Other KMP HTTP clients** — custom expect/actual implementations using raw platform networking depend on whether they go through `URLSession`

### Verification

The `AirgapTests` target includes proof-of-concept tests (`testKtorDarwinEnginePatternIsIntercepted`, `testSessionFromPreActivationConfigIsInterceptedViaInitSwizzle`, `testBackgroundConfigIsInterceptedViaInitSwizzle`) that simulate Ktor's Darwin engine pattern and verify that violations are captured, including for configs obtained before activation and non-standard config types.
