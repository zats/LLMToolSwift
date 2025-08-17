import Foundation

public struct LLMTool: Encodable, Equatable {
    public let type: String = "function"
    public let function: Function

    public init(function: Function) {
        self.function = function
    }

    public struct Function: Encodable, Equatable {
        public let name: String
        public let description: String
        public let parameters: Parameters

        public init(name: String, description: String, parameters: Parameters) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
    }

    public struct Parameters: Encodable, Equatable {
        public let type: String = "object"
        public let properties: [String: Property]
        public let required: [String]

        public init(properties: [String: Property], required: [String]) {
            self.properties = properties
            self.required = required
        }
    }

    public struct Property: Encodable, Equatable {
        public let type: String
        public let description: String
        public let `enum`: [String]?

        public init(type: String, description: String, enum values: [String]? = nil) {
            self.type = type
            self.description = description
            self.enum = values
        }
    }

    /// Minified JSON string of the function definition following the
    /// modern function tool schema (name/description/strict/parameters) without the legacy wrapper.
    /// This shape matches typical LLM function tool expectations.
    public var jsonString: String {
        struct Out: Encodable {
            struct Params: Encodable {
                let type: String
                let properties: [String: LLMTool.Property]
                let required: [String]
                let additionalProperties: Bool
            }
            let name: String
            let description: String
            let strict: Bool
            let parameters: Params
        }

        let out = Out(
            name: LLMTool.snakeCase(function.name),
            description: function.description,
            strict: true,
            parameters: .init(
                type: "object",
                properties: function.parameters.properties,
                required: function.parameters.required,
                additionalProperties: false
            )
        )

        let encoder = JSONEncoder()
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            encoder.outputFormatting.insert(.withoutEscapingSlashes)
        }
        guard let data = try? encoder.encode(out),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private static func snakeCase(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var result = ""
        for (i, ch) in s.enumerated() {
            if ch.isUppercase {
                if i != 0 { result.append("_") }
                result.append(ch.lowercased())
            } else {
                result.append(ch)
            }
        }
        return result
    }
}
