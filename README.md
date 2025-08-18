# LLMToolSwift

Swift macros that generate OpenAI-style LLM tool schemas from documented Swift functions and an optional dispatcher to invoke them by name.

## Simple Usage

```swift
import LLMToolSwift

@LLMToolRepository
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
        "Weahter in \(location) is meh"
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

and then later to consume you can either use manual mapping or take advantage of built in one with 

```swift
import OpenAI
import LLMToolOpenAI

final class MyViewModel {
    let client: OpenAI
    let functionRegistry: MyFunctionRegistry
    
    func createResponse(for query: String) -> CreateModelResponseQuery {
        return CreateModelResponseQuery(
            input: .textInput(query),
            model: .gpt5,
            toolChoice: .ToolChoiceOptions(.auto),
            tools: MyFunctionRegistry.llmTools.map { $0.openAITool }
        )
    }
    
    func handleLLMToolCall(_ call: Components.Schemas.FunctionToolCall) async throws {
        guard let args = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any],
              let result = try await functionRegistry.dispatchLLMTool(named: call.name, arguments: args) as? String
        else {
            fatalError("Failed to process LLMTool call")
        }
        saveLLMToolResult(call.id, result)
    }
    
    private func saveLLMToolResult(_ id: String?, _ result: String) {
        guard let id else { return }
        let output = InputItem.item(.functionCallOutputItemParam(.init(callId: id, _type: .functionCallOutput, output: result)))
        // accumulate all the tool calls and pass results back to LLM on the next turn
    }
}
```

—

Swift macros that generate OpenAI-style LLM tool schemas from documented Swift functions. Annotate a function with `@LLMTool` and a static `<funcName>LLMTool` property is generated that describes the function and its parameters. Use `jsonString` to get a minified JSON schema you can pass to LLMs.

- URL: https://github.com/zats/LLMToolSwift
- Swift: 6.2 (macOS 10.15+/iOS 13+)

## Features
- `@LLMTool`: Generates `<funcName>LLMTool` with matching access level for per-function tool schemas.
- `@LLMTools`: On a type, aggregates all `@LLMTool`-annotated functions into `static var llmTools` and generates `async throws func dispatchLLMTool(named:arguments:)` to invoke by name.
- `@LLMToolRepository`: On a type, aggregates all functions whose access is at least as visible as the type (no per-function annotations required) and generates `llmTools` + `dispatchLLMTool(named:arguments:)`.
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
