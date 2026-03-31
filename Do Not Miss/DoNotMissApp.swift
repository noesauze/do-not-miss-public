import SwiftUI

@main
struct DoNotMissApp: App {
    @StateObject private var appState: AppState

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        DispatchQueue.main.async {
            state.showOnboardingIfNeeded()
        }
    }

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
