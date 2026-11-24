import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ChatEngine {
    private let store: ConversationStore
    private let settings: AppSettings
    private let usage: UsageStore
    let speech: SpeechController
    let voice: VoiceController

    var draft = ""
    var pending: [PendingAttachment] = []
    var isStreaming = false
    var errorMessage: String?
    var toast: String?
    var deepThinking: Bool
    var webSearch: Bool
    var scrollTick = 0
    var thinkingNow = false
    var isTranscribing: Bool { voice.phase == .transcribing }

    private var task: Task<Void, Never>?
    private var liveConversation: Conversation?
    private var liveMessage: ChatMessage?
    private var assistantID: UUID?
    private var blockMap: [Int: String] = [:]
    private var citationCounter = 0
    private var firstThinkingAt: Date?
    private var lastFlush = Date.distantPast
    private var titleFromAPI: String?
    private var startedAt = Date()
    private var recordedUsage = false
    private var debugRequest: Data?
    private var debugUsage: [String: Any] = [:]
    private var debugMessageCount = 0
    private var debugStopReason = ""

    init(store: ConversationStore, settings: AppSettings, speech: SpeechController, voice: VoiceController, usage: UsageStore) {
        self.store = store
        self.settings = settings
        self.speech = speech
        self.voice = voice
        self.usage = usage
        self.deepThinking = settings.deepThinking
        self.webSearch = settings.webSearch
        voice.onAutoStop = { [weak self] in
            self?.endVoice(cancelled: false)
        }
    }

    // MARK: - Sending

    func send() {
        guard !isStreaming else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pending.isEmpty else { return }
        guard settings.hasAPIKey else {
            errorMessage = "还没有填 DeepSeek API Key。到「设置」里填上就能聊了。"
            return
        }
        let apiKey = APIKeyInput.clean(settings.apiKey)
        if let problem = APIKeyInput.problem(for: apiKey, baseURL: settings.baseURL) {
            errorMessage = problem
            return
        }

        let conversationID = ensureConversation()
        guard store.conversation(for: conversationID) != nil else { return }

        var attachments: [Attachment] = []
        for item in pending {
            guard var attachment = AttachmentStore.shared.save(data: item.data, kind: item.kind, filename: item.filename) else { continue }
            attachment.extractedText = item.extractedText
            attachments.append(attachment)
        }

        var userMessage = ChatMessage(role: .user, attachments: attachments)
        if !text.isEmpty { userMessage.blocks = [.text(text)] }
        let assistant = ChatMessage.assistantStreaming()

        store.update(conversationID) { conversation in
            conversation.messages.append(userMessage)
            conversation.messages.append(assistant)
            conversation.updatedAt = .now
            if conversation.title == "新对话", !text.isEmpty {
                conversation.title = Self.fallbackTitle(text)
            }
        }

        draft = ""
        pending = []
        errorMessage = nil
        startStreaming(conversationID: conversationID, assistantID: assistant.id)
    }

    func stop() {
        task?.cancel()
        task = nil
        finishStream(error: nil)
    }

    func regenerate() {
        guard !isStreaming, let conversationID = store.selectedID,
              var conversation = store.conversation(for: conversationID) else { return }

        while let last = conversation.messages.last, last.role == .assistant {
            conversation.messages.removeLast()
        }
        guard conversation.messages.last?.role == .user else { return }

        let assistant = ChatMessage.assistantStreaming()
        conversation.messages.append(assistant)
        conversation.updatedAt = .now
        store.replace(conversation)
        errorMessage = nil
        startStreaming(conversationID: conversationID, assistantID: assistant.id)
    }

    func newChat() {
        if isStreaming { stop() }
        draft = ""
        pending = []
        errorMessage = nil
        toast = nil
        store.createConversation()
    }

    private func ensureConversation() -> UUID {
        if let id = store.selectedID, store.conversation(for: id) != nil {
            return id
        }
        return store.createConversation()
    }

    private static func fallbackTitle(_ text: String) -> String {
        let first = text.firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return first.prefixText(22)
    }

    // MARK: - Streaming

    private func startStreaming(conversationID: UUID, assistantID: UUID) {
        guard let conversation = store.conversation(for: conversationID),
              let assistant = conversation.messages.first(where: { $0.id == assistantID }),
              let body = makeRequestBody(conversation: conversation) else {
            errorMessage = "组请求失败，请检查设置。"
            store.update(conversationID) { conversation in
                if let index = conversation.messages.firstIndex(where: { $0.id == assistantID }) {
                    conversation.messages[index].isStreaming = false
                    conversation.messages[index].errorText = "没有可发送的内容。"
                }
            }
            return
        }

        self.assistantID = assistantID
        liveConversation = conversation
        liveMessage = assistant
        blockMap.removeAll()
        citationCounter = 0
        firstThinkingAt = nil
        titleFromAPI = nil
        recordedUsage = false
        lastFlush = .distantPast
        startedAt = .now
        thinkingNow = deepThinking
        isStreaming = true
        errorMessage = nil
        debugRequest = body
        debugUsage = [:]
        debugStopReason = ""
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let messages = object["messages"] as? [[String: Any]] {
            debugMessageCount = messages.count
        } else {
            debugMessageCount = 0
        }

        let client = DeepSeekClient(baseURL: settings.baseURL, apiKey: settings.apiKey)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in client.streamMessages(body: body) {
                    if Task.isCancelled { break }
                    self.handle(event)
                }
                self.finishStream(error: nil)
            } catch is CancellationError {
                self.finishStream(error: nil)
            } catch {
                self.finishStream(error: error)
            }
        }
    }

    private func handle(_ event: SSEEvent) {
        guard let data = event.data.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        switch event.name {
        case "content_block_start":
            handleBlockStart(object)
        case "content_block_delta":
            handleBlockDelta(object)
        case "content_block_stop":
            handleBlockStop(object)
        case "message_delta":
            handleMessageDelta(object)
        case "message_stop":
            break
        case "error":
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                errorMessage = message
            }
        default:
            break
        }
    }

    private func handleBlockStart(_ object: [String: Any]) {
        guard let index = object["index"] as? Int,
              let block = object["content_block"] as? [String: Any],
              let type = block["type"] as? String,
              var message = liveMessage else { return }

        let id = "\(assistantID?.uuidString ?? UUID().uuidString)-\(index)"
        var content = ContentBlock(id: id, kind: .text)

        switch type {
        case "thinking":
            content.kind = .thinking
            content.text = block["thinking"] as? String ?? ""
            content.signature = block["signature"] as? String
            content.startedAt = .now
            if firstThinkingAt == nil { firstThinkingAt = .now }
            thinkingNow = true

        case "text":
            content.kind = .text
            content.text = block["text"] as? String ?? ""
            if let start = firstThinkingAt, message.thinkingSeconds == nil {
                message.thinkingSeconds = max(1, Int(Date().timeIntervalSince(start)))
            }
            thinkingNow = message.blocks.contains { $0.kind == .thinking && !$0.isComplete }

        case "server_tool_use":
            content.kind = .toolUse
            content.toolID = block["id"] as? String
            content.toolName = block["name"] as? String
            content.toolKind = block["kind"] as? String
            if let input = block["input"] as? [String: Any] {
                content.action = input["action"] as? String
                content.queries = input["queries"] as? [String] ?? []
                content.url = input["url"] as? String
                content.pattern = input["pattern"] as? String
            }
            content.isComplete = true

        case "web_search_tool_result":
            content.kind = .searchResults
            content.toolID = block["tool_use_id"] as? String
            content.toolKind = block["kind"] as? String
            content.results = Self.parseResults(block["content"])
            content.isComplete = true

        case "web_fetch_tool_result":
            content.kind = .fetchResult
            content.toolID = block["tool_use_id"] as? String
            content.toolKind = block["kind"] as? String
            if let result = block["content"] as? [String: Any] {
                if let errorCode = result["error_code"] as? String {
                    content.fetchError = errorCode
                }
                content.url = result["url"] as? String
                if let nested = result["content"] as? [String: Any] {
                    content.fetchTitle = nested["title"] as? String
                }
            }
            content.isComplete = true

        default:
            return
        }

        blockMap[index] = id
        message.blocks.append(content)
        liveMessage = message
        flush(force: true)
    }

    private func handleBlockDelta(_ object: [String: Any]) {
        guard let index = object["index"] as? Int,
              let id = blockMap[index],
              let delta = object["delta"] as? [String: Any],
              let type = delta["type"] as? String,
              var message = liveMessage,
              let blockIndex = message.blocks.firstIndex(where: { $0.id == id }) else {
            return
        }

        switch type {
        case "text_delta":
            message.blocks[blockIndex].text += delta["text"] as? String ?? ""
            if let start = firstThinkingAt, message.thinkingSeconds == nil, !message.blocks[blockIndex].text.isEmpty {
                message.thinkingSeconds = max(1, Int(Date().timeIntervalSince(start)))
            }
        case "thinking_delta":
            message.blocks[blockIndex].text += delta["thinking"] as? String ?? ""
        case "signature_delta":
            message.blocks[blockIndex].signature = delta["signature"] as? String
        case "citations_delta":
            if let raw = delta["citation"] as? [String: Any] {
                citationCounter += 1
                let citation = Citation(
                    index: citationCounter,
                    url: raw["url"] as? String ?? "",
                    title: raw["title"] as? String,
                    citedText: raw["cited_text"] as? String
                )
                message.blocks[blockIndex].citations.append(citation)
                message.blocks[blockIndex].text += " " + Self.superscript(citationCounter)
            }
        default:
            break
        }

        liveMessage = message
        maybeFlush()
    }

    private func handleBlockStop(_ object: [String: Any]) {
        guard let index = object["index"] as? Int,
              let id = blockMap[index],
              var message = liveMessage,
              let blockIndex = message.blocks.firstIndex(where: { $0.id == id }) else { return }
        message.blocks[blockIndex].isComplete = true
        message.blocks[blockIndex].finishedAt = .now
        thinkingNow = message.blocks.contains { $0.kind == .thinking && !$0.isComplete }
        liveMessage = message
        flush(force: true)
    }

    private func handleMessageDelta(_ object: [String: Any]) {
        guard let delta = object["delta"] as? [String: Any] else { return }
        if let title = delta["title"] as? String,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           liveConversation?.titleGenerated != true {
            titleFromAPI = title
            liveConversation?.title = title
            liveConversation?.titleGenerated = true
            if let conversationID = liveConversation?.id {
                store.update(conversationID) {
                    $0.title = title
                    $0.titleGenerated = true
                }
            }
        }
        if let stop = delta["stop_reason"] as? String {
            liveMessage?.stopReason = stop
            debugStopReason = stop
        }
        if let usageObject = object["usage"] as? [String: Any] {
            let input = usageObject["input_tokens"] as? Int
                ?? usageObject["prompt_tokens"] as? Int
                ?? 0
            let output = usageObject["output_tokens"] as? Int
                ?? usageObject["completion_tokens"] as? Int
                ?? 0
            var normalized = usageObject
            normalized["prompt_tokens"] = input
            normalized["completion_tokens"] = output
            let hit = usageObject["prompt_cache_hit_tokens"] as? Int
                ?? usageObject["cache_read_input_tokens"] as? Int
                ?? 0
            let explicitMiss = usageObject["prompt_cache_miss_tokens"] as? Int
                ?? usageObject["cache_creation_input_tokens"] as? Int
            let miss = (explicitMiss ?? 0) > 0 ? explicitMiss! : max(0, input - hit)
            normalized["prompt_cache_hit_tokens"] = hit
            normalized["prompt_cache_miss_tokens"] = miss
            debugUsage = normalized
            if !recordedUsage, input > 0 || output > 0 {
                recordedUsage = true
                usage.record(input: input, output: output)
            }
        }
    }

    private func maybeFlush() {
        guard Date().timeIntervalSince(lastFlush) > 0.055 else { return }
        flush(force: false)
    }

    private func flush(force: Bool) {
        guard force || Date().timeIntervalSince(lastFlush) > 0.055 else { return }
        guard var conversation = liveConversation,
              let message = liveMessage,
              let messageIndex = conversation.messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        conversation.messages[messageIndex] = message
        conversation.updatedAt = .now
        liveConversation = conversation
        store.replace(conversation)
        lastFlush = .now
        scrollTick &+= 1
    }

    private func finishStream(error: Error?) {
        guard isStreaming else { return }
        isStreaming = false
        thinkingNow = false
        task = nil

        guard var conversation = liveConversation,
              var message = liveMessage,
              let messageIndex = conversation.messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }

        message.isStreaming = false
        if message.thinkingSeconds == nil, let start = firstThinkingAt {
            message.thinkingSeconds = max(1, Int(Date().timeIntervalSince(start)))
        }
        if message.stopReason == "refusal" {
            message.errorText = "这次回答被安全策略拦下了，换个说法再试试。"
        }
        if let error {
            let friendly = friendlyMessage(error)
            errorMessage = friendly
            if message.blocks.filter({ $0.kind == .text }).allSatisfy({ $0.text.isEmpty }) {
                message.errorText = friendly
            }
        }
        if message.blocks.isEmpty, message.errorText == nil {
            message.errorText = "没有收到内容，请稍后再试。"
        }

        conversation.messages[messageIndex] = message
        if conversation.titleGenerated != true {
            if let title = titleFromAPI, !title.isEmpty {
                conversation.title = title
            } else if conversation.title == "新对话" {
                if let firstUser = conversation.messages.first(where: { $0.role == .user }) {
                    let text = firstUser.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { conversation.title = Self.fallbackTitle(text) }
                }
            }
            conversation.titleGenerated = true
        }
        conversation.updatedAt = .now
        liveConversation = conversation
        store.replace(conversation)
        scrollTick &+= 1

        if error != nil {
            Haptics.warning()
        } else if message.errorText == nil {
            Haptics.success()
            if settings.autoReadAloud {
                let text = message.textContent
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    speech.speak(text)
                }
            }
        }

        writeDebugLog(errorText: message.errorText ?? error.map { friendlyMessage($0) })
    }

    private func writeDebugLog(errorText: String?) {
        guard settings.debugLoggingEnabled, let request = debugRequest else { return }
        let response: [String: Any] = [
            "usage": debugUsage,
            "request_bytes": request.count,
            "messages_count": debugMessageCount,
            "stop_reason": debugStopReason,
            "error": errorText ?? ""
        ]
        let responseData = (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
        debugRequest = nil
        Task {
            await APIDebugLogger.shared.record(request: request, response: responseData)
        }
    }

    private func friendlyMessage(_ error: Error) -> String {
        if let api = error as? APIError { return api.friendly }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "网络连接失败，请检查网络或「设置 → API 地址」。"
        }
        return error.localizedDescription.isEmpty ? "请求失败，请稍后再试。" : error.localizedDescription
    }

    // MARK: - Request body

    private func makeRequestBody(conversation: Conversation) -> Data? {
        let level = settings.consumption
        let compressionWindow = level == .custom ? settings.customCompressionWindow : level.compressionWindow
        let attachmentLimit = level == .custom ? settings.customAttachmentLimit : level.attachmentLimit
        let historyLimit = level == .custom ? settings.customHistoryLimit : level.maxMessages
        var sourceMessages = conversation.messages
        var memorySummary = ""

        if settings.contextCompression, sourceMessages.count > compressionWindow + 1 {
            let oldMessages = Array(sourceMessages.dropLast(compressionWindow))
            memorySummary = ContextCompressor.summarize(oldMessages)
            sourceMessages = Array(sourceMessages.suffix(compressionWindow))
            while let first = sourceMessages.first, first.role == .assistant {
                sourceMessages.removeFirst()
            }
        }

        if let maxMessages = historyLimit, sourceMessages.count > maxMessages {
            sourceMessages = Array(sourceMessages.suffix(maxMessages))
            while let first = sourceMessages.first, first.role == .assistant {
                sourceMessages.removeFirst()
            }
        }
        var messages: [[String: Any]] = []

        for message in sourceMessages {
            switch message.role {
            case .assistant:
                var content: [[String: Any]] = []
                for block in message.blocks {
                    if block.kind == .thinking, level.includesThinkingHistory, !block.text.isEmpty,
                       let signature = block.signature, !signature.isEmpty {
                        content.append([
                            "type": "thinking",
                            "thinking": block.text,
                            "signature": signature
                        ])
                    } else if block.kind == .text, !block.text.isEmpty {
                        content.append(["type": "text", "text": block.text])
                    }
                }
                if !content.isEmpty {
                    messages.append(["role": "assistant", "content": content])
                }

            case .user:
                var content: [[String: Any]] = []
                var text = message.textContent
                for attachment in message.attachments where !attachment.isImage {
                    let body = attachment.extractedText ?? ""
                    guard !body.isEmpty else { continue }
                    text += "\n\n[附件：\(attachment.filename)]\n\(body.prefix(attachmentLimit))"
                }
                if !text.isEmpty {
                    content.append(["type": "text", "text": text])
                }
                for attachment in message.attachments where attachment.isImage {
                    guard let data = AttachmentStore.shared.data(for: attachment) else { continue }
                    content.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": data.base64EncodedString()
                        ]
                    ])
                }
                if content.isEmpty {
                    content.append(["type": "text", "text": ""])
                }
                messages.append(["role": "user", "content": content])
            }
        }

        guard !messages.isEmpty else { return nil }

        let temperature = settings.temperatureOverrideEnabled
            ? settings.temperature
            : (settings.persona == .companion ? 0.8 : 0.6)
        var body: [String: Any] = [
            "model": settings.model,
            "max_tokens": settings.maxTokens,
            "stream": true,
            "temperature": temperature,
            "top_p": settings.topP,
            "messages": messages,
            "title": ["enabled": settings.generatesTitle && level.allowsTitle && conversation.titleGenerated != true]
        ]

        var system = settings.effectiveSystemPrompt
        if !memorySummary.isEmpty {
            if !system.isEmpty { system += "\n\n" }
            system += "[早前对话压缩记忆]\n\(memorySummary)"
        }
        if !system.isEmpty { body["system"] = system }

        body["thinking"] = ["type": deepThinking ? "enabled" : "disabled"]
        if deepThinking {
            body["output_config"] = ["effort": settings.effort.rawValue]
        }
        if webSearch {
            body["tools"] = [
                ["type": "deepseek_web_search", "name": "deepseek_web_search"],
                ["type": "deepseek_read_url", "name": "deepseek_read_url"]
            ]
        }

        return try? JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Attachments

    func addImage(_ image: UIImage) {
        let scaled = image.downscaled(maxDimension: 1568)
        guard let data = scaled.jpegData(compressionQuality: 0.82) else { return }
        pending.append(PendingAttachment(kind: .image, filename: "photo.jpg", data: data))
        Haptics.success()
    }

    func addImageData(_ data: Data, filename: String) {
        guard let image = UIImage(data: data) else { return }
        addImage(image)
    }

    func addDocument(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            toast = "读不到这个文件"
            return
        }
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let text = PDFExtractor.text(from: data), !text.isEmpty else {
                toast = "这个 PDF 里没有可提取的文字"
                return
            }
            pending.append(PendingAttachment(kind: .pdf, filename: url.lastPathComponent, data: data, extractedText: text))
        } else {
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                toast = "暂时只支持 txt / md / pdf 文件"
                return
            }
            pending.append(PendingAttachment(kind: .text, filename: url.lastPathComponent, data: data, extractedText: text))
        }
        Haptics.success()
    }

    func removePending(_ id: UUID) {
        pending.removeAll { $0.id == id }
    }

    // MARK: - Voice

    func beginVoice() {
        errorMessage = nil
        voice.begin()
    }

    func endVoice(cancelled: Bool) {
        if cancelled {
            voice.cancel()
            return
        }
        Task {
            guard let text = await voice.finishAndTranscribe(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            draft = text
            send()
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Helpers

    private static func parseResults(_ value: Any?) -> [SearchResult] {
        guard let array = value as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            guard (item["type"] as? String) == "web_search_result" else { return nil }
            let url = item["url"] as? String ?? ""
            guard !url.isEmpty else { return nil }
            return SearchResult(
                title: item["title"] as? String ?? url,
                url: url,
                snippet: item["snippet"] as? String,
                siteName: item["site_name"] as? String,
                siteIcon: item["site_icon"] as? String,
                pageAge: item["page_age"] as? String,
                imageURL: item["image_url"] as? String
            )
        }
    }

    static func superscript(_ number: Int) -> String {
        let map: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"
        ]
        return String(String(number).map { map[$0] ?? $0 })
    }
}
