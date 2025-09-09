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
    /// Instance types of the property (union), e.g. [.string] or [.string, .null].
    public let types: [LLMTool.PropertyType]
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
            var types: [LLMTool.PropertyType] = [prop.type]
            if strict && isOptional { types.append(.null) }
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
}
