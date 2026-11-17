import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var app
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var isNearBottom = true
    @State private var showAttachments = false
    @State private var showSources: [SearchResult] = []
    @FocusState private var composerFocused: Bool

    private var engine: ChatEngine { app.engine }
    private var conversation: Conversation? { app.store.selected }
    private var messages: [ChatMessage] { conversation?.messages ?? [] }
    private var lastAssistantID: UUID? {
        messages.last(where: { $0.role == .assistant })?.id
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if messages.isEmpty {
                        EmptyChatView()
                            .padding(.top, 126)
                    }

                    ForEach(messages) { message in
                        MessageRow(
                            message: message,
                            isLastAssistant: message.id == lastAssistantID,
                            streaming: message.isStreaming,
                            onRegenerate: { engine.regenerate() },
                            onShowSources: { showSources = message.sources },
                            onSpeak: { app.speech.speak(message.textContent) }
                        )
                        .id(message.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .padding(.horizontal, 18)
                .padding(.top, 88)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height
                    >= geometry.contentSize.height - 130
            } action: { _, near in
                isNearBottom = near
            }
            .onChange(of: engine.scrollTick) { _, _ in
                guard isNearBottom else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            }
            .onChange(of: messages.count) { _, _ in
                isNearBottom = true
                withAnimation(.easeOut(duration: 0.22)) {
                    scrollPosition.scrollTo(edge: .bottom)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomArea
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar(app.router.tabBarExpanded ? .visible : .hidden, for: .tabBar)
        .overlay(alignment: .top) {
            HeaderBar(
                title: conversation?.title ?? "新对话",
                autoRead: app.settings.autoReadAloud,
                isStreaming: engine.isStreaming,
                onMenu: {
                    composerFocused = false
                    app.router.drawerOpen = true
                },
                onToggleRead: {
                    app.settings.autoReadAloud.toggle()
                    if !app.settings.autoReadAloud { app.speech.stop() }
                    Haptics.selection()
                },
                onNewChat: {
                    composerFocused = false
                    engine.newChat()
                }
            )
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .overlay(alignment: .leading) {
            edgeCatcher
        }
        .sheet(isPresented: $showAttachments) {
            AttachmentTray(
                onImage: { image in
                    engine.addImage(image)
                    showAttachments = false
                },
                onFile: { url in
                    engine.addDocument(url: url)
                    showAttachments = false
                }
            )
            .presentationDetents([.height(348)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: Binding(
            get: { !showSources.isEmpty },
            set: { if !$0 { showSources = [] } }
        )) {
            SourceListView(results: showSources)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: app.router.tab) { _, tab in
            if tab != .chat {
                composerFocused = false
            } else {
                app.router.tabBarExpanded = false
            }
        }
        .onChange(of: app.store.selectedID) { _, _ in
            if engine.isStreaming { engine.stop() }
            composerFocused = false
        }
    }

    private var bottomArea: some View {
        VStack(spacing: 8) {
            if let error = engine.errorMessage {
                ErrorBanner(text: error) {
                    engine.dismissError()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let voiceError = app.voice.error, app.voice.phase == .idle {
                HStack(spacing: 8) {
                    Image(systemName: "mic.slash")
                    Text(voiceError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        app.voice.error = nil
                    } label: {
                        Image(systemName: "xmark")
                            .dsFont(10, weight: .semibold)
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
                .dsFont(12)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !app.settings.hasAPIKey {
                APIKeyBanner {
                    app.router.tab = .settings
                }
            }

            ComposerView(
                engine: engine,
                focused: $composerFocused,
                onPlus: { showAttachments = true }
            )

            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.26)) {
                        app.router.tabBarExpanded.toggle()
                    }
                } label: {
                    Image(systemName: app.router.tabBarExpanded ? "chevron.down" : "gearshape")
                        .dsFont(15, weight: .medium)
                        .foregroundStyle(Color.primary.opacity(0.82))
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                }
                .buttonStyle(GlassPressStyle())
                .glassSurface(.circle, interactive: true)
                .accessibilityLabel(app.router.tabBarExpanded ? "收起标签栏" : "展开标签栏")

                Text("回答由 AI 生成，仅供参考")
                    .dsFont(11)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)
            }
            .padding(.leading, 2)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .padding(.top, 4)
        .animation(.snappy(duration: 0.22), value: engine.errorMessage)
    }

    private var edgeCatcher: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 18)
            .frame(maxHeight: .infinity)
            .padding(.top, 80)
            .padding(.bottom, 140)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 14)
                    .onEnded { value in
                        guard !app.router.drawerOpen else { return }
                        if value.translation.width > 52, abs(value.translation.height) < 80 {
                            Haptics.tap()
                            withAnimation(.snappy(duration: 0.28)) {
                                app.router.drawerOpen = true
                            }
                        }
                    }
            )
            .allowsHitTesting(!app.router.drawerOpen)
    }
}

// MARK: - Header

struct HeaderBar: View {
    var title: String
    var autoRead: Bool
    var isStreaming: Bool
    var onMenu: () -> Void
    var onToggleRead: () -> Void
    var onNewChat: () -> Void

    var body: some View {
        ZStack {
            HStack {
                Button(action: onMenu) {
                    MenuGlyph()
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(GlassPressStyle())
                .glassSurface(.circle, interactive: true)
                .accessibilityLabel("打开对话列表")

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    Button(action: onToggleRead) {
                        Image(systemName: autoRead ? "speaker.wave.2.fill" : "speaker.slash")
                            .dsFont(16, weight: .medium)
                            .foregroundStyle(autoRead ? Theme.accent : Color.primary.opacity(0.82))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(GlassPressStyle())
                    .accessibilityLabel(autoRead ? "关闭自动朗读" : "打开自动朗读")

                    Rectangle()
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 0.6, height: 20)

                    Button(action: onNewChat) {
                        Image(systemName: "plus")
                            .dsFont(17, weight: .medium)
                            .foregroundStyle(Color.primary.opacity(0.9))
                            .frame(width: 46, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(GlassPressStyle())
                    .accessibilityLabel("新对话")
                }
                .glassSurface(.capsule, interactive: true)
            }

            Text(title)
                .dsFont(17, weight: .semibold)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 118)
                .allowsHitTesting(false)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: title)
        }
        .frame(height: 46)
    }
}

// MARK: - Empty state

struct EmptyChatView: View {
    @State private var appeared = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<11: return "早上好，有什么可以帮到你？"
        case 11..<14: return "中午好，有什么可以帮到你？"
        case 14..<18: return "下午好，有什么可以帮到你？"
        case 18..<23: return "晚上好，有什么可以帮到你？"
        default: return "还没睡呀，有什么可以帮到你？"
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            WhaleLogo(size: 78)
                .scaleEffect(appeared ? 1 : 0.9)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)

            Text(greeting)
                .dsFont(21, weight: .semibold)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.35).delay(0.06), value: appeared)
        }
        .frame(maxWidth: .infinity)
        .onAppear { appeared = true }
    }
}

// MARK: - Banners

struct ErrorBanner: View {
    var text: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.circle")
                .dsFont(14, weight: .medium)
                .foregroundStyle(Color.orange)
                .padding(.top, 1)
            Text(text)
                .dsFont(13)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .dsFont(11, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 0.7)
        }
    }
}

struct APIKeyBanner: View {
    var onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.horizontal")
                .dsFont(14, weight: .medium)
                .foregroundStyle(Theme.accent)
            Text("填入 DeepSeek API Key 后就能开始对话")
                .dsFont(12)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("去设置", action: onOpenSettings)
                .dsFont(12, weight: .semibold)
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.16), lineWidth: 0.6)
        }
    }
}

// MARK: - Sources

struct SourceListView: View {
    var results: [SearchResult]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(results) { result in
                Link(destination: URL(string: result.url) ?? URL(string: "https://deepseek.com")!) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.title)
                            .dsFont(15, weight: .medium)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                        if let snippet = result.snippet, !snippet.isEmpty {
                            Text(snippet)
                                .dsFont(12)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        HStack(spacing: 5) {
                            SiteIcon(urlString: result.siteIcon, size: 14)
                            Text(result.siteName ?? URL(string: result.url)?.host ?? "")
                                .dsFont(11)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle("参考来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct SiteIcon: View {
    var urlString: String?
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5) }
    }

    private var fallback: some View {
        Circle()
            .fill(Theme.accent.opacity(0.18))
            .overlay {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(Theme.accent.opacity(0.8))
            }
    }
}
