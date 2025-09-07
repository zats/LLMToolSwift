# Repository Guidelines

## Project Structure & Modules
- `Package.swift`: SwiftPM manifest (Swift 6.0), declares products and deps.
- `Sources/LLMToolSwift`: Public API surface (macro entry points used by clients).
- `Sources/LLMToolSwiftMacros`: Macro implementation and compiler plugin (SwiftSyntax).
- `Sources/LLMToolSwiftClient`: Minimal executable showcasing macro usage.
- `Tests/LLMToolSwiftTests`: XCTest targets, including macro expansion tests.
- See `SPEC.md` for the intended `@LLMTool` design and roadmap.

## Build, Test, Run
- `swift build`: Build all targets in debug.
- `swift build -c release`: Build with optimizations.
- `swift test`: Run XCTest suite, including macro expansion assertions.
- `swift run LLMToolSwiftClient`: Run the sample client.
- Xcode: Open `Package.swift` to develop and run targets.
 - Tip: To avoid polluting the repo with build artifacts, use a temp build path:
   - `BUILD_DIR=$(mktemp -d); swift build --build-path "$BUILD_DIR" && swift test --build-path "$BUILD_DIR"`

## Coding Style & Naming
- Indentation: 4 spaces, no hard tabs.
- Types/protocols: UpperCamelCase (`WeatherService`, `LLMTool`).
- Functions/vars/params: lowerCamelCase (`getCurrentWeather`, `jsonString`).
- Files: One primary type per file; match filename to type.
- Macros: Attribute macros use `@LLMTool`; freestanding examples may be lowercased (e.g., `#stringify`).
- Formatting: Use Xcode’s default formatting or `swift-format`/`SwiftFormat` locally; no repo config is enforced.

## Testing Guidelines
- Framework: XCTest with `SwiftSyntaxMacrosTestSupport` for macro assertions.
- Structure: Test classes end with `Tests` and live under `Tests/…/*Tests.swift`.
- Add both positive and diagnostic tests (invalid inputs must produce clear errors).
- Run tests with `swift test`; prefer deterministic, fixture-free tests.

## TODO Tracking & Workflow
- Source of truth: Maintain the project TODO checklist at the end of `SPEC.md`.
- Keep it in sync: Update items as work starts/completes; reflect decisions and scope changes.
- Verify continuously: After each meaningful change, run `swift build` and `swift test` (ideally with a temp build path as shown above) to ensure behavior and diagnostics match expectations.

## Commit & PR Guidelines
- Commits: Present tense, concise summary line (≤72 chars), details below if needed.
- Scope clearly (`Macros:`, `API:`, `Client:`, `Tests:`) and reference issues (`#123`) when applicable.
- PRs: Describe motivation, approach, and alternatives; link issues; include before/after snippets or terminal output when relevant.
- Requirements: Passing CI, updated tests, and docs (e.g., `SPEC.md`) when behavior changes.

## Architecture Notes
- The library exposes macro entry points; the implementation lives in the separate `…Macros` target to satisfy Swift macro tooling.
- Public API should remain thin and stable; generation logic stays in the macro target.
- Any changes to the `@LLMTool` behavior must stay aligned with `SPEC.md` and be covered by tests.
