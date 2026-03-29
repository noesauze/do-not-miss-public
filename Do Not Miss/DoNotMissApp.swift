import SwiftUI

@main
struct DoNotMissApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("DoNotMiss", systemImage: "calendar.badge.clock") {
            MenuBarContentView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
        }
    }
}
