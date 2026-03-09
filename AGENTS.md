# Repository Guidelines

## Project Structure & Module Organization
- Xcode app project: `Shellraiser.xcodeproj` with entitlements in `Shellraiser/Shellraiser.entitlements`.
- SwiftPM manifest: `Package.swift` (builds executable product `Shellraiser`).
- Embedded terminal dependency: `ghostty/` submodule and `ghostty/macos/GhosttyKit.xcframework`.
- Build artifacts are local-only: `.build/`, `.xcodebuild/`, and `*.app`.

## Build, Test, and Development Commands
- `swift build`  
  Builds the SwiftPM target quickly for iteration checks.
- `xcodebuild -project Shellraiser.xcodeproj -scheme Shellraiser -configuration Debug -derivedDataPath .xcodebuild build`  
  Builds the macOS app bundle used for local runs.
- `make build-app`  
  Convenience wrapper for the `xcodebuild` command above.
- `make run`  
  Builds Debug app and opens `.xcodebuild/Build/Products/Debug/Shellraiser.app`.

## Coding Style & Naming Conventions
- Language: Swift 5.9+, macOS 14 target.
- Use 4-space indentation and keep lines focused and readable.
- Types/protocols: `UpperCamelCase`; functions/vars/properties: `lowerCamelCase`.
- Keep model and manager names explicit (`*Model`, `*Manager`, `*View`).
- Add concise doc comments (`///`) for non-trivial types/functions.
- Prefer small, composable methods and keep UI state changes on `@MainActor`.
- Prefer small and focused classes

## Testing Guidelines
- Test suite lives in `Tests/ShellraiserTests` and is exposed through the SwiftPM target `ShellraiserTests`.
- Run `swift test` for unit and integration coverage during normal iteration.
- Minimum validation before commit:
  - `swift test`
  - `make build-app`

## Commit & Pull Request Guidelines
- Commit messages in imperative mood, concise, and scoped
- Keep submodule updates explicit in separate commits when practical (e.g., `Update ghostty submodule pointer`).

## Security & Configuration Notes
- Do not commit secrets, tokens, or local env files.
- Keep `.gitignore` entries for Xcode/Swift build outputs intact.
- Treat `ghostty/` as upstream code: avoid unrelated edits and document any submodule commit changes clearly.
