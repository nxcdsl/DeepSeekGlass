import Foundation

enum ContextCompressor {
    /// A cheap, local rolling memory. It keeps one or two representative
    /// sentences from each older turn instead of sending the whole turn again.
    static func summarize(_ messages: [ChatMessage], limit: Int = 2_200) -> String {
        var pieces: [String] = []
        for message in messages {
            let text = compact(message.textContent)
            guard !text.isEmpty else { continue }
            switch message.role {
            case .user:
                pieces.append("U: \(String(text.prefix(280)))")
            case .assistant:
                pieces.append("A: \(String(text.prefix(180)))")
            }
        }
        let joined = pieces.joined(separator: "\n")
        guard joined.count > limit else { return joined }
        let head = joined.prefix(1_250)
        let tail = joined.suffix(850)
        return "\(head)\n…（中间略）…\n\(tail)"
    }

    private static func compact(_ text: String) -> String {
        var value = text
        value = value.replacingOccurrences(of: "```[\\s\\S]*?```", with: " [代码] ", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: "[#>*_`~|]", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
