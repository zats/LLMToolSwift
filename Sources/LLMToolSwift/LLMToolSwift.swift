// The Swift Programming Language
// https://docs.swift.org/swift-book

/// A macro that produces both a value and a string containing the
/// source code that generated the value. For example,
///
///     #stringify(x + y)
///
/// produces a tuple `(x + y, "x + y")`.
@freestanding(expression)
public macro stringify<T>(_ value: T) -> (T, String) = #externalMacro(module: "LLMToolSwiftMacros", type: "StringifyMacro")

/// Attached peer macro that generates a static `<funcName>LLMTool` property
/// describing the annotated function for LLM tool schemas.
@attached(peer, names: arbitrary)
public macro LLMTool() = #externalMacro(module: "LLMToolSwiftMacros", type: "LLMToolMacro")
