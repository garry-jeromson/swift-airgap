# Contributing to Airgap

Thanks for your interest in contributing to Airgap!

## Prerequisites

- **Swift 6.1+** (Xcode 16.4+) for running tests
- **SwiftLint** and **SwiftFormat** for linting (`brew install swiftlint swiftformat`)

## Getting Started

```bash
git clone https://github.com/AirGap/swift-airgap.git
cd swift-airgap
swift build
swift test
```

## Project Structure

See [CLAUDE.md](CLAUDE.md) for a detailed overview of the architecture, key files, and design decisions.

## Running Tests

```bash
make test              # Unit + in-package integration tests
make test-integration  # Consumer integration tests
make test-all          # Everything
make test-coverage     # Tests with code coverage
```

## Linting & Formatting

```bash
make lint-check        # Check lint + format (same as CI)
make lint              # SwiftLint via SwiftPM plugin
make format            # Auto-format via SwiftPM plugin
```

CI runs `swiftlint lint --strict` and `swiftformat --lint .` on every PR. Run `make lint-check` locally before pushing to catch issues early.

## Submitting Changes

1. Fork the repo and create a feature branch from `main`
2. Make your changes
3. Add or update tests as appropriate
4. Run `make test` and `make lint-check`
5. Update `CLAUDE.md` if you changed architecture, public API, or conventions
6. Open a pull request

## Code Style

- Swift 6.0 language mode with strict concurrency checking
- No external dependencies
- Thread safety via `NSLock` for shared mutable state
- Use `nonisolated(unsafe)` for lock-protected static vars (Swift 6 concurrency pattern)
