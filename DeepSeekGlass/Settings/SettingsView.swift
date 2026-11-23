import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app

    @State private var keyDraft = ""
    @State private var verifying = false
    @State private var verifyMessage: String?
    @State private var verifyOK = false
    @State private var showAdvanced = false
    @State private var showPrompt = false
    @State private var confirmClear = false
    @State private var showLogShare = false
    @State private var logMessage: String?

    var body: some View {
        @Bindable var settings = app.settings

        ZStack {
            Theme.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    apiSection(settings: settings)
                    personaSection(settings: settings)
                    advancedSection(settings: settings)
                    conversationSection(settings: settings)
                    usageSection
                    appearanceSection(settings: settings)
                    dataSection
                    debugSection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 92)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear { keyDraft = settings.apiKey }
        .sheet(isPresented: $showLogShare) {
            ShareSheet(items: [APIDebugLogger.logURL])
        }
        .alert("API 日志", isPresented: Binding(
            get: { logMessage != nil },
            set: { if !$0 { logMessage = nil } }
        )) {
            Button("好", role: .cancel) { logMessage = nil }
        } message: {
            Text(logMessage ?? "")
        }
        .confirmationDialog("清空所有对话？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("全部删除", role: .destructive) {
                app.store.deleteAll()
                Haptics.warning()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本机保存的对话和附件都会被删除，不能恢复。")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("设置")
                .dsFont(30, weight: .bold)
            Text("只接你自己的 DeepSeek API")
                .dsFont(12)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }

    // MARK: API

    private func apiSection(settings: AppSettings) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("API 接入")

            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                            .dsFont(12)
                            .foregroundStyle(Theme.accent)
                        Text("DeepSeek API Key")
                            .dsFont(14, weight: .medium)
                        Spacer()
                        Text(settings.hasAPIKey ? "已保存" : "未填写")
                            .dsFont(11)
                            .foregroundStyle(settings.hasAPIKey ? Color.green : Color.orange)
                    }

                    SecureField("sk-…", text: $keyDraft)
                        .dsFont(15)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(spacing: 10) {
                        Button {
                            let key = APIKeyInput.clean(keyDraft)
                            if let problem = APIKeyInput.problem(for: key, baseURL: settings.baseURL) {
                                verifyMessage = problem
                                verifyOK = false
                                Haptics.warning()
                                return
                            }
                            keyDraft = key
                            settings.saveAPIKey(key)
                            verifyMessage = "已保存在本机钥匙串"
                            verifyOK = true
                            Haptics.success()
                        } label: {
                            Text("保存")
                                .dsFont(13, weight: .semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .frame(height: 34)
                                .background(Theme.accent, in: Capsule())
                        }
                        .buttonStyle(GlassPressStyle())

                        Button {
                            verify(settings: settings)
                        } label: {
                            HStack(spacing: 5) {
                                if verifying { ProgressView().controlSize(.mini) }
                                Text(verifying ? "验证中" : "验证连接")
                                    .dsFont(13, weight: .medium)
                            }
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 15)
                            .frame(height: 34)
                            .background(Theme.accent.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(GlassPressStyle())
                        .disabled(verifying)

                        Spacer()
                    }

                    if let verifyMessage {
                        Text(verifyMessage)
                            .dsFont(11)
                            .foregroundStyle(verifyOK ? Color.green : Color.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Key 只保存在本机钥匙串，不会上传到别处。到 platform.deepseek.com 创建。")
                        .dsFont(10)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            }

            SettingsCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("模型")
                            .dsFont(15)
                        Spacer()
                        Menu {
                            ForEach(settings.modelOptions) { option in
                                Button {
                                    settings.model = option.id
                                } label: {
                                    if settings.model == option.id {
                                        Label(option.name, systemImage: "checkmark")
                                    } else {
                                        Text(option.name)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(settings.modelDisplayName)
                                    .dsFont(14)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .dsFont(9, weight: .semibold)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)

                    SettingsDivider()

                    DisclosureGroup(isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("API 地址")
                                .dsFont(11)
                                .foregroundStyle(.tertiary)
                            TextField("https://api.deepseek.com", text: Binding(
                                get: { settings.baseURL },
                                set: { settings.baseURL = $0 }
                            ))
                            .dsFont(13)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 10)
                            .frame(height: 38)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text("一般不用改。走代理或中转时再填。")
                                .dsFont(10)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                    } label: {
                        Text("高级")
                            .dsFont(13)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func verify(settings: AppSettings) {
        let key = APIKeyInput.clean(keyDraft)
        if let problem = APIKeyInput.problem(for: key, baseURL: settings.baseURL) {
            verifyMessage = problem
            verifyOK = false
            Haptics.warning()
            return
        }
        keyDraft = key
        settings.saveAPIKey(key)
        verifying = true
        verifyMessage = nil
        Task {
            do {
                let client = DeepSeekClient(baseURL: settings.baseURL, apiKey: key)
                try await client.validate()
                await MainActor.run {
                    verifying = false
                    verifyOK = true
                    verifyMessage = "连接正常，可以开始对话了"
                    Haptics.success()
                }
            } catch {
                await MainActor.run {
                    verifying = false
                    verifyOK = false
                    if let api = error as? APIError {
                        verifyMessage = api.friendly
                    } else {
                        verifyMessage = "连接失败：\(error.localizedDescription)"
                    }
                    Haptics.warning()
                }
            }
        }
    }

    // MARK: Persona

    private func personaSection(settings: AppSettings) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("对话风格")

            VStack(spacing: 8) {
                ForEach(PersonaPreset.allCases) { preset in
                    Button {
                        Haptics.selection()
                        withAnimation(.snappy(duration: 0.2)) {
                            settings.persona = preset
                        }
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: preset.icon)
                                .dsFont(15, weight: .medium)
                                .foregroundStyle(settings.persona == preset ? Theme.accent : .secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title)
                                    .dsFont(15, weight: .medium)
                                    .foregroundStyle(.primary)
                                Text(preset.subtitle)
                                    .dsFont(11)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: settings.persona == preset ? "checkmark.circle.fill" : "circle")
                                .dsFont(16)
                                .foregroundStyle(settings.persona == preset ? Theme.accent : Color.primary.opacity(0.12))
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 60)
                        .background {
                            if settings.persona == preset {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Theme.accent.opacity(0.09))
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )

            if settings.persona == .custom {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("自定义前置提示词")
                                .dsFont(13, weight: .medium)
                            Spacer()
                            Text("\(settings.customPrompt.count) 字")
                                .dsFont(10)
                                .foregroundStyle(.tertiary)
                        }
                        TextEditor(text: Binding(
                            get: { settings.customPrompt },
                            set: { settings.customPrompt = $0 }
                        ))
                        .dsFont(13)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 150)
                        .padding(8)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text("会作为 system 消息放在每轮请求最前面。留空则不注入。")
                            .dsFont(10)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                }
            }

            SettingsCard {
                DisclosureGroup(isExpanded: $showPrompt) {
                    Text(settings.effectiveSystemPrompt.isEmpty ? "当前没有注入提示词。" : settings.effectiveSystemPrompt)
                        .dsFont(11)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .padding(.top, 6)
                        .padding(.bottom, 10)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.plaintext")
                            .dsFont(12)
                            .foregroundStyle(Theme.accent)
                        Text("查看当前生效的提示词")
                            .dsFont(13)
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: Conversation

    private func conversationSection(settings: AppSettings) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("对话")

            SettingsCard {
                VStack(spacing: 0) {
                    toggleRow("默认深度思考", icon: "brain", isOn: Binding(
                        get: { settings.deepThinking },
                        set: { settings.deepThinking = $0 }
                    ))
                    SettingsDivider()
                    toggleRow("默认智能搜索", icon: "globe", isOn: Binding(
                        get: { settings.webSearch },
                        set: { settings.webSearch = $0 }
                    ))
                    SettingsDivider()
                    toggleRow("回答后自动朗读", icon: "speaker.wave.2", isOn: Binding(
                        get: { settings.autoReadAloud },
                        set: { settings.autoReadAloud = $0 }
                    ))
                    SettingsDivider()
                    toggleRow("展开思考过程", icon: "list.bullet.rectangle", isOn: Binding(
                        get: { settings.showReasoningByDefault },
                        set: { settings.showReasoningByDefault = $0 }
                    ))
                    SettingsDivider()

                    HStack {
                        Label {
                            Text("推理强度")
                                .dsFont(15)
                        } icon: {
                            Image(systemName: "gauge.with.dots.needle.67percent")
                                .dsFont(14)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 22)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.effort },
                            set: { settings.effort = $0 }
                        )) {
                            ForEach(ThinkingEffort.allCases) { effort in
                                Text(effort.title).tag(effort)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)

                    SettingsDivider()

                    HStack {
                        Label {
                            Text("消耗等级")
                                .dsFont(15)
                        } icon: {
                            Image(systemName: "leaf")
                                .dsFont(14)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 22)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.consumption },
                            set: { settings.consumption = $0 }
                        )) {
                            ForEach(ConsumptionLevel.allCases) { level in
                                Text(level.title).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)

                    SettingsDivider()

                    toggleRow("压缩旧对话", icon: "arrow.triangle.2.circlepath", isOn: Binding(
                        get: { settings.contextCompression },
                        set: { settings.contextCompression = $0 }
                    ))
                }
            }

            Text(settings.consumption.subtitle)
                .dsFont(10)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
            if settings.contextCompression {
                Text("较早的消息会压成一段本地记忆摘要随请求发送，保留近 \(settings.consumption.compressionWindow) 条原文。")
                    .dsFont(10)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
            }
        }
    }

    // MARK: Advanced API parameters

    private func advancedSection(settings: AppSettings) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("API 参数")

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: Binding(
                        get: { settings.temperatureOverrideEnabled },
                        set: { settings.temperatureOverrideEnabled = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自定义 temperature")
                                .dsFont(14)
                            Text("关闭时跟随所选风格（原生 0.6 / 陪伴 0.8）")
                                .dsFont(10)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(Theme.accent)

                    if settings.temperatureOverrideEnabled {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("temperature")
                                    .dsFont(12)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.2f", settings.temperature))
                                    .dsFont(12)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: Binding(
                                get: { settings.temperature },
                                set: { settings.temperature = $0 }
                            ), in: 0...2, step: 0.05)
                            .tint(Theme.accent)
                        }
                    }

                    Divider().opacity(0.4)

                    HStack {
                        Text("max_tokens")
                            .dsFont(14)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.maxTokens },
                            set: { settings.maxTokens = $0 }
                        )) {
                            ForEach([2048, 4096, 8192, 16384, 32768], id: \.self) { value in
                                Text("\(value)").tag(value)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                    }

                    HStack {
                        Text("top_p")
                            .dsFont(14)
                        Spacer()
                        Text(String(format: "%.2f", settings.topP))
                            .dsFont(12)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { settings.topP },
                        set: { settings.topP = $0 }
                    ), in: 0.9...1.0, step: 0.01)
                    .tint(Theme.accent)

                    Toggle("生成对话标题", isOn: Binding(
                        get: { settings.generatesTitle },
                        set: { settings.generatesTitle = $0 }
                    ))
                    .dsFont(14)
                    .tint(Theme.accent)

                    Text("思考模式下 temperature / top_p 可能被服务端忽略；title 会额外产生一次服务端调用。")
                        .dsFont(10)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
            }
        }
    }

    // MARK: Usage

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("API 用量")

            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(formatTokens(app.usage.totalTokens))
                            .dsFont(28, weight: .bold)
                            .monospacedDigit()
                        Text("tokens")
                            .dsFont(11)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("今日 \(formatTokens(app.usage.todayTokens))")
                            .dsFont(11)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 18) {
                        usageMetric("输入", value: app.usage.inputTokens)
                        usageMetric("输出", value: app.usage.outputTokens)
                        Spacer()
                    }

                    GeometryReader { geometry in
                        let total = max(1, app.usage.totalTokens)
                        let ratio = CGFloat(app.usage.inputTokens) / CGFloat(total)
                        HStack(spacing: 2) {
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: max(2, geometry.size.width * ratio))
                            Capsule()
                                .fill(Color.primary.opacity(0.10))
                        }
                    }
                    .frame(height: 5)

                    HStack(spacing: 8) {
                        Text("按 deepseek-flash 峰值价估算 ≈ $\(formatCost(app.usage.estimatedCost))")
                            .dsFont(10)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button("重置") {
                            app.usage.reset()
                        }
                        .dsFont(10)
                        .foregroundStyle(.tertiary)
                        .buttonStyle(.plain)
                    }

                    Text("只统计这台设备上的对话，不是平台账单。")
                        .dsFont(10)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
            }
        }
    }

    private func usageMetric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .dsFont(10)
                .foregroundStyle(.tertiary)
            Text(formatTokens(value))
                .dsFont(14, weight: .medium)
                .monospacedDigit()
        }
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func formatCost(_ value: Double) -> String {
        if value >= 1 { return String(format: "%.2f", value) }
        return String(format: "%.3f", value)
    }

    // MARK: Appearance

    private func appearanceSection(settings: AppSettings) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("外观")

            SettingsCard {
                VStack(spacing: 0) {
                    HStack {
                        Label {
                            Text("外观")
                                .dsFont(15)
                        } icon: {
                            Image(systemName: "moon.stars")
                                .dsFont(14)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 22)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.appearance },
                            set: { settings.appearance = $0 }
                        )) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)

                    SettingsDivider()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AppThemePreset.allCases) { theme in
                                Button {
                                    Haptics.selection()
                                    withAnimation(Motion.pop) {
                                        settings.theme = theme
                                    }
                                } label: {
                                    VStack(spacing: 5) {
                                        Circle()
                                            .fill(theme.accent)
                                            .frame(width: 26, height: 26)
                                            .overlay {
                                                Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.7)
                                            }
                                        Text(theme.title)
                                            .dsFont(10, weight: .medium)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(settings.theme == theme ? theme.accent.opacity(0.10) : Color.clear)
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(settings.theme == theme ? theme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
                                    }
                                }
                                .buttonStyle(GlassPressStyle(pressedScale: 0.95))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }

                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label {
                                Text("字体大小")
                                    .dsFont(15)
                            } icon: {
                                Image(systemName: "textformat.size")
                                    .dsFont(14)
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 22)
                            }
                            Spacer()
                            Text("\(Int(settings.fontScale * 100))%")
                                .dsFont(12)
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { settings.fontScale },
                            set: { settings.fontScale = $0 }
                        ), in: 0.88...1.18, step: 0.02)
                        .tint(Theme.accent)
                        Text("这是预览文字，聊天正文会跟着变。")
                            .dsFont(14)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                }
            }
        }
    }

    // MARK: Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("数据")

            SettingsCard {
                VStack(spacing: 0) {
                    HStack {
                        Label {
                            Text("本机对话")
                                .dsFont(15)
                        } icon: {
                            Image(systemName: "internaldrive")
                                .dsFont(14)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 22)
                        }
                        Spacer()
                        Text("\(app.store.conversations.count) 段")
                            .dsFont(13)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)

                    SettingsDivider()

                    Button {
                        confirmClear = true
                    } label: {
                        HStack {
                            Label {
                                Text("清空所有对话")
                                    .dsFont(15)
                            } icon: {
                                Image(systemName: "trash")
                                    .dsFont(14)
                                    .foregroundStyle(.red)
                                    .frame(width: 22)
                            }
                            Spacer()
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Debug

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("调试")

            SettingsCard {
                VStack(spacing: 0) {
                    Button {
                        if APIDebugLogger.hasLog {
                            showLogShare = true
                        } else {
                            logMessage = "还没有日志。先发几条消息，再回来导出。"
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .dsFont(14)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 22)
                            Text("导出 API 日志")
                                .dsFont(15)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(logFileSize)
                                .dsFont(11)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button {
                        Task {
                            await APIDebugLogger.shared.clear()
                            logMessage = "日志已清空。"
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "trash")
                                .dsFont(14)
                                .foregroundStyle(.red)
                                .frame(width: 22)
                            Text("清空 API 日志")
                                .dsFont(15)
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("每次请求会记录完整 Request Body 和 usage，保留最近 5 次；文件在 Documents 里，可能较大。")
                .dsFont(10)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
        }
    }

    private var logFileSize: String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: APIDebugLogger.logURL.path),
              let size = attributes[.size] as? Int, size > 0 else {
            return "无"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    // MARK: About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("关于")

            SettingsCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("版本")
                            .dsFont(15)
                        Spacer()
                        Text("1.0 (1)")
                            .dsFont(13)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)

                    SettingsDivider()

                    Link(destination: URL(string: "https://api-docs.deepseek.com/")!) {
                        HStack {
                            Text("DeepSeek API 文档")
                                .dsFont(15)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .dsFont(11, weight: .semibold)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("第三方客户端，与深度求索无隶属关系。对话由 DeepSeek API 生成，请自行判断内容。")
                .dsFont(10)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Bits

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .dsFont(12, weight: .medium)
            .foregroundStyle(.tertiary)
            .padding(.leading, 6)
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Label {
                Text(title)
                    .dsFont(15)
            } icon: {
                Image(systemName: icon)
                    .dsFont(14)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.accent)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
    }
}

struct SettingsCard<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 0.6)
            .padding(.leading, 14)
    }
}
