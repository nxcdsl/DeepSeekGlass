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
    let engine: ChatEngine

    init() {
        let settings = AppSettings()
        let store = ConversationStore()
        let speech = SpeechController()
        let voice = VoiceController(settings: settings)
        self.settings = settings
        self.store = store
        self.speech = speech
        self.voice = voice
        self.router = AppRouter()
        self.engine = ChatEngine(store: store, settings: settings, speech: speech, voice: voice)
    }
}

@main
struct DeepSeekGlassApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
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
    }
}
