import Foundation
import LLMToolSwift

public extension LLMTool {
    /// Encode the OpenAI-compatible function schema for this tool, including `strict` and `parameters`.
    /// - Parameter strict: When true (default), marks all properties as required and
    ///   encodes optional properties as a union with `null` per OpenAI strict mode guidance.
    /// - Returns: Minified UTF-8 JSON string of `{ name, description?, strict, parameters }`.
    func jsonSchema(strict: Bool = true) -> String {
        // Build properties map
        let params = function.parameters
        let requiredSet = Set(params.required)

        var properties: [String: PropertySchema] = [:]
        for (name, prop) in params.properties {
            let isOptional = !requiredSet.contains(name)
            let base = Self.baseTypeString(for: prop.type)
            let typeField: TypeField = (strict && isOptional)
                ? .multiple([base, "null"]) // optional admits null in strict mode
                : .single(base)

            let desc = prop.description.isEmpty ? nil : prop.description
            let enums = (prop.enum?.isEmpty == false) ? prop.enum : nil
            properties[name] = PropertySchema(type: typeField, description: desc, enumValues: enums)
        }

        let requiredKeys: [String]
        if strict {
            requiredKeys = Array(params.properties.keys).sorted()
        } else {
            requiredKeys = params.required
        }

        let paramsSchema = ParametersSchema(
            type: "object",
            properties: properties,
            required: requiredKeys,
            additionalProperties: false
        )

        let encoder = JSONEncoder()
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            encoder.outputFormatting.insert(.withoutEscapingSlashes)
        }
        // Wrap into function-level schema with strict flag.
        let desc = function.description.isEmpty ? nil : function.description
        let functionSchema = FunctionSchema(
            name: function.name,
            description: desc,
            strict: strict,
            parameters: paramsSchema
        )

        // Intentionally avoid pretty printing; callers can reformat if needed.
        if let jsonData = try? encoder.encode(functionSchema), let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    // MARK: - Helpers

    private static func baseTypeString(for t: LLMTool.PropertyType) -> String {
        switch t {
        case .string: return "string"
        case .integer: return "integer"
        case .number: return "number"
        case .boolean: return "boolean"
        }
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
