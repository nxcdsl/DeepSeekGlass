import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var dragX: CGFloat = 0
    @State private var renameTarget: Conversation?
    @State private var renameText = ""
    @State private var deleteTarget: Conversation?

    private var groups: [(String, [Conversation])] {
        app.store.grouped(query)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width - 54, 382)

            ZStack(alignment: .leading) {
                Color.black
                    .opacity(0.40 * max(0, 1 - abs(dragX) / max(width, 1)))
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                panel(width: width, height: proxy.size.height)
                    .frame(width: width)
                    .offset(x: min(0, dragX))
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onChanged { value in
                                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                dragX = min(0, value.translation.width)
                            }
                            .onEnded { value in
                                let shouldClose = value.translation.width < -70
                                    || value.predictedEndTranslation.width < -120
                                if shouldClose {
                                    close()
                                } else {
                                    withAnimation(.snappy(duration: 0.26)) { dragX = 0 }
                                }
                            }
                    )
            }
            .ignoresSafeArea(edges: .vertical)
        }
        .transition(.move(edge: .leading).combined(with: .opacity))
        .alert("重命名对话", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("对话名称", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("保存") {
                if let target = renameTarget {
                    app.store.rename(target.id, to: renameText)
                }
                renameTarget = nil
            }
        }
        .confirmationDialog(
            "删除这段对话？",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let target = deleteTarget {
                    app.store.delete(target.id)
                }
                deleteTarget = nil
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("删除后不能恢复。")
        }
    }

    private func panel(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4, pinnedViews: []) {
                    if groups.isEmpty {
                        Text(query.isEmpty ? "还没有对话" : "没有找到相关对话")
                            .dsFont(13)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }

                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        Text(group.0)
                            .dsFont(12, weight: .medium)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 22)
                            .padding(.top, 14)
                            .padding(.bottom, 4)

                        ForEach(group.1) { conversation in
                            conversationRow(conversation)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .frame(maxHeight: .infinity)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [Color.black.opacity(0.16), Color.black.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 30,
                topTrailingRadius: 30,
                style: .continuous
            )
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 0.5)
                .ignoresSafeArea()
        }
        .shadow(color: .black.opacity(0.28), radius: 30, x: 12, y: 0)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("对话")
                .dsFont(24, weight: .bold)
            Spacer()
            Button {
                Haptics.tap()
                app.router.newChat(store: app.store)
            } label: {
                Image(systemName: "square.and.pencil")
                    .dsFont(15, weight: .medium)
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("新对话")

            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .dsFont(13, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .dsFont(14, weight: .medium)
                .foregroundStyle(.tertiary)
            TextField("搜索对话内容…", text: $query)
                .dsFont(15)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .dsFont(13)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.6)
        }
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        Button {
            Haptics.selection()
            app.router.openChat(conversation.id, store: app.store)
        } label: {
            HStack(spacing: 8) {
                if conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .dsFont(10)
                        .foregroundStyle(Theme.accent.opacity(0.8))
                }
                Text(conversation.title)
                    .dsFont(16)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if app.store.selectedID == conversation.id {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background {
                if app.store.selectedID == conversation.id {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Theme.accent.opacity(0.16))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .contextMenu {
            Button {
                app.store.togglePin(conversation.id)
            } label: {
                Label(conversation.isPinned ? "取消置顶" : "置顶", systemImage: conversation.isPinned ? "pin.slash" : "pin")
            }
            Button {
                renameTarget = conversation
                renameText = conversation.title
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteTarget = conversation
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.6)

            Button {
                Haptics.tap()
                app.router.drawerOpen = false
                app.router.tab = .settings
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .dsFont(16, weight: .medium)
                    Text("设置")
                        .dsFont(15)
                    Spacer()
                    Text("1.0")
                        .dsFont(12)
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .frame(height: 52)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.26)) {
            app.router.drawerOpen = false
        }
        dragX = 0
    }
}
