Swift Package Specification: LLMToolSwift
1. Overview
This document specifies a Swift package, LLMToolSwift, which provides a Swift macro to streamline the process of exposing functions to Large Language Models (LLMs) for tool-calling (e.g., OpenAI's Function Calling feature).

The core of the package is an attached peer macro, @LLMTool, that can be applied to any function. The macro will generate a static, computed property that returns a strongly-typed LLMTool struct. This struct contains a complete, serializable representation of the function's signature, which can then be easily converted into various formats, such as the JSON schema required by the OpenAI API.

The macro will also perform compile-time validation to ensure that the decorated function's parameters are of types compatible with the schema, providing clear errors if they are not.

2. Project Goals
Simplicity: Provide a simple, declarative way (@LLMTool) to expose Swift functions to LLMs.

Type Safety: Leverage the Swift compiler to ensure, at compile-time, that only functions with compatible signatures can be exposed.

Flexibility: Provide a strongly-typed, intermediate representation (LLMTool struct) of the tool definition, decoupling it from any specific JSON format.

Automation: Automatically generate the required schema, reducing boilerplate and the potential for manual errors.

Clarity: Use standard Apple documentation comments (DocC format) as the source for function and parameter descriptions in the generated schema.

Testability: The package must be thoroughly tested to cover both valid and invalid use cases.

3. Detailed Specification
3.1. Public LLMTool Struct Definition
The package will expose a public, Codable struct that serves as the canonical representation for a tool.

public struct LLMTool: Codable, Equatable {
    public let type: String = "function"
    public let function: Function

    public struct Function: Codable, Equatable {
        public let name: String
        public let description: String
        public let parameters: Parameters
    }

    public struct Parameters: Codable, Equatable {
        public let type: String = "object"
        public let properties: [String: Property]
        public let required: [String]
    }

    public struct Property: Codable, Equatable {
        public let type: String
        public let description: String
        public let `enum`: [String]?
    }

    /// Provides a minified JSON string representation compatible with the OpenAI API.
    public var jsonString: String {
        let encoder = JSONEncoder()
        // Configure for minified output
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}" // Should be unreachable
        }
        return json
    }
}

3.2. Macro Definition
The package will provide a single macro: @LLMTool.

Name: LLMTool

Type: Attached Peer Macro (@attached(peer)).

Target: Can only be applied to functions.

3.3. Usage Example
public struct WeatherService {
    /// Provides the current weather for a specified location.
    /// - Parameter location: The city and state, e.g., "San Francisco, CA".
    /// - Parameter unit: The temperature unit to use, either "celsius" or "fahrenheit".
    /// - Returns: A string describing the current weather conditions.
    @LLMTool
    public func getCurrentWeather(location: String, unit: TemperatureUnit) -> String {
        // ... function implementation
        return "The weather in \(location) is 75° \(unit.rawValue)."
    }
}

public enum TemperatureUnit: String, CaseIterable {
    case celsius
    case fahrenheit
}

// Later, when preparing tools for an API call:
let weatherToolJSON = WeatherService.getCurrentWeatherLLMTool.jsonString

3.4. Generated Code
The @LLMTool macro will generate a peer property within the scope of the parent type (e.g., WeatherService).

// Generated within the scope of WeatherService
public static var getCurrentWeatherLLMTool: LLMTool {
    LLMTool(
        function: .init(
            name: "getCurrentWeather",
            description: "Provides the current weather for a specified location.",
            parameters: .init(
                properties: [
                    "location": .init(
                        type: "string",
                        description: "The city and state, e.g., \\"San Francisco, CA\\".",
                        enum: nil
                    ),
                    "unit": .init(
                        type: "string",
                        description: "The temperature unit to use, either \\"celsius\\" or \\"fahrenheit\\".",
                        enum: ["celsius", "fahrenheit"]
                    )
                ],
                required: ["location", "unit"]
            )
        )
    )
}

3.5. Generation Logic
The macro will parse the function declaration and its documentation comments to populate an LLMTool struct instance.

Function Name (function.name): The name of the Swift function.

Function Description (function.description): The main summary from the documentation comment.

Parameters (function.parameters.properties):

Each function parameter becomes a key-value pair in the properties dictionary.

The description is taken from the /// - Parameter <name>: line.

The type is determined by mapping the Swift type to a JSON schema type (see table below).

Required Parameters (function.parameters.required): Any non-optional parameter name is added to this array.

Visibility: The generated static property will automatically match the visibility of the original function (e.g., public, internal, private).

Static Context: The generated property will always be static, allowing it to be accessed at the type level (e.g., WeatherService.getCurrentWeatherLLMTool), even if the decorated function is an instance method.

Return Type (Ignored): The function's return type and its documentation will be ignored.

3.6. Type Compatibility & Validation
The macro will perform a compile-time check on the types of all parameters.

Swift Type

JSON Schema Type

Notes

String

string



Int

integer



Double

number



Float

number



Bool

boolean



T? (Optional)

(Same as T)

The parameter will be omitted from the required array.

Enum (String-backed, CaseIterable)

string

The macro will populate the enum field in the Property struct.

Compile-Time Error Example:

@LLMTool Error: The type 'Date' for parameter 'date' is not supported. LLM tools only support String, Int, Double, Float, Bool, and String-backed Enums.

4. Open Questions & Decisions Needed
Project Naming: Package is named LLMToolSwift; macro remains @LLMTool.

Description Source: I've assumed we will use Swift's documentation comments (///). Is this the right approach, or would you prefer passing descriptions as arguments to the macro, like @LLMTool(description: "...")?

5. TODO

- [x] Define `LLMTool` types in the library target (`Sources/LLMToolSwift`), matching the Codable/Equatable structure and `jsonString` behavior.
- [x] Implement `@LLMTool` as an attached peer macro in `Sources/LLMToolSwiftMacros`, generating `<funcName>LLMTool` static property with matching access level.
- [x] Parse DocC comments for summary and `- Parameter` lines to populate `description` and `properties`.
- [x] Map Swift types to schema types and validate: `String`, `Int`, `Double/Float -> number`, `Bool`, `Optional` handling; best-effort enum detection (same-file, CaseIterable/String-backed).
- [x] Emit diagnostics for unsupported types (e.g., `Date`) with clear guidance; currently lenient (no error) to ease adoption.
- [ ] Add robust macro tests (formatting-tolerant) for: expansion, enum handling, optionals, access control, and diagnostics.
- [x] Provide a minimal usage example in `LLMToolSwiftClient` demonstrating `@LLMTool` and `jsonString`.
- [x] Align naming between SPEC (LLMToolSwift/@LLMTool) and package (`Package.swift` currently `LLMToolSwift`).
- [ ] Document the mapping table and usage in README/docs; update `SPEC.md` when behavior changes.
- [ ] (Optional) Set up CI to run `swift build` and `swift test` on macOS with the appropriate Swift toolchain.

Function Name Override: Should a developer be able to override the function name? We could add a parameter like @LLMTool(name: "get_current_weather"). Is this necessary for V1?

Complex Types (Future Scope?): How should we handle nested structs? Is this a requirement for the first version?

Default Values: How should we handle parameters with default values (e.g., func search(query: String, limit: Int = 20))? Should they be considered non-required?

5. Testing Plan
5.1. Correct Usage (Happy Path) Tests
[ ] Test that the generated LLMTool struct correctly reflects a function with no parameters.

[x] Test a function with a single String parameter.

[ ] Test a function with all supported primitive types.

[ ] Test an optional parameter and verify it is not in the required array.

[ ] Test a String backed, CaseIterable enum and verify the enum field is correctly generated.

[ ] Test that multi-line documentation comments are parsed correctly.

[ ] Test that a function with a return type is parsed correctly (i.e., return info is ignored).

[ ] Test that the jsonString computed property produces valid, minified JSON.

[x] Test that a public function generates a public static property.

[ ] Test that an internal function generates an internal static property.

5.2. Incorrect Usage (Error Path) Tests
[ ] Test that applying the macro to a struct or class fails compilation.

[ ] Test that a function with an unsupported parameter type fails compilation.

[ ] Test that a function missing a parameter documentation comment fails compilation.

[ ] Test that an enum parameter that is not String-backed fails compilation.
