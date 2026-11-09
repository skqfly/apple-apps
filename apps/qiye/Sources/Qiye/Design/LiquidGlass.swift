import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Native Haptic Feedback System

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

// MARK: - Apple Native Navigation Toolbar Button Styles (Photos & Files Parity)

/// Standard Apple Photos / Files navigation bar capsule text button (e.g. "选择", "取消", "全选").
/// Features optical transparency, subtle specular rim highlight, and spring press feedback.
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
                                : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.05))
                        )
                        .overlay {
                            if !isSelected {
                                Capsule()
                                    .strokeBorder(
                                        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.50),
                                        lineWidth: 0.6
                                    )
                            }
                        }
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Standard Apple circular navigation bar button (34x34pt).
/// Pure optical lens with responsive spring touch feel and high-contrast dark foreground.
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
                        .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.05))
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                                    lineWidth: 0.6
                                )
                        }
                }
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Native Liquid Glass Component Styles (Inspired by LiquidGlassKit & Apple Guidelines)

/// Standard iOS 26+ .glass button style with clean Material fallback.
struct LiquidGlassButtonStyle: ButtonStyle {
    var isProminent: Bool = false
    var tintColor: Color = Color.appAccent
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            if isProminent {
                configuration.label
                    .glassEffect(.regular.tint(tintColor).interactive(), in: .capsule)
                    .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                    .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            } else {
                configuration.label
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                    .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            }
        } else {
            configuration.label
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isProminent {
                        Capsule().fill(tintColor)
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial.opacity(0.60))
                            .overlay {
                                Capsule().strokeBorder(
                                    colorScheme == .dark ? Color.white.opacity(0.15) : Color.white.opacity(0.55),
                                    lineWidth: 0.6
                                )
                            }
                    }
                }
                .foregroundStyle(isProminent ? Color.white : Color.primary)
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .animation(.snappy(duration: 0.15), value: configuration.isPressed)
        }
    }
}

// MARK: - Optical Transparency Cards & Floating Capsules (Never Milky White)

/// Standard Liquid Glass card with true optical transparency, eliminating white milkiness.
/// On iOS 26+ uses native .glassEffect, on fallback uses ultra-thin material with subtle rim refraction.
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
                        .fill(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.40 : 0.45))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.65),
                            lineWidth: 0.75
                        )
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.03),
                    radius: 12, y: 3
                )
        }
    }
}

/// Floating Liquid Glass capsule (for batch operation docks, toolbars, etc.).
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
                    Capsule().fill(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.45 : 0.50))
                )
                .overlay {
                    Capsule().strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.60),
                        lineWidth: 0.75
                    )
                }
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.04),
                    radius: 14, y: 4
                )
        }
    }
}

/// Standard circular glass modifier.
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
                    Circle().fill(.ultraThinMaterial.opacity(0.50))
                )
                .overlay {
                    Circle()
                        .strokeBorder(
                            colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.55),
                            lineWidth: 0.75
                        )
                }
                .contentShape(Circle())
        }
    }
}

/// Prominent tinted glass action modifier.
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

// MARK: - Convenient View Extensions

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
