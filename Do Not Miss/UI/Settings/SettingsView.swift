import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            StartupSection(loginItemManager: appState.loginItemManager)

            Section("Google Account") {
                labeledValue("Status", appState.authStatusText)

                Button(appState.authButtonTitle) {
                    Task {
                        await appState.handleAuthButtonTapped()
                    }
                }
            }

            Section("Monitoring") {
                labeledValue("Scheduler", appState.schedulerStatus)
                labeledValue("Next Event", appState.nextTriggerDescription)

                Button(appState.startStopSchedulerTitle) {
                    appState.toggleMonitoring()
                }
            }

            Section("Overlay") {
                Button("Test Overlay") {
                    appState.triggerTestOverlay()
                }
            }

            Section("Debug") {
                labeledValue("Status", appState.statusMessage)
                labeledValue("Last Triggered", appState.lastTriggeredEventTitle)
                labeledValue("Snoozed Event", appState.snoozedEventTitle)
                labeledValue("Snooze Until", appState.snoozeUntilDescription)
                labeledValue("Fetched Events", "\(appState.fetchedEvents.count)")
                labeledValue("Fetch Error", appState.calendarFetchError ?? L10n.tr("common.none"))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 380)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .lineLimit(2)
                .truncationMode(.tail)
                .textSelection(.enabled)
        }
    }
}

private struct StartupSection: View {
    @ObservedObject var loginItemManager: LoginItemManager

    var body: some View {
        Section("Startup") {
            Toggle("Launch at login", isOn: Binding(
                get: { loginItemManager.isEnabled },
                set: { newValue in
                    Task {
                        try? await loginItemManager.setLaunchAtLogin(enabled: newValue)
                    }
                }
            ))
            .disabled(loginItemManager.isUpdating)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Status")
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)

                Text(loginItemManager.statusDescription)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            if let errorMessage = loginItemManager.lastErrorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Open Login Items Settings") {
                loginItemManager.openLoginItemsSystemSettings()
            }
        }
        .onAppear {
            loginItemManager.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItemManager.refreshStatus()
        }
    }
}

#if DEBUG
#Preview {
    SettingsView(appState: AppState())
}
#endif
