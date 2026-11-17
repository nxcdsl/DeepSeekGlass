import AVFoundation
import Foundation
import Observation
import UIKit

// MARK: - Read aloud

@MainActor
@Observable
final class SpeechController {
    private let synthesizer = AVSpeechSynthesizer()
    private var watcher: Task<Void, Never>?

    var isSpeaking = false

    func speak(_ text: String) {
        let clean = text.speechText
        guard !clean.isEmpty else { return }
        stop()

        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            ?? AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first ?? "zh-CN")
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.05
        synthesizer.speak(utterance)
        isSpeaking = true

        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard let self else { return }
                if !self.synthesizer.isSpeaking {
                    self.isSpeaking = false
                    return
                }
            }
        }
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }
}

// MARK: - Voice input

@MainActor
@Observable
final class VoiceController {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
    }

    private let settings: AppSettings
    private var capture: AudioCapture?
    private var ticker: Task<Void, Never>?
    private var startedAt: Date?

    var phase: Phase = .idle
    var level: CGFloat = 0
    var elapsed: TimeInterval = 0
    var willCancel = false
    var error: String?
    var onAutoStop: (() -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func begin() {
        guard phase == .idle else { return }
        phase = .recording
        willCancel = false
        error = nil
        elapsed = 0
        level = 0
        startedAt = .now
        startTicker()

        Task { [weak self] in
            guard let self else { return }
            let granted: Bool = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                AVAudioApplication.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            guard self.phase == .recording else { return }
            guard granted else {
                self.fail("没有麦克风权限。到系统设置里允许 DeepSeek 使用麦克风。")
                return
            }
            do {
                try self.configureSession()
                let capture = try AudioCapture()
                self.capture = capture
                try capture.start()
            } catch {
                self.fail("麦克风启动失败：\(error.localizedDescription)")
            }
        }
    }

    func cancel() {
        finishCapture()
        phase = .idle
        willCancel = false
        level = 0
        elapsed = 0
        deactivateSession()
    }

    func finishAndTranscribe() async -> String? {
        guard phase == .recording else { return nil }
        ticker?.cancel()
        ticker = nil

        let pcm = finishCapture()
        guard pcm.count > 3_200 else {
            phase = .idle
            elapsed = 0
            level = 0
            return nil
        }

        phase = .transcribing
        level = 0
        let wav = AudioCapture.wav(pcm: pcm)
        let client = DeepSeekClient(baseURL: settings.baseURL, apiKey: settings.apiKey)
        do {
            let text = try await client.transcribe(wav: wav)
            phase = .idle
            elapsed = 0
            error = nil
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            phase = .idle
            elapsed = 0
            if let api = error as? APIError {
                self.error = api.friendly
            } else if (error as NSError).domain == NSURLErrorDomain {
                self.error = "语音识别失败，请检查网络。"
            } else {
                self.error = "语音识别失败：\(error.localizedDescription)"
            }
            return nil
        }
    }

    func setWillCancel(_ value: Bool) {
        willCancel = value
    }

    // MARK: Private

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                guard self.phase == .recording else { return }
                if let startedAt = self.startedAt {
                    self.elapsed = Date().timeIntervalSince(startedAt)
                }
                if let capture = self.capture {
                    self.level = capture.currentLevel()
                }
                if self.elapsed >= 120 {
                    self.onAutoStop?()
                    return
                }
            }
        }
    }

    @discardableResult
    private func finishCapture() -> Data {
        ticker?.cancel()
        ticker = nil
        let data = capture?.stop() ?? Data()
        capture = nil
        deactivateSession()
        return data
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.mixWithOthers, .defaultToSpeaker]
        )
        try session.setActive(true, options: [])
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fail(_ message: String) {
        finishCapture()
        phase = .idle
        error = message
        level = 0
        elapsed = 0
    }
}

// MARK: - Audio capture

private final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let lock = NSLock()
    private var pcm = Data()
    private var smoothLevel: CGFloat = 0
    private var started = false

    init() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: true
              ),
              let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw NSError(domain: "Voice", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有可用的麦克风输入"])
        }
        self.outputFormat = format
        self.converter = converter
    }

    func start() throws {
        guard !started else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
        started = true
    }

    func stop() -> Data {
        if started {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            started = false
        }
        lock.lock()
        let data = pcm
        pcm.removeAll(keepingCapacity: false)
        smoothLevel = 0
        lock.unlock()
        return data
    }

    func currentLevel() -> CGFloat {
        lock.lock()
        let value = smoothLevel
        lock.unlock()
        return value
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = output.int16ChannelData?[0] else { return }

        let count = Int(output.frameLength)
        guard count > 0 else { return }
        let data = Data(bytes: UnsafeRawPointer(channel), count: count * MemoryLayout<Int16>.size)

        var sum: Double = 0
        for index in 0..<count {
            let value = Double(channel[index]) / 32_768.0
            sum += value * value
        }
        let rms = sqrt(sum / Double(count))
        let level = CGFloat(min(1.0, rms * 7.0))

        lock.lock()
        pcm.append(data)
        smoothLevel = smoothLevel * 0.65 + level * 0.35
        lock.unlock()
    }

    static func wav(pcm: Data, sampleRate: Int = 16_000) -> Data {
        var data = Data()
        func append(_ string: String) {
            data.append(Data(string.utf8))
        }
        func append32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }

        append("RIFF")
        append32(UInt32(36 + pcm.count))
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))
        append16(2)
        append16(16)
        append("data")
        append32(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}
