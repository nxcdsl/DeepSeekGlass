import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct SSEEvent: Sendable {
    var name: String
    var data: String
}

struct DeepSeekClient: Sendable {
    var baseURL: String
    var apiKey: String

    private var root: String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value.isEmpty ? "https://api.deepseek.com" : value
    }

    private func url(_ path: String) -> URL? {
        URL(string: root + path)
    }

    // MARK: - Chat (Anthropic-compatible Messages API)

    func streamMessages(body: Data) -> AsyncThrowingStream<SSEEvent, Error> {
        let key = apiKey
        guard let endpoint = url("/anthropic/v1/messages") else {
            return AsyncThrowingStream { $0.finish(throwing: APIError(status: 0, message: "API 地址无效")) }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 600
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(key, forHTTPHeaderField: "x-api-key")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = body

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError(status: 0, message: "没有收到服务器响应")
                    }
                    if !(200..<300).contains(http.statusCode) {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw Self.error(from: data, status: http.statusCode)
                    }

                    var eventName = ""
                    for try await rawLine in bytes.lines {
                        let line = rawLine.trimmingCharacters(in: .newlines)
                        if line.isEmpty {
                            eventName = ""
                            continue
                        }
                        if line.hasPrefix(":") { continue }
                        if line.hasPrefix("event:") {
                            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            guard !payload.isEmpty, payload != "[DONE]" else { continue }
                            continuation.yield(SSEEvent(name: eventName, data: payload))
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Speech to text

    func transcribe(wav: Data) async throws -> String {
        guard let endpoint = url("/v1/tools/asr") else {
            throw APIError(status: 0, message: "API 地址无效")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(wav)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "没有收到服务器响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(from: data, status: http.statusCode)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String else {
            throw APIError(status: http.statusCode, message: "语音识别失败")
        }
        return text
    }

    // MARK: - Key check

    func validate() async throws {
        guard let endpoint = url("/models") else {
            throw APIError(status: 0, message: "API 地址无效")
        }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "没有收到服务器响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(from: data, status: http.statusCode)
        }
    }

    // MARK: - Errors

    static func error(from data: Data, status: Int) -> APIError {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                return APIError(status: status, message: message)
            }
            if let message = object["message"] as? String {
                return APIError(status: status, message: message)
            }
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return APIError(status: status, message: raw.isEmpty ? "HTTP \(status)" : raw.prefixText(300))
    }
}
