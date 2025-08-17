import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(LLMToolSwiftMacros)
import LLMToolSwiftMacros

let testMacros: [String: Macro.Type] = [
    "stringify": StringifyMacro.self,
    "LLMTool": LLMToolMacro.self,
]
#endif

final class LLMToolSwiftTests: XCTestCase {
    func testMacro() throws {
        #if canImport(LLMToolSwiftMacros)
        assertMacroExpansion(
            """
            #stringify(a + b)
            """,
            expandedSource: """
            (a + b, "a + b")
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testMacroWithStringLiteral() throws {
        #if canImport(LLMToolSwiftMacros)
        assertMacroExpansion(
            #"""
            #stringify("Hello, \(name)")
            """#,
            expandedSource: #"""
            ("Hello, \(name)", #""Hello, \(name)""#)
            """#,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testLLMToolMacro_SimpleStringParam() throws {
        #if canImport(LLMToolSwiftMacros)
        assertMacroExpansion(
            """
            public struct S {
                /// Greeting
                /// - Parameter name: A name.
                @LLMTool
                public func f(name: String) {}
            }
            """,
            expandedSource: """
            public struct S {
                /// Greeting
                /// - Parameter name: A name.
                public func f(name: String) {}

                public static var fLLMTool: LLMTool {
                    LLMTool(
                        function: .init(
                            name: "f",
                            description: "Greeting",
                            parameters: .init(
                                properties: [
                                    "name": .init(
                                        type: "string",
                                        description: "A name.",
                                        enum: nil
                                    )
                                ],
                                required: ["name"]
                            )
                        )
                    )
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
