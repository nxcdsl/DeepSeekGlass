import SwiftUI

struct ThinkingSection: View {
    var message: ChatMessage
    var streaming: Bool

    @Environment(AppState.self) private var app
    @State private var expanded = false
    @State private var initialized = false

    private var isThinkingNow: Bool {
        streaming && message.blocks.contains { $0.kind == .thinking && !$0.isComplete }
    }

    private var headerText: String {
        if isThinkingNow { return "正在思考" }
        if let seconds = message.thinkingSeconds { return "已思考（用时 \(seconds) 秒）" }
        return "思考过程"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.24)) { expanded.toggle() }
                Haptics.selection()
            } label: {
                HStack(spacing: 5) {
                    if isThinkingNow {
                        ThinkingPulse()
                    }
                    Text(headerText)
                        .dsFont(14, weight: .medium)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .dsFont(10, weight: .semibold)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(headerText)

            if expanded {
                timeline
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            expanded = streaming || app.settings.showReasoningByDefault
        }
        .onChange(of: streaming) { _, nowStreaming in
            if !nowStreaming {
                withAnimation(.snappy(duration: 0.24)) { expanded = false }
            }
        }
    }

    private var timeline: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.primary.opacity(0.075))
                .frame(width: 1)
                .padding(.leading, 6)
                .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 13) {
                ForEach(message.blocks) { block in
                    row(for: block)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for block: ContentBlock) -> some View {
        switch block.kind {
        case .thinking:
            if !block.text.isEmpty {
                HStack(alignment: .top, spacing: 11) {
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 5, height: 5)
                        .offset(x: 1.5, y: 8)
                        .frame(width: 13)
                    Text(block.text)
                        .dsFont(15)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        case .toolUse:
            toolRow(block)

        case .searchResults:
            EmptyView()

        case .fetchResult:
            if !hasToolUse(block.toolID) {
                fetchRow(url: block.url, title: block.fetchTitle, error: block.fetchError, toolID: block.toolID)
            }

        case .text:
            EmptyView()
        }
    }

    private func hasToolUse(_ id: String?) -> Bool {
        guard let id else { return false }
        return message.blocks.contains { $0.kind == .toolUse && $0.toolID == id }
    }

    private func searchResults(for toolID: String?) -> [SearchResult] {
        guard let toolID else { return [] }
        return message.blocks.first { $0.kind == .searchResults && $0.toolID == toolID }?.results ?? []
    }

    @ViewBuilder
    private func toolRow(_ block: ContentBlock) -> some View {
        let action = block.action ?? ""
        switch action {
        case "search":
            let results = searchResults(for: block.toolID)
            iconRow(
                icon: "magnifyingglass",
                title: results.isEmpty ? "正在搜索…" : "已搜索到 \(results.count) 个网页",
                detail: block.queries.joined(separator: " · ")
            ) {
                if !results.isEmpty {
                    HStack(spacing: -6) {
                        ForEach(Array(results.prefix(5).enumerated()), id: \.offset) { _, result in
                            SiteIcon(urlString: result.siteIcon, size: 18)
                        }
                    }
                    .padding(.top, 2)
                }
            }

        case "open_page":
            iconRow(
                icon: "doc.text.magnifyingglass",
                title: "正在浏览网页",
                detail: host(block.url)
            ) { EmptyView() }

        case "find_in_page":
            iconRow(
                icon: "text.magnifyingglass",
                title: "查找关键词",
                detail: block.pattern.map { "“\($0)”" } ?? host(block.url)
            ) { EmptyView() }

        case "read_link":
            iconRow(
                icon: "link",
                title: "阅读链接",
                detail: host(block.url)
            ) { EmptyView() }

        default:
            iconRow(
                icon: "wrench.and.screwdriver",
                title: block.toolName ?? "调用工具",
                detail: nil
            ) { EmptyView() }
        }
    }

    private func fetchRow(url: String?, title: String?, error: String?, toolID: String?) -> some View {
        let results = message.blocks.first { $0.kind == .searchResults && $0.toolID == toolID }?.results ?? []
        return iconRow(
            icon: "doc.text",
            title: error == nil ? "已浏览 1 个页面" : "页面打不开",
            detail: title ?? host(url)
        ) {
            if !results.isEmpty {
                HStack(spacing: -6) {
                    ForEach(Array(results.prefix(3).enumerated()), id: \.offset) { _, result in
                        SiteIcon(urlString: result.siteIcon, size: 18)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func iconRow<Accessory: View>(
        icon: String,
        title: String,
        detail: String?,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .dsFont(12, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: 13, height: 15)
                .offset(y: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .dsFont(14)
                    .foregroundStyle(.secondary)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .dsFont(11)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
                accessory()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func host(_ urlString: String?) -> String? {
        guard let urlString, let host = URL(string: urlString)?.host else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }
}

struct ThinkingPulse: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 6, height: 6)
            .opacity(on ? 1 : 0.35)
            .scaleEffect(on ? 1 : 0.8)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
