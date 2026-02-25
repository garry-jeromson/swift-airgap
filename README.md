# NetworkGuard

Detect and fail any test that attempts a real HTTP/HTTPS network request. Drop-in, zero dependencies, supports both XCTest and Swift Testing.

## Overview

Tests should never make real outgoing network calls — they slow down the suite, cause flaky failures, and can hit production APIs. NetworkGuard provides a mechanism to catch and report any test that attempts a real HTTP/HTTPS request.

## Installation

### Local SPM dependency (monorepo)

In your `Package.swift` or Xcode project, add a local dependency:

```swift
.package(path: "../NetworkGuard")
```

Then add `"NetworkGuard"` to your test target's dependencies.

### Remote URL

```swift
.package(url: "https://github.com/your-org/NetworkGuard.git", from: "1.0.0")
```

## Quick Start

### XCTest — entire test target (recommended)

Use `NetworkGuardObserver` as the test bundle's principal class. No changes to existing test classes required.

**Option A** — Add to your test target's Info.plist:
```xml
<key>NSPrincipalClass</key>
<string>NetworkGuardObserver</string>
```

**Option B** — Set via build setting:
Set `INFOPLIST_KEY_NSPrincipalClass` to `NetworkGuardObserver` in the test target's build settings.

The observer activates the guard before any test runs and deactivates it after all tests finish. Individual tests opt out with `NetworkGuard.allowNetworkAccess()`.

### Swift Testing — `.networkGuarded` trait

Apply the trait to a suite or individual test:

```swift
import NetworkGuard
import Testing

@Suite(.networkGuarded)
struct MyFeatureTests {
    @Test func fetchData() async throws {
        // Any HTTP/HTTPS request here will record an Issue
    }
}
```

Or per-test:

```swift
@Test(.networkGuarded)
func fetchData() async throws { ... }
```

The trait automatically sets the violation handler to `Issue.record()` and activates/deactivates the guard around each test.

## Usage Levels

### 1. Entire test target — NSPrincipalClass (XCTest, no code changes)

Set `NetworkGuardObserver` as the test bundle's principal class (see Quick Start above). This is the recommended approach for Xcode test bundles — it requires zero changes to existing test classes.

> **Note:** `NSPrincipalClass` requires an Info.plist, so it works with Xcode test bundles but not standalone SPM test targets. For SPM packages, use the `.networkGuarded` trait or manual activation.

### 2. Entire test target — base class (XCTest)

If you already have a shared base test class, add activation there:

```swift
class BaseTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        NetworkGuard.activate()
    }

    override func tearDown() {
        NetworkGuard.deactivate()
        super.tearDown()
    }
}
```

### 3. Individual test suite — XCTest

Inherit from `NetworkGuardTestCase`:

```swift
final class MyTests: NetworkGuardTestCase {
    // All tests in this suite are protected
}
```

### 4. Individual test suite — Swift Testing

Use the `.networkGuarded` trait:

```swift
@Suite(.networkGuarded)
struct MyTests {
    // All tests in this suite are protected
}
```

### 5. Individual test — Swift Testing

```swift
@Test(.networkGuarded)
func fetchData() async throws { ... }
```

### 6. Manual per-test

```swift
func testSomething() {
    NetworkGuard.activate()
    defer { NetworkGuard.deactivate() }
    // ...
}
```

## Allowing Network Access

Tests that legitimately need network access can opt out:

```swift
// XCTest — opt out an entire suite
final class IntegrationTests: NetworkGuardTestCase {
    override func setUp() {
        super.setUp()
        NetworkGuard.allowNetworkAccess()
    }
}

// XCTest — opt out a single test
func testWithRealNetwork() {
    NetworkGuard.allowNetworkAccess()
    // Real network calls are allowed
}

// Swift Testing — opt out a single test within a guarded suite
@Suite(.networkGuarded)
struct MyTests {
    @Test func integrationTest() async throws {
        NetworkGuard.allowNetworkAccess()
        // Real network calls are allowed
    }
}
```

The allow flag is automatically reset on the next `activate()` call.

## Warning Mode

By default, NetworkGuard fails tests immediately on any violation (`.fail` mode). Use `.warn` mode to detect violations without failing tests — violations appear as expected failures in Xcode's issue navigator.

### Programmatic

```swift
NetworkGuard.mode = .warn
NetworkGuard.activate()
```

### Custom observer subclass (recommended for Xcode test bundles)

Subclass `NetworkGuardObserver` to configure warn mode and a report path programmatically. Set your subclass as the `NSPrincipalClass` in the test bundle's Info.plist:

```swift
import NetworkGuard

@objc(MyTestObserver)
final class MyTestObserver: NetworkGuardObserver {
    override func testBundleWillStart(_ testBundle: Bundle) {
        NetworkGuard.mode = .warn
        NetworkGuard.reportPath = "/path/to/report.txt"
        super.testBundleWillStart(testBundle)
    }
}
```

```xml
<key>NSPrincipalClass</key>
<string>MyTestObserver</string>
```

### Environment variable

Set `NETWORK_GUARD_MODE=warn` in your Xcode scheme's environment variables. Both `NetworkGuardObserver` and `NetworkGuardTestCase` read this automatically.

## Violation Report

Generate a file listing all violations with HTTP method, URL, test name, and call stack.

### Programmatic

```swift
NetworkGuard.reportPath = "/tmp/network-guard-report.txt"
NetworkGuard.activate()
// ... run tests ...
NetworkGuard.writeReport()
```

### Custom observer subclass

See the [Warning Mode](#warning-mode) section above for a complete example.

### Environment variable

Set `NETWORK_GUARD_REPORT_PATH=/path/to/report.txt` in your Xcode scheme's environment variables. The report is written automatically when the test bundle finishes (observer) or during tearDown (test case).

### Report format

```
NetworkGuard Violation Report
Generated: 2026-02-25 14:30:00
Total violations: 2

---
Test: -[MyTests testFetchUser]
Method: GET
URL: https://api.example.com/user/123
Call Stack:
  MyService.fetchUser() + 42
  MyTests.testFetchUser() + 18
  XCTestCase.invokeTest() + 123
  ...

---
Test: -[MyTests testPostData]
Method: POST
URL: https://api.example.com/data
Call Stack:
  NetworkClient.request(_:) + 56
  MyService.postData(_:) + 31
  ...
```

## Custom Failure Handling

The default handler calls `XCTFail()`. The `.networkGuarded` trait automatically sets the handler to `Issue.record()`. You can also set it manually:

```swift
// Swift Testing (manual)
NetworkGuard.violationHandler = { Issue.record("\($0)") }

// Custom logging
NetworkGuard.violationHandler = { message in
    logger.error("Unexpected network call: \(message)")
}
```

## What Gets Blocked

| Source | Blocked? |
|--------|----------|
| `URLSession.shared` | Yes |
| `URLSession(configuration: .default)` | Yes |
| `URLSession(configuration: .ephemeral)` | Yes |
| Alamofire, Moya, and other URLSession-backed libraries | Yes |
| `http://` URLs | Yes |
| `https://` URLs | Yes |

## What Doesn't Get Blocked

| Source | Reason |
|--------|--------|
| `file://` URLs | Non-HTTP scheme, intentionally allowed |
| `data://` URLs | Non-HTTP scheme, intentionally allowed |
| `Data(contentsOf: remoteURL)` | Uses a lower-level loading path that bypasses URLProtocol |
| Fully custom `URLSessionConfiguration` (not `.default`/`.ephemeral`) | Rare; configuration swizzling only covers standard factory methods |

## How It Works

1. **URLProtocol registration** — `URLProtocol.registerClass()` intercepts requests made through `URLSession.shared`
2. **Configuration swizzling** — The getters for `URLSessionConfiguration.default` and `.ephemeral` are swizzled to inject the guard protocol into every new configuration, catching custom sessions
3. **Scheme filtering** — Only `http://` and `https://` schemes are intercepted; `file://`, `data://`, and others pass through
4. **Error delivery** — Intercepted requests receive `NSURLErrorNotConnectedToInternet` so code under test gets an error rather than hanging

## Troubleshooting

**Tests fail with "NetworkGuard: Blocked request..."**
Your test is making a real network call. Replace it with a mock or stub, or call `NetworkGuard.allowNetworkAccess()` if the test genuinely needs network access.

**Guard doesn't catch requests from a custom session**
If the session was created with a fully custom `URLSessionConfiguration` (not `.default` or `.ephemeral`), the guard protocol won't be injected automatically. Manually add `NetworkGuardURLProtocol` to the configuration's `protocolClasses`.

**`Data(contentsOf:)` requests are not caught**
`Data(contentsOf:)` for remote URLs does not go through URLProtocol. This API is synchronous and discouraged by Apple. Use `URLSession` instead.

**`NSPrincipalClass` doesn't work in SPM test targets**
SPM test targets don't have an Info.plist, so `NSPrincipalClass` is not available. Use the `.networkGuarded` trait (Swift Testing) or manual `activate()`/`deactivate()` calls instead.
