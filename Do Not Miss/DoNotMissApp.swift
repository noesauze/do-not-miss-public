import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        enforceSingleRunningInstance()
    }
}

private extension AppDelegate {
    func enforceSingleRunningInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let runningInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard let existingInstance = runningInstances.first(where: { $0.processIdentifier != currentProcessIdentifier }) else {
            return
        }

        existingInstance.activate(options: [.activateAllWindows])
        #if DEBUG
        print("[DoNotMissApp] Duplicate instance detected, terminating current process")
        #endif
        NSApp.terminate(nil)
    }
}

@main
struct DoNotMissApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    init() {
        // Menu bar apps must stay alive even when they temporarily have no visible windows.
        ProcessInfo.processInfo.disableAutomaticTermination("Keep DoNotMiss running from the menu bar")
        ProcessInfo.processInfo.disableSuddenTermination()

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
