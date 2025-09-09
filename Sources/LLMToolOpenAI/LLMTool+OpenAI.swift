import Foundation
@_spi(Schema) import LLMToolSwift
import OpenAI

public extension LLMTool {
    // Backward compatibility: keep property returning strict=true by default
    var openAITool: Tool { openAITool(strict: true) }

    /// Build an OpenAI Tool from this LLMTool using the normalized core schema.
    /// - Parameter strict: If true (default), encodes optional parameters as a union with `null`
    ///   and lists all properties in `required` per OpenAI strict-mode requirements.
    func openAITool(strict: Bool = true) -> Tool {
        let model = normalizedSchema(strict: strict)

        var properties: [String: JSONSchema] = [:]
        for (name, prop) in model.parameters.properties {
            var fields: [JSONSchemaField] = []
            if prop.types.count == 1, let only = prop.types.first {
                fields.append(.type(Self.mapType(only)))
            } else {
                fields.append(.type(.types(prop.types)))
            }
            if let d = prop.description { fields.append(.description(d)) }
            if let enums = prop.enumValues, !enums.isEmpty { fields.append(.enumValues(enums)) }
            properties[name] = JSONSchema(fields: fields)
        }

        let schema = JSONSchema.schema(
            .type(.object),
            .properties(properties),
            .required(model.parameters.required),
            .additionalProperties(.boolean(model.parameters.additionalProperties))
        )

        return .functionTool(
            FunctionTool(
                type: "function",
                name: model.name,
                description: model.description,
                parameters: schema,
                strict: model.strict
            )
        )
    }

    private static func mapType(_ s: String) -> JSONSchemaInstanceType {
        switch s {
        case "string": return .string
        case "integer": return .integer
        case "number": return .number
        case "boolean": return .boolean
        case "null": return .null
        case "array": return .array
        case "object": return .object
        default: return .types([s])
        }
    }
}

public extension Array where Element == LLMTool {
    var openAITools: [Tool] {
        map { $0.openAITool(strict: true) }
    }
    
    func openAITools(strict: Bool = true) -> [Tool] {
        map { $0.openAITool(strict: strict) }
    }
}

public extension Components.Schemas.FunctionToolCall {
    var argumentsDictionary: [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = json as? [String: Any]
        else { return [:] }
        return dict
    }
}
