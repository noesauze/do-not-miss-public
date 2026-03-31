import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appState.isReady == false {
                ProgressView(L10n.tr("Starting DoNotMiss…"))
                    .controlSize(.small)
            }

            if appState.isLaunchingWeeklyReview {
                ProgressView(L10n.tr("status.weekly_review_loading"))
                    .controlSize(.small)
            }

            statusLine(title: L10n.tr("Google"), value: appState.authStatusText)
            statusLine(title: L10n.tr("Monitoring"), value: appState.schedulerStatus)
            statusLine(title: L10n.tr("Next Event"), value: appState.nextTriggerDescription)
            statusLine(title: L10n.tr("menu.weekly_review_auto"), value: appState.weeklyReviewAutomation.modeDescription)
            statusLine(title: L10n.tr("menu.next_weekly_review"), value: appState.weeklyReviewAutomation.nextRunDescription)
            statusLine(title: L10n.tr("Last Triggered"), value: appState.lastTriggeredEventTitle)

            if let weeklyReviewError = appState.weeklyReviewLaunchError {
                Text(weeklyReviewError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            SettingsLink(label: {
                Text(L10n.tr("Open Settings"))
            })
            .simultaneousGesture(TapGesture().onEnded {
                NSApplication.shared.activate(ignoringOtherApps: true)
            })

            Button(L10n.tr("menu.start_weekly_review_now")) {
                Task {
                    await appState.startWeeklyReviewManually()
                }
            }
            .disabled(appState.isLaunchingWeeklyReview)

            Button(L10n.tr("Test Overlay")) {
                appState.triggerTestOverlay()
            }

            Button(appState.monitoringToggleTitle) {
                appState.toggleMonitoring()
            }

            Divider()

            Button(L10n.tr("Quit")) {
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
