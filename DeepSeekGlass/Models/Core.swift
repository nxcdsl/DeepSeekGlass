import Foundation

// MARK: - Conversation model

enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
}

struct Attachment: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case image
        case text
        case pdf
    }

    var id: UUID = UUID()
    var kind: Kind = .image
    var filename: String = ""
    var storedName: String = ""
    var byteCount: Int = 0
    /// Extracted text for documents, kept so an old conversation can be replayed.
    var extractedText: String?

    var isImage: Bool { kind == .image }
}

struct SearchResult: Identifiable, Codable, Hashable, Sendable {
    var title: String = ""
    var url: String = ""
    var snippet: String?
    var siteName: String?
    var siteIcon: String?
    var pageAge: String?
    var imageURL: String?

    var id: String { url + "|" + title }
}

struct Citation: Identifiable, Codable, Hashable, Sendable {
    var index: Int
    var url: String
    var title: String?
    var citedText: String?

    var id: Int { index }
}

struct ContentBlock: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case text
        case thinking
        case toolUse
        case searchResults
        case fetchResult
    }

    var id: String
    var kind: Kind

    // text / thinking
    var text: String = ""
    var signature: String?

    // tool use
    var toolID: String?
    var toolName: String?
    var action: String?
    var queries: [String] = []
    var url: String?
    var pattern: String?
    var toolKind: String?

    // results
    var results: [SearchResult] = []
    var citations: [Citation] = []

    // fetch result
    var fetchTitle: String?
    var fetchError: String?

    var isComplete: Bool = false
    var startedAt: Date?
    var finishedAt: Date?

    static func text(_ text: String, id: String = UUID().uuidString) -> ContentBlock {
        ContentBlock(id: id, kind: .text, text: text)
    }
}

struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var role: ChatRole
    var blocks: [ContentBlock] = []
    var attachments: [Attachment] = []
    var createdAt: Date = .now
    var isStreaming: Bool = false
    var errorText: String?
    var thinkingSeconds: Int?
    var stopReason: String?

    var textContent: String {
        blocks.filter { $0.kind == .text }.map(\.text).joined()
    }

    var thinkingContent: String {
        blocks.filter { $0.kind == .thinking }.map(\.text).joined(separator: "\n\n")
    }

    var hasThinking: Bool {
        blocks.contains { $0.kind == .thinking || $0.kind == .toolUse || $0.kind == .searchResults || $0.kind == .fetchResult }
    }

    var sources: [SearchResult] {
        var seen = Set<String>()
        var out: [SearchResult] = []
        for block in blocks where block.kind == .searchResults {
            for result in block.results where !result.url.isEmpty {
                if seen.insert(result.url).inserted { out.append(result) }
            }
        }
        return out
    }

    var citations: [Citation] {
        blocks.flatMap(\.citations)
    }

    static func user(_ text: String, attachments: [Attachment] = []) -> ChatMessage {
        ChatMessage(role: .user, blocks: text.isEmpty ? [] : [.text(text)], attachments: attachments)
    }

    static func assistantStreaming() -> ChatMessage {
        ChatMessage(role: .assistant, isStreaming: true)
    }
}

struct Conversation: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String = "新对话"
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var isPinned: Bool = false
    var messages: [ChatMessage] = []
    var model: String?
    var titleGenerated: Bool?

    var preview: String {
        for message in messages.reversed() where message.role == .user {
            let text = message.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return "还没有消息"
    }

    var isEmpty: Bool { messages.isEmpty }
}

// MARK: - Errors

struct APIError: LocalizedError, Sendable {
    var status: Int
    var message: String

    var errorDescription: String? { message }

    var friendly: String {
        switch status {
        case 401:
            return "API Key 无效，请到「设置」里重新填写。"
        case 402:
            return "账户余额不足，请到 DeepSeek 开放平台充值后再试。"
        case 403:
            return "这个 API Key 没有访问权限。"
        case 404:
            return "接口地址不对，请检查「设置 → API 地址」。"
        case 429:
            return "请求太频繁了，等一会儿再试。"
        case 500...599:
            return "DeepSeek 服务器繁忙，稍后再试。"
        default:
            return message.isEmpty ? "请求失败（\(status)）" : message
        }
    }
}

// MARK: - Small utilities

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nilIfEmpty: String? { isEmpty ? nil : self }

    /// A plain-text version for read-aloud.
    var speechText: String {
        var s = self
        s = s.replacingOccurrences(of: "```[\\s\\S]*?```", with: " 代码块 ", options: .regularExpression)
        s = s.replacingOccurrences(of: "[#*_>`~]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var firstLine: String {
        split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? self
    }

    func prefixText(_ count: Int) -> String {
        if self.count <= count { return self }
        return String(prefix(count)) + "…"
    }
}

extension Date {
    var chatGroupTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "今天" }
        if calendar.isDateInYesterday(self) { return "昨天" }
        if let days = calendar.dateComponents([.day], from: self, to: .now).day, days < 7 {
            return "本周"
        }
        if calendar.component(.year, from: self) == calendar.component(.year, from: .now) {
            return "\(calendar.component(.month, from: self)) 月"
        }
        return "更早"
    }

    var shortClock: String {
        formatted(date: .omitted, time: .shortened)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Int {
    var clampedNonNegative: Int { Swift.max(0, self) }
}
