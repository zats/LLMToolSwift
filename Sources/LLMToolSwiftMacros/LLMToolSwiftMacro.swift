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
        var attrTrailing: Trivia? = nil
        let attrs = funcDecl.attributes
        if let lastAttr = attrs.last?.as(AttributeSyntax.self) {
            attrTrailing = Syntax(lastAttr).trailingTrivia
        }
        var modsLeading: Trivia? = nil
        if let firstMod = funcDecl.modifiers.first {
            modsLeading = Syntax(firstMod).leadingTrivia
        }
        let funcKeywordLeading = Syntax(funcDecl.funcKeyword).leadingTrivia
        let (summary, paramDocs) = parseDocComments(leading: funcDecl.leadingTrivia, attributeTrailing: attrTrailing, modifiersLeading: modsLeading, funcLeading: funcKeywordLeading)

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
        \(raw: effectiveAccess(access)) static var \(raw: funcName)LLMTool: LLMTool {
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
    private static func effectiveAccess(_ access: String) -> String {
        return access == "private" ? "fileprivate" : access
    }

    private static func parseDocComments(leading: Trivia?, attributeTrailing: Trivia?, modifiersLeading: Trivia?, funcLeading: Trivia?) -> (summary: String, params: [String: String]) {
        var lines: [String] = []
        func append(from trivia: Trivia?) {
            guard let trivia else { return }
            for piece in trivia {
                switch piece {
                case .docLineComment(let text):
                    var t = text
                    if t.hasPrefix("///") { t.removeFirst(3) }
                    else if t.hasPrefix("//!") { t.removeFirst(3) }
                    lines.append(t.trimmingCharacters(in: .whitespaces))
                case .docBlockComment(let text):
                    var content = text
                    content = content.replacingOccurrences(of: "/**", with: "")
                    content = content.replacingOccurrences(of: "*/", with: "")
                    for raw in content.components(separatedBy: .newlines) {
                        var l = raw.trimmingCharacters(in: .whitespaces)
                        if l.hasPrefix("*") {
                            l.removeFirst()
                            l = l.trimmingCharacters(in: .whitespaces)
                        }
                        lines.append(l)
                    }
                case .blockComment(let text):
                    // Fallback: treat a block comment with "/**" as doc if present between attribute and func
                    guard text.hasPrefix("/**") else { break }
                    var content = text
                    content = content.replacingOccurrences(of: "/**", with: "")
                    content = content.replacingOccurrences(of: "*/", with: "")
                    for raw in content.components(separatedBy: .newlines) {
                        var l = raw.trimmingCharacters(in: .whitespaces)
                        if l.hasPrefix("*") {
                            l.removeFirst()
                            l = l.trimmingCharacters(in: .whitespaces)
                        }
                        lines.append(l)
                    }
                case .lineComment(let text):
                    // Fallback for //! style
                    guard text.hasPrefix("//!") else { break }
                    var t = text
                    t.removeFirst(3)
                    lines.append(t.trimmingCharacters(in: .whitespaces))
                default:
                    break
                }
            }
        }
        append(from: leading)
        append(from: attributeTrailing)
        append(from: modifiersLeading)
        append(from: funcLeading)
        var summary = ""
        var params: [String: String] = [:]
        for line in lines {
            if line.hasPrefix("- Parameter ") || line.hasPrefix("- parameter ") {
                // format: - Parameter name: description
                var rest = line
                if rest.hasPrefix("- Parameter ") { rest.removeFirst("- Parameter ".count) }
                else if rest.hasPrefix("- parameter ") { rest.removeFirst("- parameter ".count) }
                if let colon = rest.firstIndex(of: ":") {
                    let name = rest[..<colon].trimmingCharacters(in: .whitespaces)
                    let desc = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { params[String(name)] = String(desc) }
                }
            } else if summary.isEmpty {
                let s = line.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { summary = s }
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

    // MARK: Aggregation helpers

    private static func enclosingType(for funcDecl: FunctionDeclSyntax) -> (modifiers: DeclModifierListSyntax?, members: MemberBlockSyntax, kind: String)? {
        var parent: Syntax? = Syntax(funcDecl)
        while let p = parent {            
            if let s = p.as(StructDeclSyntax.self) { return (s.modifiers, s.memberBlock, "struct") }
            if let c = p.as(ClassDeclSyntax.self) { return (c.modifiers, c.memberBlock, "class") }
            if let e = p.as(ExtensionDeclSyntax.self) { return (e.modifiers, e.memberBlock, "extension") }
            parent = p.parent
        }
        return nil
    }

    private static func annotatedFunctions(in enclosing: (modifiers: DeclModifierListSyntax?, members: MemberBlockSyntax, kind: String)) -> [FunctionDeclSyntax]? {
        var result: [FunctionDeclSyntax] = []
        for m in enclosing.members.members {
            if let f = m.decl.as(FunctionDeclSyntax.self) {
                if hasLLMToolAttribute(f) {
                    result.append(f)
                }
            }
        }
        return result
    }

    private static func hasLLMToolAttribute(_ f: FunctionDeclSyntax) -> Bool {
        for a in f.attributes {
            if let attr = a.as(AttributeSyntax.self) {
                if attr.attributeName.trimmedDescription == "LLMTool" { return true }
            }
        }
        return false
    }

    private static func isStatic(_ f: FunctionDeclSyntax) -> Bool {
        for m in f.modifiers { if m.name.text == "static" || m.name.text == "class" { return true } }
        return false
    }

    private static func returnsVoid(_ f: FunctionDeclSyntax) -> Bool {
        guard let ret = f.signature.returnClause?.type else { return true }
        if let id = ret.as(IdentifierTypeSyntax.self), id.name.text == "Void" { return true }
        if ret.is(TupleTypeSyntax.self) { return true } // ()
        return false
    }

    private static func buildDispatchCase(for f: FunctionDeclSyntax, receiverBase: String) throws -> String {
        let funcName = f.name.text
        var lines: [String] = []
        lines.append("case \"\(funcName)\":")

        // Build parameter extraction
        var callArgs: [String] = []
        for param in f.signature.parameterClause.parameters {
            let external = param.firstName.text
            let internalBase = (param.secondName ?? param.firstName).text
            let varName = "__arg_\(internalBase)"
            let labelForCall = external == "_" ? "" : external + ": "
            let (isOpt, baseType) = unwrapOptional(param.type)
            let baseTypeName = baseType.trimmedDescription

            let rawVar = "__v_\(internalBase)"
            if isOpt {
                // optional param
                lines.append("    var \(varName): \(baseTypeName)?")
                lines.append("    if let \(rawVar) = arguments[\"\(external)\"] {")
                lines.append(contentsOf: convertValueLines(rawVar: rawVar, targetVar: varName, typeName: baseTypeName, forEnum: baseType.as(IdentifierTypeSyntax.self)?.name.text, assignOnly: true))
                lines.append("    } else { \(varName) = nil }")
            } else {
                lines.append("    guard let \(rawVar) = arguments[\"\(external)\"] else { throw LLMToolCallError.missingArgument(\"\(external)\") }")
                lines.append(contentsOf: convertValueLines(rawVar: rawVar, targetVar: varName, typeName: baseTypeName, forEnum: baseType.as(IdentifierTypeSyntax.self)?.name.text, assignOnly: false))
            }

            callArgs.append("\(labelForCall)\(varName)")
        }

        let receiver = isStatic(f) ? "Self" : receiverBase
        let callCore = "\(receiver).\(funcName)(\(callArgs.joined(separator: ", ")) )"
        let isAsync = f.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = (f.signature.effectSpecifiers?.throwsClause?.throwsSpecifier) != nil
        let awaitPrefix = isAsync ? "await " : ""
        let tryPrefix = isThrows ? "try " : ""
        let prefix = "\(tryPrefix)\(awaitPrefix)"
        if returnsVoid(f) {
            lines.append("    \(prefix)\(callCore)")
            lines.append("    return nil")
        } else {
            lines.append("    let __res = \(prefix)\(callCore)")
            lines.append("    return __res as Any")
        }
        
        return lines.joined(separator: "\n")
    }

    private static func convertValueLines(rawVar: String, targetVar: String, typeName: String, forEnum enumName: String?, assignOnly: Bool) -> [String] {
        switch typeName {
        case "String":
            return [
                "    guard let __s = \(rawVar) as? String else { throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"String\") }",
                assignOnly ? "    \(targetVar) = __s" : "    let \(targetVar) = __s",
            ]
        case "Int":
            var lines: [String] = []
            if !assignOnly { lines.append("    var \(targetVar): Int") }
            lines += [
                "    if let __i = \(rawVar) as? Int {",
                "        \(targetVar) = __i",
                "    } else if let __d = \(rawVar) as? Double, __d.rounded() == __d {",
                "        \(targetVar) = Int(__d)",
                "    } else {",
                "        throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"Int\")",
                "    }",
            ]
            return lines
        case "Double":
            var lines: [String] = []
            if !assignOnly { lines.append("    var \(targetVar): Double") }
            lines += [
                "    if let __d = \(rawVar) as? Double {",
                "        \(targetVar) = __d",
                "    } else if let __i = \(rawVar) as? Int {",
                "        \(targetVar) = Double(__i)",
                "    } else {",
                "        throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"Double\")",
                "    }",
            ]
            return lines
        case "Float":
            var lines: [String] = []
            if !assignOnly { lines.append("    var \(targetVar): Float") }
            lines += [
                "    if let __d = \(rawVar) as? Double {",
                "        \(targetVar) = Float(__d)",
                "    } else if let __i = \(rawVar) as? Int {",
                "        \(targetVar) = Float(__i)",
                "    } else {",
                "        throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"Float\")",
                "    }",
            ]
            return lines
        case "Bool":
            return [
                "    guard let __b = \(rawVar) as? Bool else { throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"Bool\") }",
                assignOnly ? "    \(targetVar) = __b" : "    let \(targetVar) = __b",
            ]
        default:
            if let enumName = enumName {
                return [
                    "    guard let __s = \(rawVar) as? String else { throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"String (rawValue for \(enumName))\") }",
                    "    guard let __e = \(enumName)(rawValue: __s) else { throw LLMToolCallError.invalidEnumValue(param: \"\(targetVar)\", value: __s) }",
                    assignOnly ? "    \(targetVar) = __e" : "    let \(targetVar) = __e",
                ]
            }
            return [
                "    throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"Unsupported type \(typeName)\")",
            ]
        }
    }
}

// MARK: - Type-level aggregator macro

public struct LLMToolsMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf decl: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Support structs, classes, and extensions
        let members: MemberBlockSyntax?
        let mods: DeclModifierListSyntax?
        if let s = decl.as(StructDeclSyntax.self) {
            members = s.memberBlock
            mods = s.modifiers
        } else if let c = decl.as(ClassDeclSyntax.self) {
            members = c.memberBlock
            mods = c.modifiers
        } else if let e = decl.as(ExtensionDeclSyntax.self) {
            members = e.memberBlock
            mods = e.modifiers
        } else {
            return []
        }

        guard let members else { return [] }
        let typeAccess = self.accessModifier(from: mods)
        let emitAccess = self.effectiveAccess(typeAccess)
        // Determine concrete receiver type for dispatcher parameter
        // Instance dispatcher; receiver is self

        // Collect functions annotated with @LLMTool
        var toolFuncs: [FunctionDeclSyntax] = []
        for m in members.members {
            if let f = m.decl.as(FunctionDeclSyntax.self), self.hasLLMToolAttribute(f) {
                toolFuncs.append(f)
            }
        }
        if toolFuncs.isEmpty { return [] }

        // llmTools property
        let allToolProps = toolFuncs.map { "\($0.name.text)LLMTool" }.joined(separator: ",\n            ")
        let toolsDecl: DeclSyntax = """
        \(raw: emitAccess) static var llmTools: [LLMTool] {
            [
                \(raw: allToolProps)
            ]
        }
        """

        // Dispatcher
        var switchCases: [String] = []
        for f in toolFuncs {
            let call = try self.buildDispatchCase(for: f, receiverBase: "self")
            switchCases.append(call)
        }
        let casesJoined = switchCases.joined(separator: "\n\n            ")
        let dispatcherDecl: DeclSyntax = """
        \(raw: emitAccess) func dispatchLLMTool(named name: String, arguments: [String: Any]) async throws -> Any? {
            switch name {
            \(raw: casesJoined)
            default:
                throw LLMToolCallError.functionNotFound(name)
            }
        }
        """

        return [toolsDecl, dispatcherDecl]
    }

    // Local helpers for dispatcher generation
    private static func effectiveAccess(_ access: String) -> String { access == "private" ? "fileprivate" : access }
    private static func accessModifier(from mods: DeclModifierListSyntax?) -> String {
        guard let mods else { return "internal" }
        for m in mods {
            let t = m.name.text
            if t == "public" || t == "internal" || t == "package" || t == "fileprivate" || t == "private" || t == "open" { return t }
        }
        return "internal"
    }
    private static func hasLLMToolAttribute(_ f: FunctionDeclSyntax) -> Bool {
        for a in f.attributes {
            if let attr = a.as(AttributeSyntax.self), attr.attributeName.trimmedDescription == "LLMTool" { return true }
        }
        return false
    }
    private static func unwrapOptional(_ type: TypeSyntax) -> (isOptional: Bool, base: TypeSyntax) {
        if let opt = type.as(OptionalTypeSyntax.self) { return (true, TypeSyntax(opt.wrappedType)) }
        return (false, type)
    }
    private static func isStatic(_ f: FunctionDeclSyntax) -> Bool {
        for m in f.modifiers { if m.name.text == "static" || m.name.text == "class" { return true } }
        return false
    }
    private static func buildDispatchCase(for f: FunctionDeclSyntax, receiverBase: String) throws -> String {
        let funcName = f.name.text
        var lines: [String] = []
        lines.append("case \"\(funcName)\":")
        var callArgs: [String] = []
        for param in f.signature.parameterClause.parameters {
            let external = param.firstName.text
            let internalBase = (param.secondName ?? param.firstName).text
            let varName = "__arg_\(internalBase)"
            let labelForCall = external == "_" ? "" : external + ": "
            let (isOpt, baseType) = unwrapOptional(param.type)
            let baseTypeName = baseType.trimmedDescription
            let rawVar = "__v_\(internalBase)"
            if isOpt {
                lines.append("    var \(varName): \(baseTypeName)?")
                lines.append("    if let \(rawVar) = arguments[\"\(external)\"] {")
                lines.append(contentsOf: convertValueLines(rawVar: rawVar, targetVar: varName, typeName: baseTypeName, forEnum: baseType.as(IdentifierTypeSyntax.self)?.name.text, assignOnly: true))
                lines.append("    } else { \(varName) = nil }")
            } else {
                lines.append("    guard let \(rawVar) = arguments[\"\(external)\"] else { throw LLMToolCallError.missingArgument(\"\(external)\") }")
                lines.append(contentsOf: convertValueLines(rawVar: rawVar, targetVar: varName, typeName: baseTypeName, forEnum: baseType.as(IdentifierTypeSyntax.self)?.name.text, assignOnly: false))
            }
            callArgs.append("\(labelForCall)\(varName)")
        }
        let receiver = isStatic(f) ? "Self" : receiverBase
        let callCore = "\(receiver).\(funcName)(\(callArgs.joined(separator: ", ")) )"
        let isAsync = f.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = (f.signature.effectSpecifiers?.throwsClause?.throwsSpecifier) != nil
        let awaitPrefix = isAsync ? "await " : ""
        let tryPrefix = isThrows ? "try " : ""
        let prefix = "\(tryPrefix)\(awaitPrefix)"
        if returnsVoid(f) {
            lines.append("    \(prefix)\(callCore)")
            lines.append("    return nil")
        } else {
            lines.append("    let __res = \(prefix)\(callCore)")
            lines.append("    return __res as Any")
        }
        return lines.joined(separator: "\n")
    }
    private static func returnsVoid(_ f: FunctionDeclSyntax) -> Bool {
        guard let ret = f.signature.returnClause?.type else { return true }
        if let id = ret.as(IdentifierTypeSyntax.self), id.name.text == "Void" { return true }
        if ret.is(TupleTypeSyntax.self) { return true }
        return false
    }
    private static func convertValueLines(rawVar: String, targetVar: String, typeName: String, forEnum enumName: String?, assignOnly: Bool) -> [String] {
        switch typeName {
        case "String": return ["    guard let __s = \(rawVar) as? String else { throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"String\") }", assignOnly ? "    \(targetVar) = __s" : "    let \(targetVar) = __s"]
        case "Int":
            var lines: [String] = []
            if !assignOnly { lines.append("    var \(targetVar): Int") }
            lines += ["    if let __i = \(rawVar) as? Int {", "        \(targetVar) = __i", "    } else if let __d = \(rawVar) as? Double, __d.rounded() == __d {", "        \(targetVar) = Int(__d)", "    } else {", "        throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"Int\")", "    }"]
            return lines
        case "Double":
            var lines: [String] = []
            if !assignOnly { lines.append("    var \(targetVar): Double") }
            lines += ["    if let __d = \(rawVar) as? Double {", "        \(targetVar) = __d", "    } else if let __i = \(rawVar) as? Int {", "        \(targetVar) = Double(__i)", "    } else {", "        throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"Double\")", "    }"]
            return lines
        case "Float":
            var lines: [String] = []
            if !assignOnly { lines.append("    var \(targetVar): Float") }
            lines += ["    if let __d = \(rawVar) as? Double {", "        \(targetVar) = Float(__d)", "    } else if let __i = \(rawVar) as? Int {", "        \(targetVar) = Float(__i)", "    } else {", "        throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"Float\")", "    }"]
            return lines
        case "Bool": return ["    guard let __b = \(rawVar) as? Bool else { throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"Bool\") }", assignOnly ? "    \(targetVar) = __b" : "    let \(targetVar) = __b"]
        default:
            if let enumName = enumName {
                return ["    guard let __s = \(rawVar) as? String else { throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"String (rawValue for \(enumName))\") }", "    guard let __e = \(enumName)(rawValue: __s) else { throw LLMToolCallError.invalidEnumValue(param: \"\(targetVar)\", value: __s) }", assignOnly ? "    \(targetVar) = __e" : "    let \(targetVar) = __e"]
            }
            return ["    throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"Unsupported type \(typeName)\")"]
        }
    }

    // Newer SwiftSyntax requires implementing the overload with `conformingTo:`
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf decl: some DeclGroupSyntax,
        conformingTo: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let members: MemberBlockSyntax?
        let mods: DeclModifierListSyntax?
        if let s = decl.as(StructDeclSyntax.self) {
            members = s.memberBlock
            mods = s.modifiers
        } else if let c = decl.as(ClassDeclSyntax.self) {
            members = c.memberBlock
            mods = c.modifiers
        } else if let e = decl.as(ExtensionDeclSyntax.self) {
            members = e.memberBlock
            mods = e.modifiers
        } else {
            return []
        }

        guard let members else { return [] }
        let typeAccess = self.accessModifier(from: mods)
        let emitAccess = self.effectiveAccess(typeAccess)

        // Determine concrete receiver type for static dispatcher parameter
        let receiverType: String
        if let s = decl.as(StructDeclSyntax.self) {
            receiverType = s.name.text
        } else if let c = decl.as(ClassDeclSyntax.self) {
            receiverType = c.name.text
        } else if let e = decl.as(ExtensionDeclSyntax.self) {
            receiverType = e.extendedType.trimmedDescription
        } else {
            receiverType = "Self"
        }

        var toolFuncs: [FunctionDeclSyntax] = []
        for m in members.members {
            if let f = m.decl.as(FunctionDeclSyntax.self), self.hasLLMToolAttribute(f) {
                toolFuncs.append(f)
            }
        }
        if toolFuncs.isEmpty { return [] }

        let allToolProps = toolFuncs.map { "\($0.name.text)LLMTool" }.joined(separator: ",\n            ")
        let toolsDecl: DeclSyntax = """
        \(raw: emitAccess) static var llmTools: [LLMTool] {
            [
                \(raw: allToolProps)
            ]
        }
        """

        var switchCases: [String] = []
        for f in toolFuncs {
            let call = try self.buildDispatchCase(for: f, receiverBase: "self")
            switchCases.append(call)
        }
        let casesJoined = switchCases.joined(separator: "\n\n            ")
        let dispatcherDecl: DeclSyntax = """
        \(raw: emitAccess) func dispatchLLMTool(named name: String, arguments: [String: Any]) async throws -> Any? {
            switch name {
            \(raw: casesJoined)
            default:
                throw LLMToolCallError.functionNotFound(name)
            }
        }
        """

        return [toolsDecl, dispatcherDecl]
    }

}

// MARK: - Repository macro (collect all eligible functions)

public struct LLMToolRepositoryMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf decl: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Support structs, classes, and extensions
        let members: MemberBlockSyntax?
        let mods: DeclModifierListSyntax?
        if let s = decl.as(StructDeclSyntax.self) {
            members = s.memberBlock
            mods = s.modifiers
        } else if let c = decl.as(ClassDeclSyntax.self) {
            members = c.memberBlock
            mods = c.modifiers
        } else if let e = decl.as(ExtensionDeclSyntax.self) {
            members = e.memberBlock
            mods = e.modifiers
        } else {
            return []
        }

        guard let members else { return [] }
        let typeAccess = self.accessModifier(from: mods)
        let typeRank = accessRank(typeAccess)

        // Instance dispatcher uses `self`; no receiver type variable needed.

        // Collect eligible functions by access
        var funcs: [FunctionDeclSyntax] = []
        for m in members.members {
            if let f = m.decl.as(FunctionDeclSyntax.self) {
                let fAccess = self.accessModifier(from: f.modifiers)
                if accessRank(fAccess) >= typeRank {
                    funcs.append(f)
                }
            }
        }
        if funcs.isEmpty { return [] }

        // Build llmTools array with inline LLMTool values
        var toolExprs: [String] = []
        for f in funcs {
            let funcName = f.name.text
            // Documentation
            var attrTrailing: Trivia? = nil
            let attrs = f.attributes
            if let lastAttr = attrs.last?.as(AttributeSyntax.self) { attrTrailing = Syntax(lastAttr).trailingTrivia }
            var modsLeading: Trivia? = nil
            if let firstMod = f.modifiers.first { modsLeading = Syntax(firstMod).leadingTrivia }
            let funcLeading = Syntax(f.funcKeyword).leadingTrivia
            let (summary, paramDocs) = self.parseDocComments(leading: f.leadingTrivia, attributeTrailing: attrTrailing, modifiersLeading: modsLeading, funcLeading: funcLeading)

            var properties: [(name: String, type: String, desc: String, enumCode: String?)] = []
            var required: [String] = []
            for param in f.signature.parameterClause.parameters {
                let paramName = (param.secondName ?? param.firstName).text
                let typeSyntax = param.type
                let (isOptional, baseType) = self.unwrapOptional(typeSyntax)
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
                        if let values = self.enumCaseValues(named: simple.name.text, near: Syntax(f)) {
                            let enumList = values.map { "\"\($0)\"" }.joined(separator: ", ")
                            enumCode = "[\(enumList)]"
                            jsonType = "string"
                        } else {
                            enumCode = "Array(\(simple.name.text).allCases.map(\\.rawValue))"
                            jsonType = "string"
                        }
                    }
                } else if baseType.is(OptionalTypeSyntax.self) {
                    jsonType = "string"
                } else {
                    context.diagnose(Diagnostic(node: Syntax(typeSyntax), message: LLMToolDiagnostics.UnsupportedType(typeName: baseType.description.trimmingCharacters(in: .whitespacesAndNewlines))))
                    jsonType = "string"
                }
                properties.append((name: paramName, type: jsonType, desc: desc, enumCode: enumCode))
            }

            var propEntries: [String] = []
            for prop in properties {
                let descLiteral = self.literalString(prop.desc)
                if let enumCode = prop.enumCode {
                    propEntries.append("\"\(prop.name)\": .init(\n                                type: \"\(prop.type)\",\n                                description: \(descLiteral),\n                                enum: \(enumCode)\n                            )")
                } else {
                    propEntries.append("\"\(prop.name)\": .init(\n                                type: \"\(prop.type)\",\n                                description: \(descLiteral),\n                                enum: nil\n                            )")
                }
            }
            let propsDict = propEntries.joined(separator: ",\n                            ")
            let requiredArray = required.map { "\"\($0)\"" }.joined(separator: ", ")
            let descriptionLiteral = self.literalString(summary)
            let toolExpr = """
            LLMTool(
                function: .init(
                    name: \"\(funcName)\",
                    description: \(descriptionLiteral),
                    parameters: .init(
                        properties: [
                            \(propsDict)
                        ],
                        required: [\(requiredArray)]
                    )
                )
            )
            """
            toolExprs.append(toolExpr)
        }
        let toolsJoined = toolExprs.joined(separator: ",\n                ")
        let toolsDecl: DeclSyntax = """
        \(raw: typeAccess) static var llmTools: [LLMTool] {
            [
                \(raw: toolsJoined)
            ]
        }
        """

        // Dispatcher same as LLMToolsMacro
        var switchCases: [String] = []
        for f in funcs {
            let call = try self.buildDispatchCase(for: f, receiverBase: "self")
            switchCases.append(call)
        }
        let casesJoined = switchCases.joined(separator: "\n\n            ")
        let emitAccess2 = self.effectiveAccess(typeAccess)
        let dispatcherDecl: DeclSyntax = """
        \(raw: emitAccess2) func dispatchLLMTool(named name: String, arguments: [String: Any]) async throws -> Any {
            switch name {
            \(raw: casesJoined)
            default:
                throw LLMToolCallError.functionNotFound(name)
            }
        }
        """

        return [toolsDecl, dispatcherDecl]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf decl: some DeclGroupSyntax,
        conformingTo: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Reuse the other overload implementation by upcasting
        return try expansion(of: node, providingMembersOf: decl, in: context)
    }

    private static func accessRank(_ access: String) -> Int {
        switch access {
        case "private": return 0
        case "fileprivate": return 1
        case "internal": return 2
        case "package": return 3
        case "public": return 4
        case "open": return 5
        default: return 2
        }
    }

    // MARK: Local helpers (duplicated for isolation)

    private static func accessModifier(from mods: DeclModifierListSyntax?) -> String {
        guard let mods else { return "internal" }
        for m in mods {
            let t = m.name.text
            if t == "public" || t == "internal" || t == "package" || t == "fileprivate" || t == "private" || t == "open" {
                return t
            }
        }
        return "internal"
    }
    private static func effectiveAccess(_ access: String) -> String {
        return access == "private" ? "fileprivate" : access
    }

    private static func parseDocComments(leading: Trivia?, attributeTrailing: Trivia?, modifiersLeading: Trivia?, funcLeading: Trivia?) -> (summary: String, params: [String: String]) {
        var lines: [String] = []
        func append(from trivia: Trivia?) {
            guard let trivia else { return }
            for piece in trivia {
                switch piece {
                case .docLineComment(let text):
                    var t = text
                    if t.hasPrefix("///") { t.removeFirst(3) } else if t.hasPrefix("//!") { t.removeFirst(3) }
                    lines.append(t.trimmingCharacters(in: .whitespaces))
                case .docBlockComment(let text):
                    let content = text.replacingOccurrences(of: "/**", with: "").replacingOccurrences(of: "*/", with: "")
                    for raw in content.components(separatedBy: .newlines) {
                        var l = raw.trimmingCharacters(in: .whitespaces)
                        if l.hasPrefix("*") { l.removeFirst(); l = l.trimmingCharacters(in: .whitespaces) }
                        lines.append(l)
                    }
                case .blockComment(let text):
                    guard text.hasPrefix("/**") else { break }
                    let content = text.replacingOccurrences(of: "/**", with: "").replacingOccurrences(of: "*/", with: "")
                    for raw in content.components(separatedBy: .newlines) {
                        var l = raw.trimmingCharacters(in: .whitespaces)
                        if l.hasPrefix("*") { l.removeFirst(); l = l.trimmingCharacters(in: .whitespaces) }
                        lines.append(l)
                    }
                case .lineComment(let text):
                    guard text.hasPrefix("//!") else { break }
                    var t = text; t.removeFirst(3); lines.append(t.trimmingCharacters(in: .whitespaces))
                default:
                    break
                }
            }
        }
        append(from: leading)
        append(from: attributeTrailing)
        append(from: modifiersLeading)
        append(from: funcLeading)

        var summary = ""
        var params: [String: String] = [:]
        for line in lines {
            if line.hasPrefix("- Parameter ") || line.hasPrefix("- parameter ") {
                var rest = line
                if rest.hasPrefix("- Parameter ") { rest.removeFirst("- Parameter ".count) } else if rest.hasPrefix("- parameter ") { rest.removeFirst("- parameter ".count) }
                if let colon = rest.firstIndex(of: ":") {
                    let name = rest[..<colon].trimmingCharacters(in: .whitespaces)
                    let desc = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { params[String(name)] = String(desc) }
                }
            } else if summary.isEmpty {
                let s = line.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { summary = s }
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
                var values: [String] = []
                for member in enumDecl.memberBlock.members {
                    if let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) {
                        for elem in caseDecl.elements { values.append(elem.name.text) }
                    }
                }
                if values.isEmpty { return nil }
                return values
            }
        }
        return nil
    }

    private static func literalString(_ s: String) -> String {
        if s.contains("\"") || s.contains("\\") { return "#\"\(s)\"#" }
        return "\"\(s)\""
    }

    private static func isStatic(_ f: FunctionDeclSyntax) -> Bool {
        for m in f.modifiers { if m.name.text == "static" || m.name.text == "class" { return true } }
        return false
    }

    private static func returnsVoid(_ f: FunctionDeclSyntax) -> Bool {
        guard let ret = f.signature.returnClause?.type else { return true }
        if let id = ret.as(IdentifierTypeSyntax.self), id.name.text == "Void" { return true }
        if ret.is(TupleTypeSyntax.self) { return true }
        return false
    }

    private static func buildDispatchCase(for f: FunctionDeclSyntax, receiverBase: String) throws -> String {
        let funcName = f.name.text
        var lines: [String] = []
        lines.append("case \"\(funcName)\":")
        var callArgs: [String] = []
        for param in f.signature.parameterClause.parameters {
            let external = param.firstName.text
            let internalBase = (param.secondName ?? param.firstName).text
            let varName = "__arg_\(internalBase)"
            let labelForCall = external == "_" ? "" : external + ": "
            let (isOpt, baseType) = unwrapOptional(param.type)
            let baseTypeName = baseType.trimmedDescription
            let rawVar = "__v_\(internalBase)"
            if isOpt {
                lines.append("    var \(varName): \(baseTypeName)?")
                lines.append("    if let \(rawVar) = arguments[\"\(external)\"] {")
                lines.append(contentsOf: convertValueLines(rawVar: rawVar, targetVar: varName, typeName: baseTypeName, forEnum: baseType.as(IdentifierTypeSyntax.self)?.name.text, assignOnly: true))
                lines.append("    } else { \(varName) = nil }")
            } else {
                lines.append("    guard let \(rawVar) = arguments[\"\(external)\"] else { throw LLMToolCallError.missingArgument(\"\(external)\") }")
                lines.append(contentsOf: convertValueLines(rawVar: rawVar, targetVar: varName, typeName: baseTypeName, forEnum: baseType.as(IdentifierTypeSyntax.self)?.name.text, assignOnly: false))
            }
            callArgs.append("\(labelForCall)\(varName)")
        }
        let receiver = isStatic(f) ? "Self" : receiverBase
        let callCore = "\(receiver).\(funcName)(\(callArgs.joined(separator: ", ")) )"
        let isAsync = f.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrows = (f.signature.effectSpecifiers?.throwsClause?.throwsSpecifier) != nil
        let awaitPrefix = isAsync ? "await " : ""
        let tryPrefix = isThrows ? "try " : ""
        let prefix = "\(tryPrefix)\(awaitPrefix)"
        if returnsVoid(f) {
            lines.append("    \(prefix)\(callCore)")
            lines.append("    return nil")
        } else {
            lines.append("    let __res = \(prefix)\(callCore)")
            lines.append("    return __res as Any")
        }
        return lines.joined(separator: "\n")
    }

    private static func convertValueLines(rawVar: String, targetVar: String, typeName: String, forEnum enumName: String?, assignOnly: Bool) -> [String] {
        switch typeName {
        case "String":
            return [
                "    guard let __s = \(rawVar) as? String else { throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"String\") }",
                assignOnly ? "    \(targetVar) = __s" : "    let \(targetVar) = __s",
            ]
        case "Int":
            var lines: [String] = []
            if !assignOnly { lines.append("    var \(targetVar): Int") }
            lines.append(contentsOf: [
                "    if let __i = \(rawVar) as? Int {",
                "        \(targetVar) = __i",
                "    } else if let __d = \(rawVar) as? Double, __d.rounded() == __d {",
                "        \(targetVar) = Int(__d)",
                "    } else {",
                "        throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"Int\")",
                "    }",
            ])
            return lines
        case "Double":
            var lines: [String] = []
            if !assignOnly { lines.append("    var \(targetVar): Double") }
            lines.append(contentsOf: [
                "    if let __d = \(rawVar) as? Double {",
                "        \(targetVar) = __d",
                "    } else if let __i = \(rawVar) as? Int {",
                "        \(targetVar) = Double(__i)",
                "    } else {",
                "        throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"Double\")",
                "    }",
            ])
            return lines
        case "Float":
            var lines: [String] = []
            if !assignOnly { lines.append("    var \(targetVar): Float") }
            lines.append(contentsOf: [
                "    if let __d = \(rawVar) as? Double {",
                "        \(targetVar) = Float(__d)",
                "    } else if let __i = \(rawVar) as? Int {",
                "        \(targetVar) = Float(__i)",
                "    } else {",
                "        throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"Float\")",
                "    }",
            ])
            return lines
        case "Bool":
            return [
                "    guard let __b = \(rawVar) as? Bool else { throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"Bool\") }",
                assignOnly ? "    \(targetVar) = __b" : "    let \(targetVar) = __b",
            ]
        default:
            if let enumName = enumName {
                return [
                    "    guard let __s = \(rawVar) as? String else { throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"String (rawValue for \(enumName))\") }",
                    "    guard let __e = \(enumName)(rawValue: __s) else { throw LLMToolCallError.invalidEnumValue(param: \"\(targetVar)\", value: __s) }",
                    assignOnly ? "    \(targetVar) = __e" : "    let \(targetVar) = __e",
                ]
            }
            return [
                "    throw LLMToolCallError.typeMismatch(param: \"\(targetVar)\", expected: \"Unsupported type \(typeName)\")",
            ]
        }
    }
}

@main
struct LLMToolSwiftPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StringifyMacro.self,
        LLMToolMacro.self,
        LLMToolsMacro.self,
        LLMToolRepositoryMacro.self,
    ]
}
