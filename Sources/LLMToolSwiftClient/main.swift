import LLMToolSwift

// Demo: freestanding stringify macro
let a = 17
let b = 25
let (result, code) = #stringify(a + b)
print("The value \(result) was produced by the code \"\(code)\"")

// Demo: @LLMTool macro
public enum TemperatureUnit: String, CaseIterable { case celsius, fahrenheit }
public struct WeatherService {
    /// Provides the current weather for a specified location.
    /// - Parameter location: The city and state, e.g., "San Francisco, CA".
    /// - Parameter unit: The temperature unit to use, either "celsius" or "fahrenheit".
    @LLMTool
    public func getCurrentWeather(location: String, unit: TemperatureUnit) -> String {
        return "The weather in \(location) is 75° \(unit.rawValue)."
    }
}

// Use generated tool schema
let toolJSON = WeatherService.getCurrentWeatherLLMTool.jsonString
print(toolJSON)
