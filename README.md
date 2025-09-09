# LLMToolSwift

Swift macros for LLM “tools”: annotate functions, get schemas, and dispatch calls.

– Swift 6 • macOS 10.15+/iOS 13+ • Products: `LLMToolSwift`, `LLMToolOpenAI`

## 1) Annotated Tools Repo

```swift
import LLMToolSwift

@LLMTools
struct Repo {
    /// Greet a person
    /// - Parameter name: Person name
    @LLMTool
    func greet(name: String) -> String { "Hello, \(name)!" }

    /// Add two numbers
    /// - Parameter a: First
    /// - Parameter b: Second
    @LLMTool
    func add(a: Int, b: Int) -> Int { a + b }
}

let repo = Repo()
// Tools to wire into your LLM
let tools = repo.llmTools

// Handle a tool call (name + JSON args)
let result = try await repo.dispatchLLMTool(named: "greet", arguments: ["name": "Sam"]) as? String
```

## 2) JSON Schema (print it)

```swift
import LLMToolSwift

struct Weather {
    /// Get forecast
    /// - Parameter city: City name
    @LLMTool
    func forecast(city: String) {}
}

let tool = Weather.forecastLLMTool
print(tool.jsonSchema(strict: true))
// {"name":"forecast","strict":true,"parameters":{...}}
```

## 3) MacPaw OpenAI

```swift
import LLMToolSwift
import LLMToolOpenAI
import OpenAI

let repo = Repo()
let oaiTools: [Tool] = repo.llmTools.openAITools(strict: true)
// Pass `oaiTools` to your OpenAI client when creating the session/request.

// Later, when OpenAI returns a function tool call:
func handle(call: Components.Schemas.FunctionToolCall) async throws -> String {
    let args = call.argumentsDictionary // [String: Any]
    let out = try await repo.dispatchLLMTool(named: call.name, arguments: args)
    return String(describing: out) // send back per SDK’s API
}
```

Install via SwiftPM: add `.package(url: "https://github.com/zats/LLMToolSwift", branch: "main")` and depend on `LLMToolSwift` (and `LLMToolOpenAI` if you need the OpenAI integration).

