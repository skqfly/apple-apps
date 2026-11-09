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

// MARK: - Apple Native Navigation Bar ButtonStyles (Photos & Files Reference)

/// Standard Apple Photos / Files navigation bar capsule text button (e.g. "选择", "编辑", "取消", "全选").
/// 34pt height, translucent material background, semi-bold text, smooth spring press feedback.
struct AppleNavCapsuleButtonStyle: ButtonStyle {
    var isSelected: Bool = false
    var isAccentText: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(isAccentText ? Color.appAccent : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background {
                if #available(iOS 26, *) {
                    Capsule()
                        .fill(isSelected ? Color.appAccent : Color.clear)
                        .glassEffect(.regular.interactive(), in: .capsule)
                } else {
                    Capsule()
                        .fill(
                            isSelected
                                ? Color.appAccent
                                : (colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.06))
                        )
                }
            }
            .overlay {
                if !isSelected {
                    Capsule()
                        .strokeBorder(
                            colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.05),
                            lineWidth: 0.5
                        )
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Standard Apple Photos / Files navigation bar circular button (e.g. "+", "...", "filter").
/// 34x34pt circle, translucent material background, centered icon.
struct AppleNavCircleButtonStyle: ButtonStyle {
    var size: CGFloat = 34
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
                        .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.06))
                }
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.05),
                        lineWidth: 0.5
                    )
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Liquid Glass Modifiers

/// A standardized 44x44 circular button treatment for prominent standalone actions.
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
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10),
                            lineWidth: 0.6
                        )
                }
                .contentShape(Circle())
        }
    }
}

/// A card surface with Liquid Glass on iOS 26+ and refined material fallback.
struct LiquidGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 18
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
                        .fill(Color.appSurface)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06),
                            lineWidth: 0.75
                        )
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.05),
                    radius: 12, y: 4
                )
        }
    }
}

/// A floating capsule container, perfect for toolbars, docks, and batch action bars.
struct LiquidGlassCapsule: ViewModifier {
    var interactive: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.interactive(interactive), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(
                            colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08),
                            lineWidth: 0.6
                        )
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08),
                    radius: 16, y: 5
                )
        }
    }
}

/// An interactive prominent action button (tinted glass on iOS 26+, prominent bordered on earlier).
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

    func liquidGlassCard(cornerRadius: CGFloat = 18, interactive: Bool = false) -> some View {
        modifier(LiquidGlassCard(cornerRadius: cornerRadius, interactive: interactive))
    }

    func liquidGlassCapsule(interactive: Bool = true) -> some View {
        modifier(LiquidGlassCapsule(interactive: interactive))
    }

    func liquidGlassProminent(tint: Color = Color.appAccent, cornerRadius: CGFloat = 12) -> some View {
        modifier(LiquidGlassProminentButton(tintColor: tint, cornerRadius: cornerRadius))
    }
}
