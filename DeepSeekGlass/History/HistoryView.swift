import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var renameTarget: Conversation?
    @State private var renameText = ""
    @State private var deleteTarget: Conversation?

    private var groups: [(String, [Conversation])] {
        app.store.grouped(query)
    }

    private var total: Int { app.store.conversations.count }

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header
                    searchField

                    if groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            section(title: group.0, conversations: group.1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
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

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("历史")
                    .dsFont(30, weight: .bold)
                Text(total == 0 ? "所有对话都会留在这里" : "\(total) 段对话")
                    .dsFont(12)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                Haptics.tap()
                app.router.newChat(store: app.store)
            } label: {
                Image(systemName: "square.and.pencil")
                    .dsFont(17, weight: .medium)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(GlassPressStyle())
            .glassSurface(.circle, interactive: true)
            .accessibilityLabel("新对话")
        }
        .padding(.top, 4)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .dsFont(14, weight: .medium)
                .foregroundStyle(.tertiary)
            TextField("搜索标题或内容…", text: $query)
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
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.6)
        }
    }

    private func section(title: String, conversations: [Conversation]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .dsFont(12, weight: .medium)
                .foregroundStyle(.tertiary)
                .padding(.leading, 6)

            VStack(spacing: 0) {
                ForEach(Array(conversations.enumerated()), id: \.offset) { index, conversation in
                    row(conversation)
                    if index < conversations.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 0.6)
                            .padding(.leading, 14)
                    }
                }
            }
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
    }

    private func row(_ conversation: Conversation) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                Haptics.selection()
                app.router.openChat(conversation.id, store: app.store)
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            if conversation.isPinned {
                                Image(systemName: "pin.fill")
                                    .dsFont(9)
                                    .foregroundStyle(Theme.accent.opacity(0.8))
                            }
                            Text(conversation.title)
                                .dsFont(16, weight: .medium)
                                .lineLimit(1)
                        }
                        Text(conversation.preview)
                            .dsFont(12)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    Text(conversation.updatedAt.shortClock)
                        .dsFont(11)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
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
            } label: {
                Image(systemName: "ellipsis")
                    .dsFont(13, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: query.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass")
                .dsFont(30, weight: .light)
                .foregroundStyle(.tertiary)
                .padding(.top, 70)

            Text(query.isEmpty ? "还没有历史对话" : "没有找到相关对话")
                .dsFont(16, weight: .medium)
                .foregroundStyle(.secondary)

            if query.isEmpty {
                Button {
                    Haptics.tap()
                    app.router.newChat(store: app.store)
                } label: {
                    Text("聊两句")
                        .dsFont(14, weight: .semibold)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 20)
                        .frame(height: 38)
                        .background(Theme.accent.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
