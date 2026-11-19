import SwiftUI

extension Color {
    static let appBackground = Color("AppBackground")
    static let appSurface = Color("AppSurface")
    static let actionAccent = Color(red: 0.00, green: 0.32, blue: 0.69)
    static let actionAccentOnDark = Color(red: 0.49, green: 0.74, blue: 1.00)
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
