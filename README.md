# LLMToolSwift

Swift macros that generate OpenAI-style LLM tool schemas from documented Swift functions. Annotate a function with `@LLMTool` and a static `<funcName>LLMTool` property is generated that describes the function and its parameters. Use `jsonString` to get a minified JSON schema you can pass to LLMs.

- URL: https://github.com/zats/LLMToolSwift
- Swift: 6.2 (macOS 10.15+/iOS 13+)

## Features
- `@LLMTool` attached peer macro generates `<funcName>LLMTool` with matching access level.
- Parses DocC comments (`///`), using the first line as the tool description and `- Parameter` lines for parameter descriptions.
- Maps Swift parameter types to JSON Schema types: `String → string`, `Int → integer`, `Double/Float → number`, `Bool → boolean`, with optional-handling (`T?` not required).
- String-backed, `CaseIterable` enums produce an `enum` list for values (best-effort static extraction, with dynamic fallback via `EnumType.allCases.map(\.rawValue)`).
- Clear diagnostics for unsupported parameter types.

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

// Access the generated tool schema
let toolJSON = WeatherService.getCurrentWeatherLLMTool.jsonString
print(toolJSON)
```

Example output (minified):

```json
{"type":"function","function":{"name":"getCurrentWeather","description":"Provides the current weather for a specified location.","parameters":{"type":"object","properties":{"location":{"type":"string","description":"The city and state, e.g., \"San Francisco, CA\"."},"unit":{"type":"string","description":"The temperature unit to use, either \"celsius\" or \"fahrenheit\".","enum":["celsius","fahrenheit"]}},"required":["location","unit"]}}}
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
- Description is taken from the first line of the function’s DocC comments; parameter descriptions from `- Parameter` lines.
- The generated property name is the function name plus `LLMTool` (e.g., `getCurrentWeatherLLMTool`).
- The property’s access level matches the function’s access level.

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
