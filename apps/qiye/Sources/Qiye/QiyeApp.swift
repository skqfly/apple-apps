import SwiftUI

@main
struct QiyeApp: App {
    @AppStorage("appearance") private var appearance = "dark"

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some Scene {
        WindowGroup {
            AppNavigationView()
                .preferredColorScheme(colorScheme)
        }
    }
}
