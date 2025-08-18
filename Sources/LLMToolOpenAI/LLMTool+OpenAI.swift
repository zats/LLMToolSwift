import Foundation
import LLMToolSwift
import OpenAI

public extension LLMTool {
    var openAITool: Tool {
        let schema = makeOpenAIJSONSchema(from: function.parameters)
        return .functionTool(
            FunctionTool(
                type: type,
                name: function.name,
                description: function.description.isEmpty ? nil : function.description,
                parameters: schema,
                strict: true
            )
        )
    }

    private func makeOpenAIJSONSchema(from params: LLMTool.Parameters) -> JSONSchema {
        var properties: [String: JSONSchema] = [:]
        for (name, prop) in params.properties {
            properties[name] = makePropertySchema(from: prop)
        }
        return JSONSchema.schema(
            .type(.object),
            .properties(properties),
            .required(params.required),
            .additionalProperties(.boolean(false))
        )
    }

    private func makePropertySchema(from prop: LLMTool.Property) -> JSONSchema {
        var fields: [JSONSchemaField] = []
        switch prop.type {
        case .string: fields.append(.type(.string))
        case .integer: fields.append(.type(.integer))
        case .number: fields.append(.type(.number))
        case .boolean: fields.append(.type(.boolean))
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
    var openAITools: [Tool] { map { $0.openAITool } }
}

