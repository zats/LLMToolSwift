import Foundation

/// A common interface for types that expose a repository of LLM tools.
///
/// Types annotated with `@LLMTools` will automatically conform to this
/// protocol. The macro synthesizes the static `llmTools` collection and the
/// instance dispatcher.
public protocol LLMToolsRepository {
    /// All tools exposed by this repository.
    static var llmTools: [LLMTool] { get }

    /// Invoke a tool by name with dynamic arguments.
    /// - Parameters:
    ///   - name: The tool (function) name.
    ///   - arguments: A dictionary of argument values, typically decoded from JSON.
    /// - Returns: The function's result boxed as `Any?`; `nil` for `Void` functions.
    func dispatchLLMTool(named name: String, arguments: [String: Any]) async throws -> Any?
}

