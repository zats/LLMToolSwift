import Foundation
import LLMToolSwift
import OpenAI

public extension LLMTool {
    // Backward compatibility: keep property returning strict=true by default
    var openAITool: Tool { openAITool(strict: true) }

    /// Build an OpenAI Tool from this LLMTool.
    /// - Parameter strict: If true (default), encodes optional parameters as a union with `null`
    ///   and lists all properties in `required` per OpenAI strict-mode requirements.
    func openAITool(strict: Bool = true) -> Tool {
        let schema = makeOpenAIJSONSchema(from: function.parameters, strict: strict)
        return .functionTool(
            FunctionTool(
                type: "function",
                name: function.name,
                description: function.description.isEmpty ? nil : function.description,
                parameters: schema,
                strict: strict
            )
        )
    }

    private func makeOpenAIJSONSchema(from params: LLMTool.Parameters, strict: Bool) -> JSONSchema {
        var properties: [String: JSONSchema] = [:]
        let requiredSet = Set(params.required)
        let allKeys = Array(params.properties.keys)
        for (name, prop) in params.properties {
            let isOptional = !requiredSet.contains(name)
            properties[name] = makePropertySchema(from: prop, optional: isOptional, strict: strict)
        }
        let requiredKeys = strict ? allKeys.sorted() : params.required
        return JSONSchema.schema(
            .type(.object),
            .properties(properties),
            .required(requiredKeys),
            .additionalProperties(.boolean(false))
        )
    }

    private func makePropertySchema(from prop: LLMTool.Property, optional: Bool, strict: Bool) -> JSONSchema {
        var fields: [JSONSchemaField] = []
        let baseType: JSONSchemaInstanceType
        switch prop.type {
        case .string: baseType = .string
        case .integer: baseType = .integer
        case .number: baseType = .number
        case .boolean: baseType = .boolean
        }

        if strict && optional {
            // Optional fields must admit null in strict mode
            let typeStrings: [String]
            switch baseType {
            case .string: typeStrings = ["string", "null"]
            case .integer: typeStrings = ["integer", "null"]
            case .number: typeStrings = ["number", "null"]
            case .boolean: typeStrings = ["boolean", "null"]
            case .array: typeStrings = ["array", "null"]
            case .object: typeStrings = ["object", "null"]
            case .null: typeStrings = ["null"]
            case .types(let arr): typeStrings = arr
            }
            fields.append(.type(.types(typeStrings)))
        } else {
            fields.append(.type(baseType))
        }

        if !prop.description.isEmpty {
            fields.append(.description(prop.description))
        }
        if let values = prop.enum, !values.isEmpty {
            fields.append(.enumValues(values))
        }
        return JSONSchema(fields: fields)
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
    var argumentsDictioanry: [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = json as? [String: Any]
        else { return [:] }
        return dict
    }
}
