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

extension View {
    @ViewBuilder
    func toolbarConfirmationStyle() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Color.appAccent)
        } else {
            self
        }
    }
}

enum ButtonMetrics {
    static let minimumHitSide: CGFloat = 44
    static let floatingSide: CGFloat = 48
    static let floatingSpacing: CGFloat = 6
    static let floatingInset: CGFloat = 4
}

// MARK: - Content Buttons

enum ContentActionSize: Equatable {
    case medium, large

    var height: CGFloat { self == .large ? 50 : 34 }
}

enum ContentActionEmphasis: Equatable {
    case borderless, standard, prominent
}

struct ContentActionStyle: ButtonStyle {
    let emphasis: ContentActionEmphasis
    let size: ContentActionSize
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let isDestructive = configuration.role == .destructive
        let isProminent = emphasis == .prominent && isEnabled
        let accent = isDestructive ? Color.actionDestructive : Color.actionAccent
        let foreground = !isEnabled ? Color(uiColor: .tertiaryLabel)
            : isProminent ? .white
            : colorScheme == .dark ? (isDestructive ? .actionDestructiveOnDark : .actionAccentOnDark) : accent
        let fill = emphasis == .borderless ? Color.clear
            : isProminent ? accent : Color(uiColor: .tertiarySystemFill)

        configuration.label
            .font(size == .large ? .body : .subheadline)
            .padding(.horizontal, size == .large ? 20 : 14)
            .padding(.vertical, size == .large ? 14 : 7)
            .frame(minWidth: size.height, minHeight: size.height)
            .foregroundStyle(foreground)
            .background {
                Capsule()
                    .fill(fill)
                    .overlay {
                        if configuration.isPressed && isEnabled {
                            Capsule().fill(Color.primary.opacity(0.08))
                        }
                    }
                    .allowsHitTesting(false)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .frame(minWidth: ButtonMetrics.minimumHitSide, minHeight: ButtonMetrics.minimumHitSide)
            .contentShape(Rectangle())
    }
}

extension View {
    func contentActionStyle(_ emphasis: ContentActionEmphasis = .standard,
                            size: ContentActionSize = .medium) -> some View {
        buttonStyle(ContentActionStyle(emphasis: emphasis, size: size))
    }
}

/// Keep choices on one line when they fit and reflow them at larger text sizes.
struct ContentActionChoices<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 4) { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Icon Actions

/// A native label lets the navigation bar size and group its own glass controls.
struct ToolbarActionIcon: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
    }
}

/// Fixed label geometry for controls outside the system navigation bar.
struct ActionIcon: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Image(systemName: systemImage)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 17, weight: .medium))
            .modifier(ActionHitArea())
            .accessibilityLabel(title)
    }
}

struct ActionHitArea: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: ButtonMetrics.floatingSide, height: ButtonMetrics.floatingSide)
            .contentShape(Rectangle())
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
    var size: CGFloat = ButtonMetrics.floatingSide
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(Rectangle())
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
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Convenient View Extensions

extension View {
    func liquidGlassCircle(size: CGFloat = ButtonMetrics.floatingSide) -> some View {
        modifier(LiquidGlassCircle(size: size))
    }

    func liquidGlassCard(cornerRadius: CGFloat = 20, interactive: Bool = false) -> some View {
        modifier(LiquidGlassCard(cornerRadius: cornerRadius, interactive: interactive))
    }

    func liquidGlassCapsule(interactive: Bool = true) -> some View {
        modifier(LiquidGlassCapsule(interactive: interactive))
    }
}

struct GlassActionGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: ButtonMetrics.floatingSpacing) { content }
            .padding(.horizontal, ButtonMetrics.floatingInset)
            .liquidGlassCapsule(interactive: false)
    }
}
