import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if appState.isReady == false {
                ProgressView(L10n.tr("Starting DoNotMiss…"))
                    .controlSize(.small)
            }

            if appState.isLaunchingWeeklyReview {
                ProgressView(L10n.tr("status.weekly_review_loading"))
                    .controlSize(.small)
            }

            if appState.isAuthenticated {
                statusLine(title: L10n.tr("Google"), value: appState.authStatusText)
            } else {
                statusLineWithAction(
                    title: L10n.tr("Google"),
                    value: appState.authStatusText,
                    actionTitle: L10n.tr("action.sign_in"),
                    isActionDisabled: false,
                    onAction: {
                        Task {
                            await appState.handleAuthButtonTapped()
                        }
                    }
                )
            }

            Divider()

            statusLineWithAction(
                title: L10n.tr("Monitoring"),
                value: appState.schedulerStatus,
                actionTitle: appState.isMonitoringActive ? L10n.tr("menu.cut_alerts") : L10n.tr("menu.enable_alerts"),
                actionSystemImage: appState.isMonitoringActive ? "pause.fill" : "play.fill",
                isActionDisabled: false,
                onAction: {
                    appState.toggleMonitoring()
                }
            )
            statusLine(title: L10n.tr("Next Event"), value: appState.nextTriggerDescription)

            statusLineWithAction(
                title: L10n.tr("menu.next_weekly_review"),
                value: appState.weeklyReviewAutomation.nextRunDescription,
                actionTitle: L10n.tr("menu.start_weekly_review_now"),
                isActionDisabled: appState.isLaunchingWeeklyReview,
                onAction: {
                    Task {
                        await appState.startWeeklyReviewManually()
                    }
                }
            )
            if let weeklyReviewError = appState.weeklyReviewLaunchError {
                Text(weeklyReviewError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 12) {
                SettingsLink(label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                })
                .help(L10n.tr("Open Settings"))
                .simultaneousGesture(TapGesture().onEnded {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                })

                Spacer()

                Button(L10n.tr("Quit")) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
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

    @ViewBuilder
    private func statusLineWithAction(
        title: String,
        value: String,
        actionTitle: String,
        actionSystemImage: String? = nil,
        isActionDisabled: Bool,
        onAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Button(action: onAction) {
                if let actionSystemImage {
                    Label {
                        Text(actionTitle)
                    } icon: {
                        Image(systemName: actionSystemImage)
                    }
                    .labelStyle(.titleAndIcon)
                } else {
                    Text(actionTitle)
                }
            }
            .disabled(isActionDisabled)
        }
    }

}

#if DEBUG
#Preview {
    MenuBarContentView(appState: AppState())
}
#endif
