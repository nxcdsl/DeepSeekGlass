import SwiftUI

struct VoiceOverlay: View {
    @Environment(AppState.self) private var app

    private var voice: VoiceController { app.voice }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.30)
                    .ignoresSafeArea()

                panel
                    .frame(height: max(280, proxy.size.height * 0.38))
                    .frame(maxWidth: .infinity)
                    .mask {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.85), .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .background(alignment: .bottom) {
                        LinearGradient(
                            colors: [
                                Color(hex: 0x2F63FF).opacity(0),
                                Color(hex: 0x2F63FF).opacity(0.72),
                                Color(hex: 0x1C3FC8),
                                Color(hex: 0x0C1B4D)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .mask {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.7), .black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    }
                    .overlay(alignment: .bottom) {
                        VoiceRipple(level: voice.level)
                            .frame(height: 180)
                            .allowsHitTesting(false)
                    }
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var panel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                Circle()
                    .fill(.white.opacity(voice.phase == .recording ? 0.9 : 0.35))
                    .frame(width: 5, height: 5)
                Text(voice.phase == .transcribing ? "正在识别" : "正在录音")
                    .dsFont(12, weight: .medium)
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
                Text(timeString)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 26)
            .padding(.top, 26)

            Spacer(minLength: 0)

            if voice.phase == .transcribing {
                VStack(spacing: 14) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text("把刚才的话转成文字…")
                        .dsFont(14)
                        .foregroundStyle(.white.opacity(0.8))
                }
            } else {
                VStack(spacing: 10) {
                    Text(voice.willCancel ? "松开取消" : "松手发送，上滑取消")
                        .dsFont(17, weight: .semibold)
                        .foregroundStyle(voice.willCancel ? Color(hex: 0xFFB4B4) : .white.opacity(0.95))
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.15), value: voice.willCancel)

                    dottedWave
                        .frame(height: 28)
                }
            }

            Spacer(minLength: 0)

            Text(voice.willCancel ? "上滑已取消" : " ")
                .dsFont(11)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
    }

    private var dottedWave: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let level = max(0.08, Double(voice.level))
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<38, id: \.self) { index in
                    let phase = Double(index) * 0.55
                    let wave = 0.25 + 0.75 * abs(sin(phase + time * 4.2))
                    let height = 2 + 16 * wave * level
                    Capsule()
                        .fill(.white.opacity(0.72))
                        .frame(width: 2, height: height)
                }
            }
        }
    }

    private var timeString: String {
        let total = Int(voice.elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct VoiceRipple: View {
    var level: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height * 0.92)
                for index in 0..<4 {
                    let phase = (time * 0.32 + Double(index) * 0.25).truncatingRemainder(dividingBy: 1)
                    let radius = (0.12 + phase * 0.88) * size.width * 0.55
                    let alpha = (1 - phase) * 0.16 * (0.45 + Double(level))
                    let rect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius * 0.26,
                        width: radius * 2,
                        height: radius * 0.52
                    )
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(alpha)),
                        lineWidth: 0.8
                    )
                }
            }
        }
        .blendMode(.plusLighter)
    }
}
