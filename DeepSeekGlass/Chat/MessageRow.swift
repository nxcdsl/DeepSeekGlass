import SwiftUI
import UIKit

struct MessageRow: View {
    var message: ChatMessage
    var isLastAssistant: Bool
    var streaming: Bool
    var onRegenerate: () -> Void
    var onShowSources: () -> Void
    var onSpeak: () -> Void

    var body: some View {
        if message.role == .user {
            userRow
        } else {
            assistantRow
        }
    }

    private var userRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 52)
            VStack(alignment: .trailing, spacing: 8) {
                if !message.attachments.isEmpty {
                    attachmentStrip
                }
                if !message.textContent.isEmpty {
                    Text(message.textContent)
                        .dsFont(17)
                        .lineSpacing(5)
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .background(Color.dsUserBubble, in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(message.attachments) { attachment in
                    if attachment.isImage, let data = AttachmentStore.shared.data(for: attachment), let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 148, height: 148)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: "doc.text.fill")
                                .dsFont(20)
                                .foregroundStyle(Theme.accent)
                            Text(attachment.filename)
                                .dsFont(12, weight: .medium)
                                .lineLimit(2)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                                .dsFont(10)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .frame(width: 150, height: 92, alignment: .leading)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: 300)
    }

    private var assistantRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.hasThinking {
                ThinkingSection(message: message, streaming: streaming)
            }

            if !message.textContent.isEmpty {
                MarkdownView(text: message.textContent)
            } else if streaming {
                TypingIndicator()
                    .padding(.vertical, 2)
            }

            if !message.sources.isEmpty {
                SourcesPill(results: message.sources, onTap: onShowSources)
            }

            if let error = message.errorText, !error.isEmpty {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle")
                        .dsFont(12, weight: .medium)
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                    Text(error)
                        .dsFont(13)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !streaming {
                MessageActionBar(
                    message: message,
                    isLastAssistant: isLastAssistant,
                    onRegenerate: onRegenerate,
                    onSpeak: onSpeak
                )
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Actions

struct MessageActionBar: View {
    var message: ChatMessage
    var isLastAssistant: Bool
    var onRegenerate: () -> Void
    var onSpeak: () -> Void

    @Environment(AppState.self) private var app
    @State private var copied = false
    @State private var liked = false
    @State private var disliked = false

    var body: some View {
        HStack(spacing: 23) {
            button(copied ? "checkmark" : "square.on.square", label: "复制") {
                UIPasteboard.general.string = message.textContent
                Haptics.success()
                copied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copied = false
                }
            }

            button(liked ? "hand.thumbsup.fill" : "hand.thumbsup", label: "有帮助", tint: liked ? Theme.accent : nil) {
                liked.toggle()
                if liked { disliked = false }
                Haptics.selection()
            }

            button(disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown", label: "没帮助", tint: disliked ? Theme.accent : nil) {
                disliked.toggle()
                if disliked { liked = false }
                Haptics.selection()
            }

            button(app.speech.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2", label: "朗读", tint: app.speech.isSpeaking ? Theme.accent : nil) {
                if app.speech.isSpeaking {
                    app.speech.stop()
                } else {
                    onSpeak()
                }
            }

            ShareLink(item: message.textContent) {
                Image(systemName: "square.and.arrow.up")
                    .dsFont(16, weight: .regular)
                    .foregroundStyle(Color.secondary)
                    .frame(width: 28, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("分享")

            if isLastAssistant {
                button("arrow.clockwise", label: "重新生成") {
                    Haptics.tap()
                    onRegenerate()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func button(_ icon: String, label: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .dsFont(16, weight: .regular)
                .foregroundStyle(tint ?? Color.secondary)
                .frame(width: 28, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Sources

struct SourcesPill: View {
    var results: [SearchResult]
    var onTap: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: -7) {
                    ForEach(Array(results.prefix(3).enumerated()), id: \.offset) { _, result in
                        SiteIcon(urlString: result.siteIcon, size: 19)
                            .background(Circle().fill(Theme.background))
                    }
                }
                Text("\(results.count) 个网页")
                    .dsFont(12, weight: .medium)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .dsFont(9, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.primary.opacity(0.045), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.6)
            }
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.97))
        .accessibilityLabel("查看 \(results.count) 个参考网页")
    }
}

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.6))
                    .frame(width: 5, height: 5)
                    .scaleEffect(animating ? 1.0 : 0.55)
                    .opacity(animating ? 1 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .frame(height: 22)
        .onAppear { animating = true }
    }
}
