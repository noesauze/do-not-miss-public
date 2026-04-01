import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            StartupSection(loginItemManager: appState.loginItemManager)

            Section(L10n.tr("Google Account")) {
                labeledValue(L10n.tr("Status"), appState.authStatusText)

                Button(appState.authButtonTitle) {
                    Task {
                        await appState.handleAuthButtonTapped()
                    }
                }
            }

            Section(L10n.tr("settings.weekly_review.section")) {
                Toggle(L10n.tr("settings.weekly_review.enable"), isOn: Binding(
                    get: { appState.weeklyReviewAutomation.isEnabled },
                    set: { appState.weeklyReviewAutomation.setEnabled($0) }
                ))

                Picker(L10n.tr("settings.weekly_review.day"), selection: Binding(
                    get: { appState.weeklyReviewAutomation.selectedWeekday },
                    set: { appState.weeklyReviewAutomation.setWeekday($0) }
                )) {
                    ForEach(WeeklyReviewWeekday.allCases) { weekday in
                        Text(weekday.localizedName).tag(weekday)
                    }
                }
                .disabled(appState.weeklyReviewAutomation.isEnabled == false)

                DatePicker(
                    L10n.tr("settings.weekly_review.time"),
                    selection: Binding(
                        get: { appState.weeklyReviewAutomation.selectedTime },
                        set: { appState.weeklyReviewAutomation.setTime($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
                .disabled(appState.weeklyReviewAutomation.isEnabled == false)

                labeledValue(L10n.tr("settings.weekly_review.auto_mode"), appState.weeklyReviewAutomation.modeDescription)
                labeledValue(L10n.tr("settings.weekly_review.next_run"), appState.weeklyReviewAutomation.nextRunDescription)
                labeledValue(L10n.tr("settings.weekly_review.last_run"), appState.weeklyReviewAutomation.lastRunDescription)
            }

            Section(L10n.tr("Monitoring")) {
                labeledValue(L10n.tr("Scheduler"), appState.schedulerStatus)
                labeledValue(L10n.tr("Next Event"), appState.nextTriggerDescription)

                Button(appState.startStopSchedulerTitle) {
                    appState.toggleMonitoring()
                }
            }

            Section(L10n.tr("Overlay")) {
                Button(L10n.tr("Test Overlay")) {
                    appState.triggerTestOverlay()
                }
            }

            Section(L10n.tr("settings.onboarding.section")) {
                Button(L10n.tr("settings.onboarding.replay")) {
                    appState.relaunchOnboarding()
                }
            }

            Section(L10n.tr("settings.about.section")) {
                labeledValue(L10n.tr("settings.about.version"), AppVersionProvider.resolved())
            }

            Section(L10n.tr("Debug")) {
                labeledValue(L10n.tr("Status"), appState.statusMessage)
                labeledValue(L10n.tr("Last Triggered"), appState.lastTriggeredEventTitle)
                labeledValue(L10n.tr("settings.debug.snoozed_event"), appState.snoozedEventTitle)
                labeledValue(L10n.tr("settings.debug.snooze_until"), appState.snoozeUntilDescription)
                labeledValue(L10n.tr("Fetched Events"), "\(appState.fetchedEvents.count)")
                labeledValue(L10n.tr("Fetch Error"), appState.calendarFetchError ?? L10n.tr("common.none"))

                Button(L10n.tr("settings.debug.show_latest_backend_message")) {
                    Task {
                        await appState.presentLatestBackendMessageForDebug()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 420)
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
        Section(L10n.tr("Startup")) {
            Toggle(L10n.tr("Launch at login"), isOn: Binding(
                get: { loginItemManager.isEnabled },
                set: { newValue in
                    Task {
                        try? await loginItemManager.setLaunchAtLogin(enabled: newValue)
                    }
                }
            ))
            .disabled(loginItemManager.isUpdating)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L10n.tr("Status"))
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

            Button(L10n.tr("Open Login Items Settings")) {
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
