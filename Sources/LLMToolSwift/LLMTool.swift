import Foundation

public struct LLMTool: Codable, Equatable {
    public let type: String = "function"
    public let function: Function

    public init(function: Function) {
        self.function = function
    }

    public struct Function: Codable, Equatable {
        public let name: String
        public let description: String
        public let parameters: Parameters

        public init(name: String, description: String, parameters: Parameters) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
    }

    public struct Parameters: Codable, Equatable {
        public let type: String = "object"
        public let properties: [String: Property]
        public let required: [String]

        public init(properties: [String: Property], required: [String]) {
            self.properties = properties
            self.required = required
        }
    }

    public struct Property: Codable, Equatable {
        public let type: String
        public let description: String
        public let `enum`: [String]?

        public init(type: String, description: String, enum values: [String]? = nil) {
            self.type = type
            self.description = description
            self.enum = values
        }
    }

    /// Minified JSON string compatible with OpenAI-style tool schema.
    public var jsonString: String {
        let encoder = JSONEncoder()
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            encoder.outputFormatting.insert(.withoutEscapingSlashes)
        }
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

