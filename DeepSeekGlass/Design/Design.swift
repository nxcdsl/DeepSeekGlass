import SwiftUI
import UIKit

// MARK: - Palette

enum Theme {
    static let accent = Color(red: 0.302, green: 0.420, blue: 0.996)
    static let accentSoft = Color(red: 0.44, green: 0.55, blue: 1.0)
    static let accentDeep = Color(red: 0.16, green: 0.26, blue: 0.92)

    static let pagePadding: CGFloat = 16
    static let headerHeight: CGFloat = 44
    static let composerRadius: CGFloat = 26
    static let cardRadius: CGFloat = 22
    static let bubbleRadius: CGFloat = 20

    static var background: Color { Color(uiColor: .systemBackground) }
    static var secondaryBackground: Color { Color(uiColor: .secondarySystemBackground) }
    static var tertiaryBackground: Color { Color(uiColor: .tertiarySystemBackground) }
    static var groupedBackground: Color { Color(uiColor: .systemGroupedBackground) }
    static var separator: Color { Color(uiColor: .separator) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    static var dsUserBubble: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1)
                : UIColor(red: 0.89, green: 0.92, blue: 1.0, alpha: 1)
        })
    }

    static var dsAssistantText: Color { .primary }
}

// MARK: - Type scale

private struct FontScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var dsFontScale: Double {
        get { self[FontScaleKey.self] }
        set { self[FontScaleKey.self] = newValue }
    }
}

struct DSFontModifier: ViewModifier {
    @Environment(\.dsFontScale) private var scale
    var size: CGFloat
    var weight: Font.Weight
    var design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * CGFloat(scale), weight: weight, design: design))
    }
}

extension View {
    func dsFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(DSFontModifier(size: size, weight: weight, design: design))
    }
}

// MARK: - Glass

extension View {
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if let tint {
            if interactive {
                glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else {
                glassEffect(.regular.tint(tint), in: shape)
            }
        } else {
            if interactive {
                glassEffect(.regular.interactive(), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        }
    }
}

struct GlassPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct GlassIconButton: View {
    var systemName: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 17
    var tint: Color = .primary
    var accessibility: String?
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .dsFont(iconSize, weight: .semibold)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle())
        .glassSurface(.circle, interactive: true)
        .accessibilityLabel(accessibility ?? systemName)
    }
}

/// The two-line menu glyph used by the native app.
struct MenuGlyph: View {
    var color: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(color).frame(width: 18, height: 1.8)
            Capsule().fill(color).frame(width: 18, height: 1.8)
        }
    }
}

struct GlassPill: View {
    var title: String
    var icon: String
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .dsFont(12, weight: .semibold)
                Text(title)
                    .dsFont(13, weight: .medium)
            }
            .foregroundStyle(isOn ? Theme.accent : Color.secondary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background {
                Capsule(style: .continuous)
                    .fill(isOn ? Theme.accent.opacity(0.14) : Color.primary.opacity(0.055))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isOn ? Theme.accent.opacity(0.22) : Color.primary.opacity(0.06), lineWidth: 0.8)
            }
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.96))
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Background

struct AppBackdrop: View {
    var ambient: Bool = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Theme.background

            if ambient {
                GeometryReader { proxy in
                    let size = proxy.size
                    ZStack {
                        RadialGradient(
                            colors: [Theme.accent.opacity(scheme == .dark ? 0.20 : 0.13), .clear],
                            center: .topTrailing,
                            startRadius: 4,
                            endRadius: size.width * 0.95
                        )
                        .frame(width: size.width, height: size.width)
                        .offset(x: size.width * 0.22, y: -size.width * 0.35)
                        .blur(radius: 30)

                        RadialGradient(
                            colors: [Color(hex: 0x22D3EE).opacity(scheme == .dark ? 0.10 : 0.07), .clear],
                            center: .bottomLeading,
                            startRadius: 4,
                            endRadius: size.width * 0.8
                        )
                        .frame(width: size.width, height: size.width)
                        .offset(x: -size.width * 0.3, y: size.height * 0.5)
                        .blur(radius: 40)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

/// A soft material fade under the floating header so text stays legible without a hard bar.
struct TopFade: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(
            colors: [
                Theme.background,
                Theme.background.opacity(scheme == .dark ? 0.86 : 0.82),
                Theme.background.opacity(0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 132)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Whale

struct WhaleLogo: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            // Tail
            WhaleTail()
                .fill(LinearGradient(colors: [Theme.accentSoft, Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.34, height: size * 0.32)
                .offset(x: size * 0.30, y: -size * 0.10)

            // Dorsal fin
            WhaleFin()
                .fill(LinearGradient(colors: [Theme.accentSoft, Theme.accent], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.22, height: size * 0.20)
                .offset(x: size * 0.02, y: -size * 0.21)

            // Body
            Ellipse()
                .fill(LinearGradient(colors: [Theme.accentSoft, Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.82, height: size * 0.55)
                .offset(x: -size * 0.02, y: size * 0.03)

            // Belly
            Ellipse()
                .fill(Color.white.opacity(0.94))
                .frame(width: size * 0.54, height: size * 0.24)
                .offset(x: -size * 0.10, y: size * 0.14)

            // Eye
            Circle()
                .fill(Color.white)
                .frame(width: size * 0.075, height: size * 0.075)
                .offset(x: -size * 0.22, y: -size * 0.02)
            Circle()
                .fill(Color(hex: 0x0B1B4D))
                .frame(width: size * 0.036, height: size * 0.036)
                .offset(x: -size * 0.23, y: -size * 0.02)

            // Spout
            Circle()
                .fill(Color.white.opacity(0.75))
                .frame(width: size * 0.035, height: size * 0.035)
                .offset(x: -size * 0.05, y: -size * 0.30)
            Circle()
                .fill(Color.white.opacity(0.5))
                .frame(width: size * 0.025, height: size * 0.025)
                .offset(x: -size * 0.13, y: -size * 0.33)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct WhaleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.10),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.20)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.15)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.midY),
            control: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct WhaleFin: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.15)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.midY)
        )
        path.closeSubpath()
        return path
    }
}
