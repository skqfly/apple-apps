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

/// Compact controls share the neutral collection palette.
struct AppleNavCapsuleButtonStyle: ButtonStyle {
    var isSelected: Bool = false
    var isAccentText: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.appBackground : Color.primary)
            .padding(.horizontal, 14).frame(minHeight: 36)
            .background(isSelected ? Color.primary : Color.primary.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : CollectionStyle.spring, value: configuration.isPressed)
    }
}

struct AppleNavCircleButtonStyle: ButtonStyle {
    var size: CGFloat = 34
    var isAccent: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.primary)
            .frame(width: size, height: size)
            .background(Color.primary.opacity(isAccent ? 0.14 : 0.08), in: Circle())
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .animation(reduceMotion ? nil : CollectionStyle.spring, value: configuration.isPressed)
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

/// Compatibility wrapper for existing content cards in the collection palette.
struct LiquidGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20
    var interactive: Bool = false

    func body(content: Content) -> some View {
        content.collectionSurface(radius: cornerRadius)
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
