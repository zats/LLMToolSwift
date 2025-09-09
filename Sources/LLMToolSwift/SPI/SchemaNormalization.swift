import Foundation

// Shared schema model for internal/adaptor reuse.
// Marked as SPI so only friend modules opt-in to use it.
@_spi(Schema) public struct NormalizedFunctionSchema {
    public let name: String
    public let description: String?
    public let strict: Bool
    public let parameters: NormalizedParametersSchema
}

@_spi(Schema) public struct NormalizedParametersSchema {
    public let properties: [String: NormalizedProperty]
    public let required: [String]
    public let additionalProperties: Bool
}

@_spi(Schema) public struct NormalizedProperty {
    /// JSON Schema instance type names, e.g. ["string"] or ["string","null"].
    public let types: [String]
    public let description: String?
    public let enumValues: [String]?
}

@_spi(Schema) public extension LLMTool {
    /// Produce a provider-agnostic, normalized function schema used by adapters.
    func normalizedSchema(strict: Bool) -> NormalizedFunctionSchema {
        let params = function.parameters
        let requiredSet = Set(params.required)

        var props: [String: NormalizedProperty] = [:]
        for (name, prop) in params.properties {
            let isOptional = !requiredSet.contains(name)
            let base = Self.baseTypeString(for: prop.type)
            let types = (strict && isOptional) ? [base, "null"] : [base]
            let desc = prop.description.isEmpty ? nil : prop.description
            let enums = (prop.enum?.isEmpty == false) ? prop.enum : nil
            props[name] = NormalizedProperty(types: types, description: desc, enumValues: enums)
        }

        let requiredKeys: [String] = strict ? Array(params.properties.keys).sorted() : params.required

        let normParams = NormalizedParametersSchema(
            properties: props,
            required: requiredKeys,
            additionalProperties: false
        )

        let desc = function.description.isEmpty ? nil : function.description
        return NormalizedFunctionSchema(
            name: function.name,
            description: desc,
            strict: strict,
            parameters: normParams
        )
    }

    // Base mapping used by normalization
    static func baseTypeString(for t: LLMTool.PropertyType) -> String {
        switch t {
        case .string: return "string"
        case .integer: return "integer"
        case .number: return "number"
        case .boolean: return "boolean"
        }
    }
}

