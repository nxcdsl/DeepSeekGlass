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
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var panel: some View {
        ZStack(alignment: .bottom) {
            FluidVoiceGlow(level: voice.level)
                .frame(height: 190)
                .allowsHitTesting(false)

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

private struct FluidVoiceGlow: View {
    var level: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let energy = Double(level)

            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    SIMD2<Float>(0, 0),
                    SIMD2<Float>(Float(0.50 + 0.10 * sin(time * 0.8)), 0),
                    SIMD2<Float>(1, 0),
                    SIMD2<Float>(0, Float(0.42 + 0.06 * cos(time * 0.7))),
                    SIMD2<Float>(
                        Float(0.50 + 0.22 * sin(time * 1.15 + 1.2)),
                        Float(0.46 + 0.14 * cos(time * 1.05))
                    ),
                    SIMD2<Float>(1, Float(0.42 + 0.06 * sin(time * 0.9))),
                    SIMD2<Float>(0, 1),
                    SIMD2<Float>(Float(0.50 + 0.08 * cos(time * 1.1)), 1),
                    SIMD2<Float>(1, 1)
                ],
                colors: [
                    Color(hex: 0x2F63FF).opacity(0.18 + energy * 0.18),
                    Color(hex: 0x22D3EE).opacity(0.10 + energy * 0.20),
                    Color(hex: 0x2F63FF).opacity(0.16 + energy * 0.16),
                    Color(hex: 0x1C3FC8).opacity(0.30 + energy * 0.22),
                    Color(hex: 0x7FA6FF).opacity(0.34 + energy * 0.32),
                    Color(hex: 0x2F63FF).opacity(0.26 + energy * 0.22),
                    Color(hex: 0x0C1B4D).opacity(0.55),
                    Color(hex: 0x1C3FC8).opacity(0.32 + energy * 0.20),
                    Color(hex: 0x0C1B4D).opacity(0.60)
                ]
            )
            .blur(radius: 26)
            .opacity(0.9)
            .blendMode(.plusLighter)
        }
        .mask {
            LinearGradient(
                colors: [.clear, .black.opacity(0.5), .black],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
