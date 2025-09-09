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

    /// Minified JSON string of the function schema.
    /// Delegates to `jsonSchema(strict: true)` to keep one source of truth.
    public var jsonString: String { jsonSchema(strict: true) }
}
