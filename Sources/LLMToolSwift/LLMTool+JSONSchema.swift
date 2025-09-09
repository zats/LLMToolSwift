import Foundation

public extension LLMTool {
    /// Encode the OpenAI-compatible function schema for this tool, including `strict` and `parameters`.
    /// Uses the normalized schema SPI to ensure one source of truth.
    func jsonSchema(strict: Bool = true) -> String {
        let model = normalizedSchema(strict: strict)

        var properties: [String: PropertySchema] = [:]
        for (name, p) in model.parameters.properties {
            let typeField: TypeField = (p.types.count == 1) ? .single(p.types[0]) : .multiple(p.types)
            properties[name] = PropertySchema(type: typeField,
                                             description: p.description,
                                             enumValues: p.enumValues)
        }

        let paramsSchema = ParametersSchema(
            type: "object",
            properties: properties,
            required: model.parameters.required,
            additionalProperties: model.parameters.additionalProperties
        )

        let functionSchema = FunctionSchema(
            name: model.name,
            description: model.description,
            strict: model.strict,
            parameters: paramsSchema
        )

        let encoder = JSONEncoder()
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            encoder.outputFormatting.insert(.withoutEscapingSlashes)
        }
        if let jsonData = try? encoder.encode(functionSchema), let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }
}

// MARK: - Codable schema helpers

private struct ParametersSchema: Encodable {
    let type: String // "object"
    let properties: [String: PropertySchema]
    let required: [String]
    let additionalProperties: Bool
}

private struct FunctionSchema: Encodable {
    let name: String
    let description: String?
    let strict: Bool
    let parameters: ParametersSchema
}

private struct PropertySchema: Encodable {
    let type: TypeField // either a single string or [String]
    let description: String?
    let enumValues: [String]?

    enum CodingKeys: String, CodingKey { case type, description, `enum` }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        if let description { try c.encode(description, forKey: .description) }
        if let enumValues { try c.encode(enumValues, forKey: .enum) }
    }
}

private enum TypeField: Encodable {
    case single(String)
    case multiple([String])

    func encode(to encoder: Encoder) throws {
        var sv = encoder.singleValueContainer()
        switch self {
        case .single(let s): try sv.encode(s)
        case .multiple(let a): try sv.encode(a)
        }
    }
}
