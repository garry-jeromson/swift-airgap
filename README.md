<div align="center">
  <img src="docs/img/logo.png" alt="Airgap Logo" width="200"/>
  <h1>Swift Airgap</h1>
  <p><strong>Stop your unit tests from accidentally hitting real APIs.</strong></p>
</div>

Detect and fail any test that attempts a real HTTP/HTTPS network request. Drop-in, zero dependencies, supports both XCTest and Swift Testing.

## Overview

Tests should never make real outgoing network calls — they slow down the suite, cause flaky failures, and can hit production APIs. Airgap provides a mechanism to catch and report any test that attempts a real HTTP/HTTPS request.

## Installation

### Local SPM dependency (monorepo)

In your `Package.swift` or Xcode project, add a local dependency:

```swift
.package(path: "../Airgap")
```

Then add `"Airgap"` to your test target's dependencies.

### Remote URL

```swift
.package(url: "https://github.com/garry-jeromson/swift-airgap.git", from: "1.0.0")
```

## Quick Start

### XCTest — entire test target (recommended)

Use `AirgapObserver` as the test bundle's principal class. No changes to existing test classes required.

**Option A** — Add to your test target's Info.plist:
```xml
<key>NSPrincipalClass</key>
<string>AirgapObserver</string>
```

**Option B** — Set via build setting:
Set `INFOPLIST_KEY_NSPrincipalClass` to `AirgapObserver` in the test target's build settings.

The observer activates the guard before any test runs and deactivates it after all tests finish. Individual tests opt out with `Airgap.allowNetworkAccess()`.

### Swift Testing — `.airgapped` trait

Apply the trait to a suite or individual test:

```swift
import Airgap
import Testing

@Suite(.airgapped)
struct MyFeatureTests {
    @Test func fetchData() async throws {
        // Any HTTP/HTTPS request here will record an Issue
    }
}
```

Or per-test:

```swift
@Test(.airgapped)
func fetchData() async throws { ... }
```

The trait automatically sets the violation handler to `Issue.record()` and activates/deactivates the guard around each test.

## Usage Levels

### 1. Entire test target — NSPrincipalClass (XCTest, no code changes)

Set `AirgapObserver` as the test bundle's principal class (see Quick Start above). This is the recommended approach for Xcode test bundles — it requires zero changes to existing test classes.

> **Note:** `NSPrincipalClass` requires an Info.plist, so it works with Xcode test bundles but not standalone SPM test targets. For SPM packages, use the `.airgapped` trait or manual activation.

### 2. Entire test target — base class (XCTest)

If you already have a shared base test class, add activation there:

```swift
class BaseTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        Airgap.activate()
    }

    override func tearDown() {
        Airgap.deactivate()
        super.tearDown()
    }
}
```

### 3. Individual test suite — XCTest

Inherit from `AirgapTestCase`:

```swift
final class MyTests: AirgapTestCase {
    // All tests in this suite are protected
}
```

### 4. Individual test suite — Swift Testing

Use the `.airgapped` trait:

```swift
@Suite(.airgapped)
struct MyTests {
    // All tests in this suite are protected
}
```

### 5. Individual test — Swift Testing

```swift
@Test(.airgapped)
func fetchData() async throws { ... }
```

### 6. Manual per-test

```swift
func testSomething() {
    Airgap.activate()
    defer { Airgap.deactivate() }
    // ...
}
```

## Allowing Network Access

Tests that legitimately need network access can opt out:

```swift
// XCTest — opt out an entire suite
final class IntegrationTests: AirgapTestCase {
    override func setUp() {
        super.setUp()
        Airgap.allowNetworkAccess()
    }
}

// XCTest — opt out a single test
func testWithRealNetwork() {
    Airgap.allowNetworkAccess()
    // Real network calls are allowed
}

// Swift Testing — opt out a single test within a guarded suite
@Suite(.airgapped)
struct MyTests {
    @Test func integrationTest() async throws {
        Airgap.allowNetworkAccess()
        // Real network calls are allowed
    }
}
```

The allow flag is automatically reset on the next `activate()` call.

## Warning Mode

By default, Airgap fails tests immediately on any violation (`.fail` mode). Use `.warn` mode to detect violations without failing tests — violations appear as expected failures in Xcode's issue navigator.

### Programmatic

```swift
Airgap.mode = .warn
Airgap.activate()
```

### Custom observer subclass (recommended for Xcode test bundles)

Subclass `AirgapObserver` to configure warn mode and a report path programmatically. Set your subclass as the `NSPrincipalClass` in the test bundle's Info.plist:

```swift
import Airgap

@objc(MyTestObserver)
final class MyTestObserver: AirgapObserver {
    override func testBundleWillStart(_ testBundle: Bundle) {
        Airgap.mode = .warn
        Airgap.reportPath = "/path/to/report.txt"
        super.testBundleWillStart(testBundle)
    }
}
```

```xml
<key>NSPrincipalClass</key>
<string>MyTestObserver</string>
```

### Environment variable

Set `AIRGAP_MODE=warn` in your Xcode scheme's environment variables. Both `AirgapObserver` and `AirgapTestCase` read this automatically.

## Violation Report

Generate a file listing all violations with HTTP method, URL, test name, and call stack.

### Programmatic

```swift
Airgap.reportPath = "/tmp/airgap-report.txt"
Airgap.activate()
// ... run tests ...
Airgap.writeReport()
```

### Custom observer subclass

See the [Warning Mode](#warning-mode) section above for a complete example.

### Environment variable

Set `AIRGAP_REPORT_PATH=/path/to/report.txt` in your Xcode scheme's environment variables. The report is written automatically when the test bundle finishes (observer) or during tearDown (test case).

### Report format

```
Airgap Violation Report
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

The default handler calls `XCTFail()`. The `.airgapped` trait automatically sets the handler to `Issue.record()`. You can also set it manually:

```swift
// Swift Testing (manual)
Airgap.violationHandler = { Issue.record("\($0)") }

// Custom logging
Airgap.violationHandler = { message in
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

**Tests fail with "Airgap: Blocked request..."**
Your test is making a real network call. Replace it with a mock or stub, or call `Airgap.allowNetworkAccess()` if the test genuinely needs network access.

**Guard doesn't catch requests from a custom session**
If the session was created with a fully custom `URLSessionConfiguration` (not `.default` or `.ephemeral`), the guard protocol won't be injected automatically. Manually add `AirgapURLProtocol` to the configuration's `protocolClasses`.

**`Data(contentsOf:)` requests are not caught**
`Data(contentsOf:)` for remote URLs does not go through URLProtocol. This API is synchronous and discouraged by Apple. Use `URLSession` instead.

**`NSPrincipalClass` doesn't work in SPM test targets**
SPM test targets don't have an Info.plist, so `NSPrincipalClass` is not available. Use the `.airgapped` trait (Swift Testing) or manual `activate()`/`deactivate()` calls instead.
