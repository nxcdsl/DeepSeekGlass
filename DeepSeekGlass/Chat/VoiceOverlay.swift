import SwiftUI

struct VoiceOverlay: View {
    @Environment(AppState.self) private var app

    private var voice: VoiceController { app.voice }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x2F63FF), Color(hex: 0x16308F), Color(hex: 0x081433)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 340, height: 340)
                .blur(radius: 70)
                .offset(x: -150, y: -250)

            Circle()
                .fill(Color(hex: 0x22D3EE).opacity(0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: 170, y: 300)

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)

                Spacer(minLength: 30)

                center
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 40)

                bottomHint
                    .padding(.bottom, 34)
            }
            .padding(.horizontal, 28)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity.animation(.easeInOut(duration: 0.18)))
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
                .opacity(voice.phase == .recording ? 1 : 0.4)
            Text(voice.phase == .transcribing ? "正在识别" : "正在录音")
                .dsFont(13, weight: .medium)
                .foregroundStyle(.white.opacity(0.92))
            Spacer()
            Text(timeString)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 16)
    }

    private var center: some View {
        VStack(spacing: 26) {
            if voice.phase == .transcribing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.3)
                Text("把刚才的话转成文字…")
                    .dsFont(15)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                waveform
                    .frame(height: 76)
                Text(voice.willCancel ? "松开取消" : "松手发送")
                    .dsFont(21, weight: .semibold)
                    .foregroundStyle(voice.willCancel ? Color(hex: 0xFFB4B4) : .white)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.16), value: voice.willCancel)
                Text(voice.willCancel ? "上滑已取消发送" : "上滑可以取消")
                    .dsFont(12)
                    .foregroundStyle(.white.opacity(0.55))
                    .opacity(voice.willCancel ? 0 : 1)
            }
        }
    }

    private var waveform: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let level = max(0.06, Double(voice.level))
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<44, id: \.self) { index in
                    let phase = Double(index) * 0.52
                    let wave = 0.35 + 0.65 * abs(sin(phase + time * 4.4))
                    let envelope = 1.0 - abs(Double(index) - 21.5) / 28.0
                    let height = 7 + 56 * wave * level * max(0.25, envelope)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.95), .white.opacity(0.45)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3.2, height: height)
                }
            }
            .animation(.linear(duration: 0.08), value: level)
        }
    }

    private var bottomHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .dsFont(19, weight: .medium)
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .overlay { Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8) }

            if voice.phase == .recording {
                Text(voice.willCancel ? "松手取消" : "松手发送，上滑取消")
                    .dsFont(12)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }

    private var timeString: String {
        let total = Int(voice.elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
