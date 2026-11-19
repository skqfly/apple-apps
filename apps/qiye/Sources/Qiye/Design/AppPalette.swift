import SwiftUI

extension Color {
    static let appBackground = Color("AppBackground")
    static let appSurface = Color("AppSurface")
    static var actionAccent: Color { AppTheme.shared.accentColor }
    static var actionAccentOnDark: Color { AppTheme.shared.accentColor.accentOnDark }
    static let actionDestructive = Color(red: 0.69, green: 0.12, blue: 0.19)
    static let actionDestructiveOnDark = Color(red: 1.00, green: 0.54, blue: 0.57)
    static var appAccent: Color {
        AppTheme.shared.accentColor
    }
}

extension View {
    func appPageBackground() -> some View {
        background(Color.appBackground.ignoresSafeArea())
    }
}
