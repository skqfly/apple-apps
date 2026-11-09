import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Haptic Feedback

enum Haptics {
    static func light() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func medium() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func error() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}

// MARK: - Pure Liquid Glass Navigation Bar ButtonStyles (Referencing Minis Double-Icon Capsule)

/// Pure Liquid Glass capsule button (e.g. "选择", "取消", "全选").
/// High optical clarity, transparent refractive glass, soft rim highlight.
struct AppleNavCapsuleButtonStyle: ButtonStyle {
    var isSelected: Bool = false
    var isAccentText: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(isAccentText ? Color.appAccent : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background {
                if #available(iOS 26, *) {
                    Capsule()
                        .fill(isSelected ? Color.appAccent : Color.clear)
                        .glassEffect(.regular.interactive(), in: .capsule)
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(0.55))
                        .overlay {
                            Capsule().strokeBorder(
                                colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.55),
                                lineWidth: 0.75
                            )
                        }
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Pure Liquid Glass circular button (36x36pt).
/// High-transparency glass lens with delicate edge refraction.
struct AppleNavCircleButtonStyle: ButtonStyle {
    var size: CGFloat = 36
    var isAccent: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isAccent ? Color.appAccent : Color.primary)
            .frame(width: size, height: size)
            .background {
                if #available(iOS 26, *) {
                    Circle()
                        .glassEffect(.regular.interactive(), in: .circle)
                } else {
                    Circle()
                        .fill(.ultraThinMaterial.opacity(0.55))
                        .overlay {
                            Circle().strokeBorder(
                                colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.55),
                                lineWidth: 0.75
                            )
                        }
                }
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Deep Optical Transparency Liquid Glass Cards & Surfaces

/// Pure Liquid Glass card: radically transparent, eliminating milky white fog,
/// showcasing crystal clarity and crisp content legibility.
struct LiquidGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20
    var interactive: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if interactive {
                content
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.45 : 0.50))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            colorScheme == .dark ? Color.white.opacity(0.15) : Color.white.opacity(0.65),
                            lineWidth: 0.75
                        )
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.03),
                    radius: 12, y: 3
                )
        }
    }
}

/// Radical optical transparency floating capsule (for navigation bar groups, docks, batch action bars).
struct LiquidGlassCapsule: ViewModifier {
    var interactive: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.interactive(interactive), in: .capsule)
        } else {
            content
                .background(
                    Capsule().fill(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.50 : 0.55))
                )
                .overlay {
                    Capsule().strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.60),
                        lineWidth: 0.75
                    )
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04),
                    radius: 12, y: 3
                )
        }
    }
}

/// Standardized circular treatment.
struct LiquidGlassCircle: ViewModifier {
    var size: CGFloat = 44
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(Circle())
        } else {
            content
                .frame(width: size, height: size)
                .background(
                    Circle().fill(.ultraThinMaterial.opacity(0.55))
                )
                .overlay {
                    Circle()
                        .strokeBorder(
                            colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.55),
                            lineWidth: 0.75
                        )
                }
                .contentShape(Circle())
        }
    }
}

/// Prominent tinted glass action button.
struct LiquidGlassProminentButton: ViewModifier {
    var tintColor: Color = Color.appAccent
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.tint(tintColor).interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(tintColor, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: tintColor.opacity(0.3), radius: 6, y: 2)
        }
    }
}

// MARK: - View Extensions

extension View {
    func liquidGlassCircle(size: CGFloat = 44) -> some View {
        modifier(LiquidGlassCircle(size: size))
    }

    func liquidGlassCard(cornerRadius: CGFloat = 20, interactive: Bool = false) -> some View {
        modifier(LiquidGlassCard(cornerRadius: cornerRadius, interactive: interactive))
    }

    func liquidGlassCapsule(interactive: Bool = true) -> some View {
        modifier(LiquidGlassCapsule(interactive: interactive))
    }

    func liquidGlassProminent(tint: Color = Color.appAccent, cornerRadius: CGFloat = 12) -> some View {
        modifier(LiquidGlassProminentButton(tintColor: tint, cornerRadius: cornerRadius))
    }
}
