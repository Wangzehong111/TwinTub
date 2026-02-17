# Contributing to TwinTub

Thank you for your interest in contributing to TwinTub! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Development Environment](#development-environment)
- [Project Structure](#project-structure)
- [How to Contribute](#how-to-contribute)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Testing](#testing)

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## Development Environment

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later
- Swift 5.9 or later

### Setup

1. Fork and clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/TwinTub.git
   cd TwinTub
   ```

2. Build the project:
   ```bash
   xcodebuild -scheme TwinTub -destination 'platform=macOS' build
   ```

3. Run the development build:
   ```bash
   ./scripts/run_twintub_app.sh
   ```

4. Install hooks for testing (optional):
   ```bash
   ./hooks/install_hooks.sh
   ```

### Verify Setup

Run the test suite to verify your environment:

```bash
xcodebuild -scheme TwinTub -destination 'platform=macOS' test
```

Check the health endpoint:

```bash
curl -i http://127.0.0.1:55771/health
```

## Project Structure

```
TwinTub/
├── TwinTubApp/
│   ├── App/
│   │   └── TwinTubApp.swift      # App entry point, EventBridge, AppDelegate
│   ├── Core/
│   │   ├── Configuration/        # Configuration constants
│   │   ├── EventServer/          # HTTP server for hook events
│   │   ├── Model/                # Data models (TwinTubEvent, SessionModel)
│   │   ├── Services/             # Business services (notifications, terminal jump)
│   │   ├── State/                # Reducer for state mutations
│   │   └── Store/                # State management
│   └── UI/
│       ├── MenuBar/              # Menu bar status icon
│       ├── Panel/                # Main panel view and session cards
│       └── Theme/                # Theme tokens and color schemes
├── TwinTubTests/                 # Unit tests
├── hooks/                        # Claude Code hook scripts
├── scripts/                      # Build and utility scripts
└── Formula/                      # Homebrew formula
```

### Architecture

TwinTub uses a Redux-like architecture:

```
TwinTubEvent → EventBridge → SessionStore → SwiftUI Views
                  │              │
                  │              ├─→ SessionReducer (pure)
                  │              ├─→ SessionLivenessMonitor
                  │              └─→ NotificationService
                  │
                  └─→ Coalesce by session, 100ms flush
```

## How to Contribute

### Reporting Bugs

1. Check existing issues to avoid duplicates
2. Use the bug report template
3. Include:
   - macOS version
   - TwinTub version
   - Steps to reproduce
   - Expected vs actual behavior
   - Logs from Console.app (filter: "TwinTub")

### Suggesting Features

1. Check existing issues for similar requests
2. Use the feature request template
3. Describe the use case and expected behavior

### Code Contributions

1. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following the coding standards

3. Add or update tests

4. Ensure all tests pass:
   ```bash
   xcodebuild -scheme TwinTub -destination 'platform=macOS' test
   ```

5. Commit with a clear message

## Pull Request Process

1. **Fork & Branch**: Create a feature branch from `main`

2. **Code Quality**:
   - Follow Swift naming conventions
   - Add documentation comments for public APIs
   - Keep functions focused and single-purpose

3. **Testing**:
   - Add unit tests for new functionality
   - Ensure existing tests pass
   - Test manually on macOS

4. **Documentation**:
   - Update README.md if needed
   - Update CLAUDE.md for architecture changes
   - Add inline comments for complex logic

5. **Commit Messages**:
   - Use present tense ("Add feature" not "Added feature")
   - Keep first line under 72 characters
   - Reference issues: "Fix #123"

6. **Submit PR**:
   - Fill out the PR template
   - Link related issues
   - Request review

## Coding Standards

### Swift Style

- Use Swift 5.9 features where appropriate
- Prefer `let` over `var` when possible
- Use meaningful variable names
- Keep lines under 120 characters

### Documentation

- Use Swift documentation comments (`///`) for public APIs
- Include parameter and return descriptions
- Add code examples for complex APIs

```swift
/// Calculates the number of progress bar segments based on token usage.
/// - Parameters:
///   - usageTokens: Current token usage count
///   - maxContextTokens: Maximum context window size (default: 200K)
/// - Returns: Number of segments (0-10)
public static func segmentsForTokens(_ usageTokens: Int, maxContextTokens: Int = defaultMaxContextTokens) -> Int
```

### Comments

- Public API: English documentation comments
- Internal logic: Can use Chinese or English
- Explain "why", not "what"

### File Organization

```swift
// 1. Imports
import Foundation

// 2. Type definition
public final class MyClass {
    // 3. Properties (static first, then instance)
    public static let shared = MyClass()
    private let property: String

    // 4. Initializers
    public init() {}

    // 5. Public methods
    public func doSomething() {}

    // 6. Private methods
    private func helper() {}
}

// 7. Extensions (separate by protocol conformance)
extension MyClass: Equatable {
    public static func == (lhs: MyClass, rhs: MyClass) -> Bool {
        return true
    }
}
```

## Testing

### Running Tests

```bash
# All tests
xcodebuild -scheme TwinTub -destination 'platform=macOS' test

# Specific test file
swift test --filter SessionReducerTests

# With verbose output
xcodebuild -scheme TwinTub -destination 'platform=macOS' test | xcpretty
```

### Writing Tests

- Place tests in `TwinTubTests/` directory
- Name test files with `Tests` suffix
- Use descriptive test function names:
  ```swift
  func test_reduce_userPromptSubmit_setsProcessingStatus()
  ```

### Test Coverage

- Aim for high coverage on business logic (reducers, monitors)
- Test edge cases and error paths
- Use mocks for external dependencies

---

Thank you for contributing to TwinTub!
