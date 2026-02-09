# Contributing to FRTMProxy

First off, thank you for considering contributing to FRTMProxy! It's people like you that make FRTMProxy such a great tool for debugging HTTP/S traffic.

## Code of Conduct

This project and everyone participating in it is governed by the [FRTMProxy Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code. Please report unacceptable behavior by opening an issue.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the existing issues to avoid duplicates. When you are creating a bug report, please include as many details as possible:

* **Use a clear and descriptive title** for the issue to identify the problem.
* **Describe the exact steps which reproduce the problem** in as many details as possible.
* **Provide specific examples to demonstrate the steps**.
* **Describe the behavior you observed after following the steps** and point out what exactly is the problem with that behavior.
* **Explain which behavior you expected to see instead and why.**
* **Include screenshots and animated GIFs** which show you following the described steps and clearly demonstrate the problem.
* **Include your macOS version** and FRTMProxy version.

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

* **Use a clear and descriptive title** for the issue to identify the suggestion.
* **Provide a step-by-step description of the suggested enhancement** in as many details as possible.
* **Provide specific examples to demonstrate the steps** or provide mockups if applicable.
* **Describe the current behavior** and **explain which behavior you expected to see instead** and why.
* **Explain why this enhancement would be useful** to most FRTMProxy users.

### Pull Requests

* Fill in the pull request template (if available)
* Do not include issue numbers in the PR title
* Include screenshots and animated GIFs in your pull request whenever possible
* Follow the Swift style guide (see below)
* Document new code
* End all files with a newline
* Avoid platform-dependent code

## Development Setup

FRTMProxy is a macOS application built with Swift and SwiftUI. To set up your development environment:

1. **Prerequisites**:
   - macOS 12.0 or later
   - Xcode 14.0 or later
   - Swift 5.7 or later

2. **Clone the repository**:
   ```bash
   git clone https://github.com/ValentinoPalomba/FRTMProxy.git
   cd FRTMProxy
   ```

3. **Open the project**:
   ```bash
   open FRTMProxy.xcodeproj
   ```

4. **Build and run**:
   - Select the FRTMProxy scheme
   - Press `Cmd + R` to build and run

## Coding Style

* Follow Swift's standard naming conventions
* Use meaningful variable and function names
* Write self-documenting code; add comments only when necessary to explain "why", not "what"
* Keep functions focused and single-purpose
* Use SwiftUI best practices for UI components
* Keep code clean and maintainable

### Swift Style Guidelines

* Use 4 spaces for indentation (not tabs)
* Place opening braces on the same line as the declaration
* Use `camelCase` for variables and functions
* Use `PascalCase` for types and protocols
* Prefer `let` over `var` whenever possible
* Avoid force unwrapping (`!`) when possible; prefer optional binding or guard statements

Example:
```swift
func processRequest(_ request: URLRequest) -> HTTPResponse? {
    guard let url = request.url else {
        return nil
    }
    
    // Process the request
    return HTTPResponse(url: url)
}
```

## Testing

* Write tests for new features when applicable
* Ensure all existing tests pass before submitting a PR
* Test your changes on different macOS versions if possible
* Test with both Simulator and physical iOS devices when changes affect device connectivity

## Git Commit Messages

* Use the present tense ("Add feature" not "Added feature")
* Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
* Limit the first line to 72 characters or less
* Reference issues and pull requests liberally after the first line
* Consider starting the commit message with an applicable emoji:
  * 🎨 `:art:` when improving the format/structure of the code
  * 🐛 `:bug:` when fixing a bug
  * ✨ `:sparkles:` when adding a new feature
  * 📝 `:memo:` when writing docs
  * 🚀 `:rocket:` when improving performance
  * ✅ `:white_check_mark:` when adding tests
  * 🔒 `:lock:` when dealing with security

## Project Structure

* `FRTMProxy/` - Main application code
* `ProxyCore/` - Core proxy functionality
* `.media/` - Screenshots and media assets
* `readme.md` - Project documentation

## License

By contributing to FRTMProxy, you agree that your contributions will be licensed under the [GNU Affero General Public License v3.0](LICENSE).

This means:
* You must make the source code of any modifications available under the same license
* If you distribute modified versions or run FRTMProxy as a network service, you must disclose the source code
* Your contributions must be compatible with AGPL-3.0

## Questions?

Don't hesitate to ask questions by opening an issue. We're here to help!

## Recognition

Contributors will be recognized in the project. Thank you for making FRTMProxy better! 🚀
