import Foundation

actor APIDebugLogger {
    static let shared = APIDebugLogger()

    nonisolated static var logURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("api_debug_log.txt")
    }

    nonisolated static var hasLog: Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path) else { return false }
        return (attributes[.size] as? Int ?? 0) > 0
    }

    nonisolated static func readLog() -> String? {
        try? String(contentsOf: logURL, encoding: .utf8)
    }

    private let maxEntries = 5
    private let marker = "\n\n===== API_DEBUG_ENTRY =====\n\n"

    func record(request: Data, response: Data) {
        let entry = """
        \(Self.timestamp())
        [REQUEST]
        \(pretty(request))
        [RESPONSE]
        \(pretty(response))
        """

        var entries = loadEntries()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        let text = entries.joined(separator: marker) + "\n"
        try? text.write(to: Self.logURL, atomically: true, encoding: .utf8)
    }

    func clear() {
        try? FileManager.default.removeItem(at: Self.logURL)
    }

    private func loadEntries() -> [String] {
        guard let text = try? String(contentsOf: Self.logURL, encoding: .utf8), !text.isEmpty else {
            return []
        }
        return text.components(separatedBy: marker).filter { !$0.isEmpty }
    }

    private func pretty(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let string = String(data: prettyData, encoding: .utf8) else {
            return String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
        }
        return string
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: .now)
    }
}
