import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appState.isReady == false {
                ProgressView("Starting DoNotMiss…")
                    .controlSize(.small)
            }

            statusLine(title: "Google", value: appState.authStatusText)
            statusLine(title: "Monitoring", value: appState.schedulerStatus)
            statusLine(title: "Next Event", value: appState.nextTriggerDescription)
            statusLine(title: "Last Triggered", value: appState.lastTriggeredEventTitle)

            Divider()

            SettingsLink(label: {
                Text(L10n.tr("Open Settings"))
            })

            Button("Test Overlay") {
                appState.triggerTestOverlay()
            }

            Button(appState.monitoringToggleTitle) {
                appState.toggleMonitoring()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 340)
    }

    @ViewBuilder
    private func statusLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

#if DEBUG
#Preview {
    MenuBarContentView(appState: AppState())
}
#endif
