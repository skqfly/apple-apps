import SwiftUI

extension Color {
    static let appBackground = Color("AppBackground")
    static let appSurface = Color("AppSurface")
    static var appAccent: Color {
        AppTheme.shared.accentColor
    }
}
