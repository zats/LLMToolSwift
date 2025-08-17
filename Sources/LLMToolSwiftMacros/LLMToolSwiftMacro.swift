import SwiftCompilerPlugin
import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `stringify` macro, which takes an expression
/// of any type and produces a tuple containing the value of that expression
/// and the source code that produced the value. For example
///
///     #stringify(x + y)
///
///  will expand to
///
///     (x + y, "x + y")
public struct StringifyMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) -> ExprSyntax {
        guard let argument = node.arguments.first?.expression else {
            fatalError("compiler bug: the macro does not have any arguments")
        }

        return "(\(argument), \(literal: argument.description))"
    }
}

// MARK: - LLMTool Peer Macro

enum LLMToolDiagnostics {
    struct UnsupportedType: DiagnosticMessage {
        let typeName: String
        var message: String { "@LLMTool Error: The type '\(typeName)' is not supported. LLM tools only support String, Int, Double, Float, Bool, Optionals thereof, and String-backed CaseIterable enums." }
        var diagnosticID: MessageID { .init(domain: "LLMToolMacro", id: "unsupported_type") }
        var severity: DiagnosticSeverity { .error }
    }
}

public struct LLMToolMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf decl: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let funcDecl = decl.as(FunctionDeclSyntax.self) else { return [] }

        let access = accessModifier(from: funcDecl.modifiers)
        let funcName = funcDecl.name.text

        // Documentation: summary and per-parameter descriptions
        let (summary, paramDocs) = parseDocComments(from: funcDecl.leadingTrivia)

        // Parameters: map to schema
        var properties: [(name: String, type: String, desc: String, enumCode: String?)] = []
        var required: [String] = []

        for param in funcDecl.signature.parameterClause.parameters {
            let paramName = (param.secondName ?? param.firstName).text
            let typeSyntax = param.type
            let (isOptional, baseType) = unwrapOptional(typeSyntax)

            if !isOptional { required.append(paramName) }

            let desc = paramDocs[paramName] ?? ""
            var enumCode: String? = nil
            let jsonType: String

            if let simple = baseType.as(IdentifierTypeSyntax.self) {
                switch simple.name.text {
                case "String": jsonType = "string"
                case "Int": jsonType = "integer"
                case "Double", "Float": jsonType = "number"
                case "Bool": jsonType = "boolean"
                default:
                    // Try to resolve enum values from same file
                    if let values = enumCaseValues(named: simple.name.text, near: Syntax(funcDecl)) {
                        let enumList = values.map { "\"\($0)\"" }.joined(separator: ", ")
                        enumCode = "[\(enumList)]"
                        jsonType = "string"
                    } else {
                        // Fall back to dynamic extraction if type provides `allCases` and `rawValue`.
                        enumCode = "Array(\(simple.name.text).allCases.map(\\.rawValue))"
                        jsonType = "string"
                    }
                }
            } else if baseType.is(OptionalTypeSyntax.self) {
                // nested optionals unlikely; treat as string
                jsonType = "string"
            } else {
                // Unsupported complex type
                context.diagnose(Diagnostic(node: Syntax(typeSyntax), message: LLMToolDiagnostics.UnsupportedType(typeName: baseType.description.trimmingCharacters(in: .whitespacesAndNewlines))))
                jsonType = "string"
            }

            properties.append((name: paramName, type: jsonType, desc: desc, enumCode: enumCode))
        }

        // Build properties dictionary literal
        var propEntries: [String] = []
        for prop in properties {
            let descLiteral = literalString(prop.desc)
            if let enumCode = prop.enumCode {
                propEntries.append("\"\(prop.name)\": .init(\n                        type: \"\(prop.type)\",\n                        description: \(descLiteral),\n                        enum: \(enumCode)\n                    )")
            } else {
                propEntries.append("\"\(prop.name)\": .init(\n                        type: \"\(prop.type)\",\n                        description: \(descLiteral),\n                        enum: nil\n                    )")
            }
        }
        let propsDict = propEntries.joined(separator: ",\n                    ")
        let requiredArray = required.map { "\"\($0)\"" }.joined(separator: ", ")

        let descriptionLiteral = literalString(summary)
        let toolDecl: DeclSyntax = """
        \(raw: access) static var \(raw: funcName)LLMTool: LLMTool {
            LLMTool(
                function: .init(
                    name: \"\(raw: funcName)\",
                    description: \(raw: descriptionLiteral),
                    parameters: .init(
                        properties: [
                            \(raw: propsDict)
                        ],
                        required: [\(raw: requiredArray)]
                    )
                )
            )
        }
        """

        return [toolDecl]
    }

    // MARK: Helpers

    private static func accessModifier(from mods: DeclModifierListSyntax?) -> String {
        guard let mods else { return "public" } // default to public to mirror typical API exposure
        for m in mods {
            let t = m.name.text
            if t == "public" || t == "internal" || t == "package" || t == "fileprivate" || t == "private" {
                return t
            }
        }
        return "internal"
    }

    private static func parseDocComments(from trivia: Trivia?) -> (summary: String, params: [String: String]) {
        var lines: [String] = []
        if let trivia {
            for piece in trivia {
                if case .docLineComment(let text) = piece {
                    let trimmed = text.replacingOccurrences(of: "///", with: "").trimmingCharacters(in: .whitespaces)
                    lines.append(trimmed)
                }
            }
        }
        var summary = ""
        var params: [String: String] = [:]
        for line in lines {
            if line.hasPrefix("- Parameter ") || line.hasPrefix("- parameter ") {
                // format: - Parameter name: description
                let rest = line.drop(while: { $0 != " " }).dropFirst().trimmingCharacters(in: .whitespaces)
                if let colon = rest.firstIndex(of: ":") {
                    let name = rest[..<colon].replacingOccurrences(of: "Parameter", with: "").trimmingCharacters(in: .whitespaces)
                    let desc = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { params[name] = desc }
                }
            } else if summary.isEmpty && !line.isEmpty {
                summary = line
            }
        }
        return (summary, params)
    }

    private static func unwrapOptional(_ type: TypeSyntax) -> (isOptional: Bool, base: TypeSyntax) {
        if let opt = type.as(OptionalTypeSyntax.self) { return (true, TypeSyntax(opt.wrappedType)) }
        return (false, type)
    }

    private static func enumCaseValues(named name: String, near decl: Syntax) -> [String]? {
        let file = decl.root.as(SourceFileSyntax.self)
        guard let file else { return nil }
        for item in file.statements {
            if let enumDecl = item.item.as(EnumDeclSyntax.self), enumDecl.name.text == name {
                // Check raw type and/or CaseIterable if specified
                var isStringBacked = false
                var isCaseIterable = false
                if let inherits = enumDecl.inheritanceClause?.inheritedTypes {
                    for inh in inherits {
                        let t = inh.type.trimmedDescription
                        if t == "String" { isStringBacked = true }
                        if t == "CaseIterable" { isCaseIterable = true }
                    }
                }
                // If not explicitly specified, still proceed to extract cases; assume String-backed enums used responsibly
                var values: [String] = []
                for member in enumDecl.memberBlock.members {
                    if let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) {
                        for elem in caseDecl.elements { values.append(elem.name.text) }
                    }
                }
                if values.isEmpty { return nil }
                // If not obviously string-backed, still return names; schema requires strings
                _ = isStringBacked; _ = isCaseIterable
                return values
            }
        }
        return nil
    }

    private static func literalString(_ s: String) -> String {
        // Use Swift raw string literal if needed
        if s.contains("\"") || s.contains("\\") {
            return "#\"\(s)\"#"
        }
        return "\"\(s)\""
    }
}

@main
struct LLMToolSwiftPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StringifyMacro.self,
        LLMToolMacro.self,
    ]
}
