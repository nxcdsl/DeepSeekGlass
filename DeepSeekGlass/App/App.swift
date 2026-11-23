import Observation
import SwiftUI

@MainActor
@Observable
final class AppRouter {
    enum Tab: Hashable {
        case chat
        case history
        case settings
    }

    var tab: Tab = .chat
    var drawerOpen = false
    var tabBarExpanded = false

    func openChat(_ id: UUID, store: ConversationStore) {
        store.selectedID = id
        tab = .chat
        drawerOpen = false
    }

    func newChat(store: ConversationStore) {
        store.createConversation()
        tab = .chat
        drawerOpen = false
    }
}

@MainActor
@Observable
final class AppState {
    let settings: AppSettings
    let store: ConversationStore
    let router: AppRouter
    let speech: SpeechController
    let voice: VoiceController
    let usage: UsageStore
    let engine: ChatEngine

    init() {
        let settings = AppSettings()
        let store = ConversationStore()
        let speech = SpeechController()
        let voice = VoiceController(settings: settings)
        let usage = UsageStore()
        self.settings = settings
        self.store = store
        self.speech = speech
        self.voice = voice
        self.usage = usage
        self.router = AppRouter()
        self.engine = ChatEngine(store: store, settings: settings, speech: speech, voice: voice, usage: usage)
    }
}

@main
struct DeepSeekGlassApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(app.settings.theme)
                .environment(app)
                .environment(\.dsFontScale, app.settings.fontScale)
                .preferredColorScheme(app.settings.appearance.colorScheme)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var router = app.router

        ZStack {
            TabView(selection: $router.tab) {
                Tab("对话", systemImage: "bubble.left.and.bubble.right.fill", value: AppRouter.Tab.chat) {
                    ChatView()
                }
                Tab("历史", systemImage: "clock.arrow.circlepath", value: AppRouter.Tab.history) {
                    HistoryView()
                }
                Tab("设置", systemImage: "gearshape.fill", value: AppRouter.Tab.settings) {
                    SettingsView()
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tint(Theme.accent)
            .toolbar(.hidden, for: .tabBar)

            if router.tab != .chat {
                VStack {
                    Spacer()
                    GlobalTabBar()
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }
                .zIndex(1)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .scale(scale: 0.18, anchor: .bottomLeading).combined(with: .opacity)
                ))
            }

            if router.drawerOpen {
                SidebarView()
                    .zIndex(2)
                    .transition(.opacity)
            }

            if app.voice.phase != .idle {
                VoiceOverlay()
                    .zIndex(3)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.dsFontScale, app.settings.fontScale)
        .animation(Motion.drawer, value: router.drawerOpen)
        .animation(.easeOut(duration: 0.14), value: app.voice.phase)
    }
}

struct GlobalTabBar: View {
    @Environment(AppState.self) private var app
    @Namespace private var namespace
    @State private var visualTab: AppRouter.Tab = .history

    var body: some View {
        HStack(spacing: 3) {
            tab(.chat, title: "对话", icon: "bubble.left.and.bubble.right.fill")
            tab(.history, title: "历史", icon: "clock")
            tab(.settings, title: "设置", icon: "gearshape")
        }
        .padding(4)
        .frame(height: 56)
        .glassSurface(.capsule, interactive: true)
        .onAppear { visualTab = app.router.tab }
        .onChange(of: app.router.tab) { _, tab in visualTab = tab }
    }

    private func tab(_ tab: AppRouter.Tab, title: String, icon: String) -> some View {
        let selected = visualTab == tab
        return Button {
            Haptics.thud()
            if tab == .chat {
                withAnimation(Motion.pop) { visualTab = .chat }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    withAnimation(Motion.pop) {
                        app.router.tab = .chat
                        app.router.tabBarExpanded = false
                    }
                }
            } else {
                withAnimation(Motion.pop) {
                    visualTab = tab
                    app.router.tab = tab
                }
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .dsFont(16, weight: .medium)
                Text(title)
                    .dsFont(10, weight: .medium)
            }
            .foregroundStyle(selected ? Theme.accent : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(Theme.accent.opacity(0.14))
                        .matchedGeometryEffect(id: "global-tab-indicator", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
