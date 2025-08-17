# LLMToolSwift

Swift macros that generate OpenAI-style LLM tool schemas from documented Swift functions. Annotate a function with `@LLMTool` and a static `<funcName>LLMTool` property is generated that describes the function and its parameters. Use `jsonString` to get a minified JSON schema you can pass to LLMs.

- URL: https://github.com/zats/LLMToolSwift
- Swift: 6.2 (macOS 10.15+/iOS 13+)

## Features
- `@LLMTool`: Generates `<funcName>LLMTool` with matching access level for per-function tool schemas.
- `@LLMTools`: On a type, aggregates all `@LLMTool`-annotated functions into `static var llmTools` and generates `async throws func dispatchTool(named:arguments:)` to invoke by name.
- `@LLMToolRepository`: On a type, aggregates all functions whose access is at least as visible as the type (no per-function annotations required) and generates `llmTools` + `dispatchTool(named:arguments:)`.
- DocC parsing: Supports `///`, `//!`, and `/** ... */` (even when the block is placed between an attribute and the function) with `- Parameter` entries recognized.
- Type mapping: `String → string`, `Int → integer`, `Double/Float → number`, `Bool → boolean`, optional handling (`T?` not required), and CaseIterable string-backed enums as `enum` values.
- Diagnostics: Unsupported parameter types emit a compile-time error with guidance.

## Installation (Swift Package Manager)
Add the package to your project using one of the methods below.

### Xcode
- File → Add Packages…
- Enter the URL: `https://github.com/zats/LLMToolSwift`
- Choose the desired version/branch and add the `LLMToolSwift` product.

### Package.swift
```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "YourProject",
    dependencies: [
        // Use a tagged version once available
        //.package(url: "https://github.com/zats/LLMToolSwift", from: "0.1.0"),
        // Or track main during early development
        .package(url: "https://github.com/zats/LLMToolSwift", branch: "main"),
    ],
    targets: [
        .target(name: "YourTarget", dependencies: ["LLMToolSwift"]),
    ]
)
```

## Quick Start
Annotate a function and use the generated static property to obtain its tool schema.

```swift
import LLMToolSwift

public enum TemperatureUnit: String, CaseIterable { case celsius, fahrenheit }

public struct WeatherService {
    /// Provides the current weather for a specified location.
    /// - Parameter location: The city and state, e.g., "San Francisco, CA".
    /// - Parameter unit: The temperature unit to use, either "celsius" or "fahrenheit".
    @LLMTool
    public func getCurrentWeather(location: String, unit: TemperatureUnit) -> String {
        // Your implementation
        "The weather in \(location) is 75° \(unit.rawValue)."
    }
}

// Access the generated tool schema (modern function shape)
let toolJSON = WeatherService.getCurrentWeatherLLMTool.jsonString
print(toolJSON)
```

Example output (minified):

```json
{"name":"get_current_weather","description":"Provides the current weather for a specified location.","strict":true,"parameters":{"type":"object","properties":{"location":{"type":"string","description":"The city and state, e.g., \"San Francisco, CA\"."},"unit":{"type":"string","description":"The temperature unit to use, either \"celsius\" or \"fahrenheit\".","enum":["celsius","fahrenheit"]}},"required":["location","unit"],"additionalProperties":false}}
```
### Aggregate tools + dispatcher
Use `@LLMTools` if you annotate individual functions with `@LLMTool` and want an aggregate plus a dispatcher:

```swift
@LLMTools
struct Calculator {
    /// Adds two integers
    /// - Parameter a: First value
    /// - Parameter b: Second value
    @LLMTool
    func add(a: Int, b: Int) -> Int { a + b }
}

// List all tools
print(Calculator.llmTools.map { $0.function.name }) // ["add"]

// Dispatch by name
let calc = Calculator()
let result = try await calc.dispatchTool(named: "add", arguments: ["a": 2, "b": 3]) as? Int
```

Use `@LLMToolRepository` when you prefer to generate tools and a dispatcher for all eligible functions automatically (no per-function annotations required):

```swift
@LLMToolRepository
struct WeatherRepo {
    /** Summary
     - Parameter city: City name
     */
    func current(city: String) -> String { "Sunny in \(city)" }
}

print(WeatherRepo.llmTools.count) // 1
let repo = WeatherRepo()
let s = try await repo.dispatchTool(named: "current", arguments: ["city": "Lisbon"]) as? String
```

## Supported Types
- String → `string`
- Int → `integer`
- Double/Float → `number`
- Bool → `boolean`
- T? (Optional) → same as `T`, and omitted from `required`
- String-backed `enum` conforming to `CaseIterable` → `string` with `enum` values

Unsupported parameter types emit a compile-time diagnostic.

## Tips
- Doc comments: The first non-empty line becomes the tool description; `- Parameter` lines populate parameter docs.
- Property name: Per-function tool property is `funcName + LLMTool` (e.g., `getCurrentWeatherLLMTool`).
- Access: Generated properties/methods match type visibility; `@LLMToolRepository` includes only functions whose access is at least as visible as the type.

## Sample Client
This package includes a tiny executable target demonstrating usage:

```bash
swift run LLMToolSwiftClient
```

## Development
- Build in a temporary directory to keep the repo clean:
  ```bash
  BUILD_DIR=$(mktemp -d)
  swift build --build-path "$BUILD_DIR"
  swift test --build-path "$BUILD_DIR"
  ```
- Open `Package.swift` in Xcode to explore the library, macro implementation, and tests.

## Roadmap
See `SPEC.md` for the full design and the project TODOs. Contributions, feedback, and ideas are welcome!
