# LLMToolSwift

Use inline documentation to create LLM-compatible tools from native Swift functions

## 1) Annotated Tools Repo

```swift
import LLMToolSwift

@LLMTools
struct ToolsRepository {
    /// Greet a person
    /// - Parameter name: Person name (defaults to "World")
    @LLMTool
    func greet(name: String = "World") -> String { "Hello, \(name)!" }

    /// Add two numbers
    /// - Parameter a: First
    /// - Parameter b: Second
    @LLMTool
    func add(a: Int, b: Int) -> Int { a + b }
}

let repo = ToolsRepository()
// Pass your tools to the LLM of your choice (see built in integrations below
let tools = repo.llmTools

// Handle a tool call (name + JSON args)
let result = try await repo.dispatchLLMTool(named: "greet", arguments: ["name": "Sam"]) as? String
let usesDefault = try await repo.dispatchLLMTool(named: "greet", arguments: [:]) as? String // "Hello, World!"
```

Parameters with Swift default values are treated as optional in the generated schema; if an argument is missing (or `NSNull`), dispatch uses the function’s default. Provided values still override the default with normal type checking. You can also override a tool’s name with `@LLMTool(name: "read_file")`; by default it matches the Swift function name.

## 2) Tools to JSON Schema

```swift
import LLMToolSwift

struct Weather {
    /// Get forecast
    /// - Parameter city: City name
    @LLMTool
    func forecast(city: String) {}
}

let tool = Weather.forecastLLMTool

print(tool.jsonSchema())
// Resulting JSON can be emdedded into system prompt,
// you will need to detect LLM tool calls in its responses later
// {"name":"forecast","strict":true,"parameters":{...}}
// Defaulted parameters are omitted from `required`.
// Tool name defaults to the Swift function name; override with @LLMTool(name: "...").
```

## 3) MacPaw OpenAI

```swift
import LLMToolSwift
import LLMToolOpenAI
import OpenAI

let allTools = ToolsRepository()
let oaiTools: [Tool] = allTools.llmTools.openAITools()
// Pass `oaiTools` to your OpenAI client when creating the session/request.

// Later, when OpenAI returns a function tool call:
func handle(call: Components.Schemas.FunctionToolCall) async throws -> String {
    let args = call.argumentsDictionary // [String: Any]
    let out = try await repo.dispatchLLMTool(named: call.name, arguments: args)
    return String(describing: out) // send back per SDK’s API
}
```

Install via SwiftPM: add `.package(url: "https://github.com/zats/LLMToolSwift", branch: "main")` and depend on `LLMToolSwift` (and `LLMToolOpenAI` if you need the OpenAI integration).
