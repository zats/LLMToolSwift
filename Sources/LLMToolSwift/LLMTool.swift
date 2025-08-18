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

    public enum PropertyType: String, Encodable, Equatable {
        case string
        case integer
        case number
        case boolean
    }

    public struct Property: Encodable, Equatable {
        public let type: PropertyType
        public let description: String
        public let `enum`: [String]?

        // Preferred initializer using strong-typed PropertyType
        public init(type: PropertyType, description: String, enum values: [String]? = nil) {
            self.type = type
            self.description = description
            self.enum = values
        }

        // Backwards-compatible initializer used by existing macro generation
        public init(type: String, description: String, enum values: [String]? = nil) {
            self.type = PropertyType(rawValue: type) ?? .string
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
            name: function.name,
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
}
