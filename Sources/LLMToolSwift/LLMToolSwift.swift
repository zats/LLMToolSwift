import Foundation

/// Attached peer macro that generates a static `<funcName>LLMTool` property
/// describing the annotated function for LLM tool schemas.
@attached(peer, names: arbitrary)
public macro LLMTool() = #externalMacro(module: "LLMToolSwiftMacros", type: "LLMToolMacro")

/// Attached member macro placed on a type to aggregate all @LLMTool functions
/// into a `llmTools` array and generate a `handleLLMCall(name:arguments:)` dispatcher.
/// The annotated type also conforms to `LLMToolsRepository`.
@attached(member,
          names: named(llmTools),
                 named(dispatchLLMTool(named:arguments:)),
                 named(LLMToolFilterSet),
                 named(_FilteredRepository),
                 named(filter(_:)),
          conformances: LLMToolsRepository)
@attached(extension, conformances: LLMToolsRepository)
public macro LLMTools() = #externalMacro(module: "LLMToolSwiftMacros", type: "LLMToolsMacro")
