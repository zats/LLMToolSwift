# LLMToolSwift

Swift macros that generate OpenAI-style LLM tool schemas from documented Swift functions and an optional dispatcher to invoke them by name.

## Simple Usage

```swift
import Foundation
import LLMToolSwift

@LLMTools
final class MyFunctionRegistry {
    /**
     Fetches weather information for a specified location using an LLM tool.
     
     Use this method to retrieve up-to-date weather data for a given location. The method is asynchronous and may throw an error if the retrieval fails.
     
     - Parameter location: A string specifying the geographic location for which to fetch weather information.
     - Throws: An error if the weather data could not be retrieved or processed.
     - Returns: A string containing the weather information for the specified location.
     */
    @LLMTool
    func getWeather(location: String) async throws -> String {
        "Weather in \(location) is meh"
    }
    
    /**
     Retrieves the current stock price for the specified stock symbol using an LLM tool.
     
     Use this method to fetch up-to-date stock pricing information for a given symbol. The method is asynchronous and may throw an error if retrieval fails.
     
     - Parameter symbol: A string specifying the stock symbol (e.g., "AAPL" for Apple Inc.)
     - Throws: An error if the stock price could not be retrieved or processed.
     - Returns: A string containing the current stock price for the specified symbol.
     */
    @LLMTool
    func getStockPrice(symbol: String) async throws -> String {
        "The current price of \(symbol) is $123.45"
    }
}
```

vanilla example building on the previously defined class:

```swift
let myFunctionRegistry = MyFunctionRegistry()

// When setting up your LLM session.
// Pass myFunctionRegistry.llmTools to LLM 
// For OpenAI responses API it can look like this
// (you will need to map llmTools to specific SDK tool type)
CreateModelResponseQuery(
    input: .textInput(query),
    model: .gpt5,
    toolChoice: .ToolChoiceOptions(.auto),
    tools: myFunctionRegistry.llmTools.openAITools(strict: true)
)

// Later when LLM decides to call a tool, 
// you need to pass tool name and arguments back to the registry
// (use your custom string converstion logic)
let result = try await myFunctionRegistry.dispatchLLMTool(named: call.name, arguments: args) as! String

// then you need to pass `result` back to LLM
// OpenAI responses API will need to use 
let toolCallResult = InputItem.item(.functionCallOutputItemParam(.init(callId: id, _type: .functionCallOutput, output: result)))
// refer to your LLM SDK of choice to see how to return the tool call results back to LLM
```

—

Swift macros that generate OpenAI-style LLM tool schemas from documented Swift functions. Annotate a function with `@LLMTool` and a static `<funcName>LLMTool` property is generated that describes the function and its parameters. Use either the built-in `jsonString` property or the `LLMToolJSONSchema` module’s `jsonSchema(strict:)` to get a minified function schema you can pass to LLMs.

- URL: https://github.com/zats/LLMToolSwift
- Swift: 6.0 (macOS 10.15+/iOS 13+)

## Features
- `@LLMTool`: Generates `<funcName>LLMTool` with matching access level for per-function tool schemas.
- `@LLMTools`: Apply to a type to aggregate all functions annotated with `@LLMTool` into a static `llmTools` array and synthesize an instance method `dispatchLLMTool(named:arguments:)` that calls the matching function with validated, converted arguments. The annotated type automatically conforms to `LLMToolsRepository` (when used at file scope).
- DocC parsing: Supports `///`, `//!`, and `/** ... */` (even when the block is placed between an attribute and the function) with `- Parameter` entries recognized.
- Type mapping: `String → string`, `Int → integer`, `Double/Float → number`, `Bool → boolean`, optional handling (`T?` not required), and CaseIterable string-backed enums as `enum` values.
- Diagnostics: Unsupported parameter types emit a compile-time error with guidance.

### OpenAI integration and strict mode
- `import LLMToolOpenAI` to convert `LLMTool` to OpenAI `Tool` types.
- `tool.openAITool(strict: Bool = true)`: Build a single OpenAI tool.
  - When `strict` is true (default):
    - Optional parameters are encoded as a union with `null` (e.g., `"type":["string","null"]`).
    - The `required` array lists all properties (OpenAI strict-mode behavior).
  - When `strict` is false:
    - Optional parameters are not unioned with `null`.
    - The `required` array contains only actually required properties.
- For arrays: `MyFunctionRegistry.llmTools.openAITools(strict: ...)`.

### JSON Schema (OpenAI-compatible)
- `import LLMToolJSONSchema` to produce the function schema for OpenAI function calling or adding to LLM of your choice _raw_.
- `tool.jsonSchema(strict: Bool = true) -> String` returns minified JSON with `{ name, description?, strict, parameters }`.

```swift
import LLMToolSwift
import LLMToolJSONSchema

struct WeatherService {
    /// Get forecast
    /// - Parameter city: City name.
    /// - Parameter units: Units system (metric/imperial).
    @LLMTool
    func forecast(city: String, units: String?) {}
}

let tool = WeatherService.forecastLLMTool
let schema = tool.jsonSchema(strict: true)
print(schema)
// {"name":"forecast","description":"Get forecast","strict":true,
//  "parameters":{"type":"object","properties":{"city":{...},"units":{...}},
//  "required":["city","units"],"additionalProperties":false}}
```

Add the module product to your target to emit schema JSON:

```swift
// In your Package.swift target dependencies
.product(name: "LLMToolJSONSchema", package: "LLMToolSwift")
```

## Installation (Swift Package Manager)
Add the package to your project using one of the methods below.

### Xcode
- File → Add Packages…
- Enter the URL: `https://github.com/zats/LLMToolSwift`
- Choose the desired version/branch and add the `LLMToolSwift` product.

### Package.swift
```swift
// swift-tools-version: 6.0
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
- Access: Generated properties/methods match type visibility.
- Scope tip: Apply `@LLMTools` at file scope to also get automatic `LLMToolsRepository` conformance. Attaching `@LLMTools` to local types (inside functions) is not supported.


## Development
- Build in a temporary directory to keep the repo clean:
  ```bash
  BUILD_DIR=$(mktemp -d)
  swift build --build-path "$BUILD_DIR"
  swift test --build-path "$BUILD_DIR"
  ```
- Open `Package.swift` in Xcode to explore the library, macro implementation, and tests.
