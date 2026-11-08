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

// MARK: - Liquid Glass Modifiers

/// A standardized 44x44 circular button treatment. Uses interactive Liquid Glass
/// on iOS 26+ and falls back to a delicate ultra-thin material ring on earlier iOS.
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
