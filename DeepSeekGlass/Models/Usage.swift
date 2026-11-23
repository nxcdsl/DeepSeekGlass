import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    private let defaults = UserDefaults.standard

    private(set) var inputTokens: Int
    private(set) var outputTokens: Int
    private(set) var todayInput: Int
    private(set) var todayOutput: Int
    private(set) var dayKey: String

    var totalTokens: Int { inputTokens + outputTokens }
    var todayTokens: Int { todayInput + todayOutput }

    /// deepseek-flash peak pricing, shown only as a rough reference.
    var estimatedCost: Double {
        Double(inputTokens) / 1_000_000 * 0.30 + Double(outputTokens) / 1_000_000 * 1.20
    }

    var todayEstimatedCost: Double {
        Double(todayInput) / 1_000_000 * 0.30 + Double(todayOutput) / 1_000_000 * 1.20
    }

    init() {
        let defaults = UserDefaults.standard
        let key = Self.currentDayKey()
        let storedDay = defaults.string(forKey: Keys.day) ?? key
        let storedInput = defaults.integer(forKey: Keys.input)
        let storedOutput = defaults.integer(forKey: Keys.output)
        let storedTodayInput = defaults.integer(forKey: Keys.todayInput)
        let storedTodayOutput = defaults.integer(forKey: Keys.todayOutput)

        dayKey = key
        inputTokens = storedInput
        outputTokens = storedOutput
        todayInput = storedDay == key ? storedTodayInput : 0
        todayOutput = storedDay == key ? storedTodayOutput : 0
    }

    func record(input: Int, output: Int) {
        guard input > 0 || output > 0 else { return }
        let key = Self.currentDayKey()
        if key != dayKey {
            dayKey = key
            todayInput = 0
            todayOutput = 0
        }
        inputTokens += input
        outputTokens += output
        todayInput += input
        todayOutput += output
        persist()
    }

    func reset() {
        inputTokens = 0
        outputTokens = 0
        todayInput = 0
        todayOutput = 0
        dayKey = Self.currentDayKey()
        persist()
    }

    private func persist() {
        defaults.set(inputTokens, forKey: Keys.input)
        defaults.set(outputTokens, forKey: Keys.output)
        defaults.set(todayInput, forKey: Keys.todayInput)
        defaults.set(todayOutput, forKey: Keys.todayOutput)
        defaults.set(dayKey, forKey: Keys.day)
    }

    private static func currentDayKey() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }

    private enum Keys {
        static let input = "usage.input"
        static let output = "usage.output"
        static let todayInput = "usage.todayInput"
        static let todayOutput = "usage.todayOutput"
        static let day = "usage.day"
    }
}
