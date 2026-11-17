import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ComposerView: View {
    var engine: ChatEngine
    var focused: FocusState<Bool>.Binding
    var onPlus: () -> Void

    @Environment(AppState.self) private var app
    @State private var pressingMic = false
    @State private var micStartedAt: Date?
    @State private var willCancel = false
    @State private var holdingBar = false
    @State private var voiceFromBar = false
    @State private var holdTask: Task<Void, Never>?

    private var canSend: Bool {
        !engine.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !engine.pending.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !engine.pending.isEmpty {
                pendingStrip
            }

            ZStack(alignment: .topLeading) {
                TextField(
                    "",
                    text: Binding(
                        get: { engine.draft },
                        set: { engine.draft = $0 }
                    ),
                    axis: .vertical
                )
                .focused(focused)
                .lineLimit(1...6)
                .dsFont(17)
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .onSubmit { engine.send() }
                .padding(.vertical, 1)

                if engine.draft.isEmpty {
                    Text("发消息或按住说话")
                        .dsFont(17)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .padding(.top, 1)
                }
            }
            .frame(minHeight: 25)
            .overlay {
                if engine.draft.isEmpty, !focused.wrappedValue {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(holdGesture)
                }
            }

            HStack(spacing: 7) {
                GlassPill(title: "深度思考", icon: "brain", isOn: engine.deepThinking) {
                    engine.deepThinking.toggle()
                }
                GlassPill(title: "智能搜索", icon: "globe", isOn: engine.webSearch) {
                    engine.webSearch.toggle()
                }

                Spacer(minLength: 6)

                Button {
                    Haptics.tap()
                    onPlus()
                } label: {
                    Image(systemName: "plus")
                        .dsFont(17, weight: .regular)
                        .foregroundStyle(Color.primary.opacity(0.82))
                        .frame(width: 34, height: 34)
                        .background {
                            Circle().strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(GlassPressStyle())

                trailingButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 12)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(holdGesture)
        }
        .glassSurface(.rect(cornerRadius: 28))
    }

    @ViewBuilder
    private var trailingButton: some View {
        if engine.isStreaming {
            Button {
                Haptics.tap()
                engine.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .dsFont(14, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.accent))
                    .contentShape(Circle())
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("停止生成")
        } else if canSend {
            Button {
                Haptics.tap()
                engine.send()
            } label: {
                Image(systemName: "arrow.up")
                    .dsFont(16, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.accent))
                    .contentShape(Circle())
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("发送")
        } else {
            micButton
        }
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !holdingBar {
                    holdingBar = true
                    voiceFromBar = false
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 260_000_000)
                        guard !Task.isCancelled else { return }
                        voiceFromBar = true
                        focused.wrappedValue = false
                        Haptics.tap()
                        engine.beginVoice()
                    }
                }
                if voiceFromBar {
                    willCancel = value.translation.height < -60
                    app.voice.setWillCancel(willCancel)
                }
            }
            .onEnded { value in
                holdTask?.cancel()
                holdTask = nil
                if voiceFromBar {
                    engine.endVoice(cancelled: value.translation.height < -60)
                } else {
                    focused.wrappedValue = true
                }
                holdingBar = false
                voiceFromBar = false
                willCancel = false
            }
    }

    private var micButton: some View {
        Image(systemName: "waveform")
            .dsFont(16, weight: .medium)
            .foregroundStyle(app.voice.phase == .recording ? Theme.accent : Color.primary.opacity(0.82))
            .frame(width: 34, height: 34)
            .background {
                Circle().strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
            }
            .contentShape(Circle())
            .scaleEffect(pressingMic ? 1.08 : 1)
            .animation(.snappy(duration: 0.18), value: pressingMic)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !pressingMic {
                            pressingMic = true
                            micStartedAt = .now
                            Haptics.tap()
                            engine.beginVoice()
                        }
                        willCancel = value.translation.height < -70
                        app.voice.setWillCancel(willCancel)
                    }
                    .onEnded { value in
                        let tooShort = micStartedAt.map { Date().timeIntervalSince($0) < 0.22 } ?? false
                        let cancel = value.translation.height < -70 || tooShort
                        pressingMic = false
                        willCancel = false
                        micStartedAt = nil
                        engine.endVoice(cancelled: cancel)
                    }
            )
            .accessibilityLabel("按住说话")
    }

    private var pendingStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(engine.pending) { item in
                    ZStack(alignment: .topTrailing) {
                        if item.kind == .image, let image = UIImage(data: item.data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            VStack(spacing: 3) {
                                Image(systemName: "doc.text")
                                    .dsFont(17, weight: .medium)
                                Text(item.filename)
                                    .dsFont(8)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.secondary)
                            .frame(width: 54, height: 54)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Button {
                            engine.removePending(item.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 17, height: 17)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                    }
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                }
            }
        }
        .frame(height: 66)
    }
}

// MARK: - Attachment tray

struct AttachmentTray: View {
    var onImage: (UIImage) -> Void
    var onFile: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var cameraUnavailable = false

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("添加附件")
                    .dsFont(17, weight: .semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .dsFont(12, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)

            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: 6,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    AttachmentTile(icon: "photo.on.rectangle", title: "相册", subtitle: "选几张图")
                }
                .buttonStyle(GlassPressStyle(pressedScale: 0.97))

                Button {
                    Haptics.tap()
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        cameraUnavailable = true
                    }
                } label: {
                    AttachmentTile(icon: "camera", title: "拍照", subtitle: "拍一张")
                }
                .buttonStyle(GlassPressStyle(pressedScale: 0.97))

                Button {
                    Haptics.tap()
                    showFiles = true
                } label: {
                    AttachmentTile(icon: "doc", title: "文件", subtitle: "PDF / TXT")
                }
                .buttonStyle(GlassPressStyle(pressedScale: 0.97))
            }

            Text("图片会随消息一起发给模型；PDF 和文本只提取文字。")
                .dsFont(11)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        onImage(image)
                    }
                }
                photoItems = []
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                onImage(image)
                showCamera = false
                dismiss()
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFiles,
            allowedContentTypes: [.pdf, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                onFile(url)
                dismiss()
            }
        }
        .alert("这台设备没有相机", isPresented: $cameraUnavailable) {
            Button("好", role: .cancel) {}
        } message: {
            Text("可以用「相册」选一张照片。")
        }
    }
}

struct AttachmentTile: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .dsFont(20, weight: .medium)
                .foregroundStyle(Theme.accent)
                .frame(height: 24)
            Text(title)
                .dsFont(14, weight: .medium)
            Text(subtitle)
                .dsFont(10)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 98)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
