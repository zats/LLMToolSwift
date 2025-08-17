import Foundation

public enum LLMToolCallError: Error, CustomStringConvertible, Equatable {
    case functionNotFound(String)
    case missingArgument(String)
    case typeMismatch(param: String, expected: String)
    case invalidEnumValue(param: String, value: String)

    public var description: String {
        switch self {
        case .functionNotFound(let name):
            return "LLMTool call error: function not found: \(name)"
        case .missingArgument(let name):
            return "LLMTool call error: missing argument: \(name)"
        case .typeMismatch(let param, let expected):
            return "LLMTool call error: type mismatch for \(param), expected \(expected)"
        case .invalidEnumValue(let param, let value):
            return "LLMTool call error: invalid enum value for \(param): \(value)"
        }
    }
}

