import Foundation
import Observation
import Security

// MARK: - Keychain

enum KeychainStore {
    private static let service = "com.nxcdsl.deepseekglass"
    private static let account = "deepseek-api-key"

    static func readAPIKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    @discardableResult
    static func saveAPIKey(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            attributes.forEach { add[$0.key] = $0.value }
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Attachments on disk

@MainActor
final class AttachmentStore {
    static let shared = AttachmentStore()

    let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("DeepSeekGlass/Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func save(data: Data, kind: Attachment.Kind, filename: String) -> Attachment? {
        let ext: String
        switch kind {
        case .image: ext = "jpg"
        case .text: ext = "txt"
        case .pdf: ext = "pdf"
        }
        let stored = UUID().uuidString + "." + ext
        let url = directory.appendingPathComponent(stored)
        do {
            try data.write(to: url, options: .atomic)
            return Attachment(kind: kind, filename: filename, storedName: stored, byteCount: data.count)
        } catch {
            return nil
        }
    }

    func data(for attachment: Attachment) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(attachment.storedName))
    }

    func url(for attachment: Attachment) -> URL {
        directory.appendingPathComponent(attachment.storedName)
    }

    func delete(_ attachment: Attachment) {
        try? FileManager.default.removeItem(at: url(for: attachment))
    }

    func delete(contentsOf conversation: Conversation) {
        for message in conversation.messages {
            message.attachments.forEach(delete)
        }
    }
}

/// An attachment that has not been sent yet.
struct PendingAttachment: Identifiable {
    var id = UUID()
    var kind: Attachment.Kind
    var filename: String
    var data: Data
    var extractedText: String?
}

// MARK: - Conversation store

@MainActor
@Observable
final class ConversationStore {
    private(set) var conversations: [Conversation] = []
    private(set) var isLoaded = false

    var selectedID: UUID? {
        didSet {
            UserDefaults.standard.set(selectedID?.uuidString, forKey: Keys.selected)
        }
    }

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    private enum Keys {
        static let selected = "selectedConversationID"
    }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("DeepSeekGlass", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("conversations.json")

        if let stored = UserDefaults.standard.string(forKey: Keys.selected) {
            selectedID = UUID(uuidString: stored)
        }
        load()
    }

    // MARK: Loading and saving

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            isLoaded = true
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let stored = try? decoder.decode([Conversation].self, from: data) {
            let migrated = stored.map { item -> Conversation in
                var conversation = item
                if conversation.titleGenerated == nil, conversation.title != "新对话" {
                    conversation.titleGenerated = true
                }
                return conversation
            }
            conversations = migrated.sorted { $0.updatedAt > $1.updatedAt }
            if selectedID == nil { selectedID = conversations.first?.id }
        } else {
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("conversations.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
        isLoaded = true
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = conversations
        let url = fileURL
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    func flush() {
        saveTask?.cancel()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(conversations) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Queries

    func index(of id: UUID) -> Int? {
        conversations.firstIndex { $0.id == id }
    }

    func conversation(for id: UUID?) -> Conversation? {
        guard let id else { return nil }
        return conversations.first { $0.id == id }
    }

    var selected: Conversation? { conversation(for: selectedID) }

    func filtered(_ query: String) -> [Conversation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return conversations }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.messages.contains { $0.textContent.localizedCaseInsensitiveContains(q) }
        }
    }

    /// Pinned first, then date groups, matching the native drawer.
    func grouped(_ query: String = "") -> [(String, [Conversation])] {
        let list = filtered(query)
        let pinned = list.filter(\.isPinned)
        var groups: [(String, [Conversation])] = []
        if !pinned.isEmpty { groups.append(("置顶", pinned)) }

        let unpinned = list.filter { !$0.isPinned }
        var buckets: [String: [Conversation]] = [:]
        var order: [String] = []
        for conversation in unpinned {
            let title = conversation.updatedAt.chatGroupTitle
            if buckets[title] == nil {
                buckets[title] = []
                order.append(title)
            }
            buckets[title]?.append(conversation)
        }
        let preferred = ["今天", "昨天", "本周"]
        order.sort { lhs, rhs in
            let l = preferred.firstIndex(of: lhs) ?? 99
            let r = preferred.firstIndex(of: rhs) ?? 99
            return l < r
        }
        for title in order {
            if let items = buckets[title], !items.isEmpty {
                groups.append((title, items.sorted { $0.updatedAt > $1.updatedAt }))
            }
        }
        return groups
    }

    // MARK: Mutations

    @discardableResult
    func createConversation(select: Bool = true) -> UUID {
        if let existing = selected, existing.messages.isEmpty {
            return existing.id
        }
        let conversation = Conversation()
        conversations.insert(conversation, at: 0)
        if select { selectedID = conversation.id }
        scheduleSave()
        return conversation.id
    }

    func replace(_ conversation: Conversation) {
        guard let index = index(of: conversation.id) else {
            conversations.insert(conversation, at: 0)
            scheduleSave()
            return
        }
        conversations[index] = conversation
        scheduleSave()
    }

    func update(_ id: UUID, _ mutate: (inout Conversation) -> Void) {
        guard let index = index(of: id) else { return }
        var conversation = conversations[index]
        mutate(&conversation)
        conversation.updatedAt = .now
        conversations[index] = conversation
        scheduleSave()
    }

    func appendMessage(_ message: ChatMessage, to id: UUID) {
        update(id) { $0.messages.append(message) }
    }

    func select(_ id: UUID?) {
        selectedID = id
    }

    func delete(_ id: UUID) {
        guard let index = index(of: id) else { return }
        let conversation = conversations[index]
        AttachmentStore.shared.delete(contentsOf: conversation)
        conversations.remove(at: index)
        if selectedID == id { selectedID = conversations.first?.id }
        scheduleSave()
    }

    func deleteAll() {
        for conversation in conversations {
            AttachmentStore.shared.delete(contentsOf: conversation)
        }
        conversations.removeAll()
        selectedID = nil
        scheduleSave()
    }

    func togglePin(_ id: UUID) {
        update(id) { $0.isPinned.toggle() }
    }

    func rename(_ id: UUID, to title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        update(id) {
            $0.title = clean
            $0.titleGenerated = true
        }
    }
}
