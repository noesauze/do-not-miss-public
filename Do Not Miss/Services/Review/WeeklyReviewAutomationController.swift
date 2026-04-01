import Foundation
import Combine

@MainActor
final class WeeklyReviewAutomationController: ObservableObject {
    @Published var isEnabled: Bool
    @Published var selectedWeekday: WeeklyReviewWeekday
    @Published var selectedTime: Date
    @Published private(set) var modeDescription: String
    @Published private(set) var nextRunDescription: String
    @Published private(set) var lastRunDescription: String

    private let preferencesStore: PreferencesStore
    private let weeklyReviewLauncher: WeeklyReviewLauncher
    private var onStatusMessage: (String) -> Void
    private var onSessionEnded: (WeeklyReviewResult) -> Void

    private lazy var scheduler: WeeklyReviewScheduler = {
        let scheduler = WeeklyReviewScheduler(
            preferencesStore: preferencesStore,
            triggerAction: { [weak self] in
                guard let self else {
                    return .failed
                }
                return await self.startAutomaticallyIfNeeded()
            }
        )

        scheduler.onSnapshotChanged = { [weak self] snapshot in
            self?.apply(snapshot: snapshot)
        }

        return scheduler
    }()

    init(
        preferencesStore: PreferencesStore,
        weeklyReviewLauncher: WeeklyReviewLauncher,
        onStatusMessage: ((String) -> Void)? = nil
    ) {
        self.preferencesStore = preferencesStore
        self.weeklyReviewLauncher = weeklyReviewLauncher
        self.onStatusMessage = onStatusMessage ?? { _ in }
        self.onSessionEnded = { _ in }

        self.isEnabled = preferencesStore.weeklyReviewEnabled
        self.selectedWeekday = preferencesStore.weeklyReviewWeekday
        self.selectedTime = preferencesStore.weeklyReviewTimeDate
        self.modeDescription = preferencesStore.weeklyReviewEnabled
            ? L10n.tr("weekly_review.automation.mode.enabled")
            : L10n.tr("weekly_review.automation.mode.disabled")
        self.nextRunDescription = L10n.tr("common.none")
        self.lastRunDescription = preferencesStore.weeklyReviewLastAutomaticRunDate.map(Self.formatDateTime) ?? L10n.tr("common.none")
    }

    func setStatusMessageHandler(_ handler: @escaping (String) -> Void) {
        onStatusMessage = handler
    }

    func setSessionEndedHandler(_ handler: @escaping (WeeklyReviewResult) -> Void) {
        onSessionEnded = handler
    }

    func start() {
        scheduler.start()
    }

    func stop() {
        scheduler.stop()
    }

    func setEnabled(_ enabled: Bool) {
        preferencesStore.weeklyReviewEnabled = enabled
        isEnabled = enabled
        modeDescription = enabled
            ? L10n.tr("weekly_review.automation.mode.enabled")
            : L10n.tr("weekly_review.automation.mode.disabled")

        scheduler.recomputeNextRunDate()
        Task {
            await scheduler.triggerIfNeeded()
        }
    }

    func setWeekday(_ weekday: WeeklyReviewWeekday) {
        preferencesStore.weeklyReviewWeekday = weekday
        selectedWeekday = weekday

        scheduler.recomputeNextRunDate()
        Task {
            await scheduler.triggerIfNeeded()
        }
    }

    func setTime(_ date: Date) {
        preferencesStore.setWeeklyReviewTime(from: date)
        selectedTime = preferencesStore.weeklyReviewTimeDate

        scheduler.recomputeNextRunDate()
        Task {
            await scheduler.triggerIfNeeded()
        }
    }

    private func apply(snapshot: WeeklyReviewSchedulerSnapshot) {
        isEnabled = snapshot.isAutoEnabled
        selectedWeekday = preferencesStore.weeklyReviewWeekday
        selectedTime = preferencesStore.weeklyReviewTimeDate
        modeDescription = snapshot.isAutoEnabled
            ? L10n.tr("weekly_review.automation.mode.enabled")
            : L10n.tr("weekly_review.automation.mode.disabled")

        if let nextRun = snapshot.nextRunDate {
            nextRunDescription = Self.formatDateTime(nextRun)
        } else {
            nextRunDescription = snapshot.isAutoEnabled
                ? L10n.tr("weekly_review.automation.next_run.none")
                : L10n.tr("weekly_review.automation.mode.disabled")
        }

        lastRunDescription = snapshot.lastRunDate.map(Self.formatDateTime) ?? L10n.tr("common.none")
    }

    private func startAutomaticallyIfNeeded() async -> WeeklyReviewAutoTriggerOutcome {
        let launchOutcome = await weeklyReviewLauncher.startReview(startWhenEmpty: false) { [weak self] result in
            guard let self else {
                return
            }

            self.onSessionEnded(result)
            let decidedCount = result.acceptedCount + result.declinedCount + result.tentativeCount
            switch result.endReason {
            case .completed:
                self.onStatusMessage(
                    L10n.tr(
                        "status.weekly_review_auto_completed",
                        result.acceptedCount,
                        result.declinedCount,
                        result.tentativeCount
                    )
                )
            case .cancelled:
                self.onStatusMessage(
                    L10n.tr(
                        "status.weekly_review_auto_cancelled",
                        decidedCount,
                        result.totalEvents
                    )
                )
            }
        }

        switch launchOutcome {
        case .started(let events):
            onStatusMessage(L10n.tr("status.weekly_review_auto_started", events.count))
            return .started
        case .noReviewableEvents:
            onStatusMessage(L10n.tr("status.weekly_review_auto_skipped_no_events"))
            return .skippedNoReviewableEvents
        case .alreadyActive:
            onStatusMessage(L10n.tr("status.weekly_review_already_active"))
            return .alreadyActive
        case .alreadyLaunching:
            onStatusMessage(L10n.tr("status.weekly_review_loading"))
            return .alreadyLaunching
        case .notAuthenticated:
            onStatusMessage(L10n.tr("status.weekly_review_auto_skipped_sign_in"))
            return .failed
        case .failed(let errorMessage):
            onStatusMessage(L10n.tr("status.weekly_review_auto_failed", errorMessage))
            return .failed
        }
    }

    private static func formatDateTime(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}
