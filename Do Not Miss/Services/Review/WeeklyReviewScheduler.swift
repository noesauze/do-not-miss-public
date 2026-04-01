import AppKit
import Foundation

enum WeeklyReviewAutoTriggerOutcome {
    case started
    case skippedNoReviewableEvents
    case alreadyActive
    case alreadyLaunching
    case failed
}

struct WeeklyReviewSchedulerSnapshot {
    let isRunning: Bool
    let isAutoEnabled: Bool
    let nextRunDate: Date?
    let lastRunDate: Date?
}

@MainActor
final class WeeklyReviewScheduler {
    var onSnapshotChanged: ((WeeklyReviewSchedulerSnapshot) -> Void)?

    private let preferencesStore: PreferencesStore
    private let triggerAction: () async -> WeeklyReviewAutoTriggerOutcome
    private let timerInterval: TimeInterval = 20

    private var timer: Timer?
    private var notificationObservers: [NSObjectProtocol] = []

    private(set) var isRunning: Bool = false
    private(set) var nextRunDate: Date?
    private(set) var lastRunDate: Date?

    init(
        preferencesStore: PreferencesStore,
        triggerAction: @escaping () async -> WeeklyReviewAutoTriggerOutcome
    ) {
        self.preferencesStore = preferencesStore
        self.triggerAction = triggerAction
        self.lastRunDate = preferencesStore.weeklyReviewLastAutomaticRunDate
    }

    func start() {
        guard isRunning == false else {
            publishSnapshot()
            return
        }

        isRunning = true
        installObservers()
        startTimer()
        recomputeNextRunDate()

        Task {
            await triggerIfNeeded()
        }
    }

    func stop() {
        guard isRunning else {
            publishSnapshot()
            return
        }

        isRunning = false
        timer?.invalidate()
        timer = nil

        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()

        publishSnapshot()
    }

    func recomputeNextRunDate() {
        guard preferencesStore.weeklyReviewEnabled else {
            nextRunDate = nil
            publishSnapshot()
            return
        }

        nextRunDate = computeNextRunDate(after: Date().addingTimeInterval(-60))
        publishSnapshot()
    }

    func triggerIfNeeded() async {
        guard isRunning else {
            return
        }

        guard preferencesStore.weeklyReviewEnabled else {
            nextRunDate = nil
            publishSnapshot()
            return
        }

        guard let slotDate = nextRunDate else {
            recomputeNextRunDate()
            return
        }

        let now = Date()
        guard now >= slotDate else {
            return
        }

        let calendar = Calendar.autoupdatingCurrent
        if let lastTriggeredSlot = preferencesStore.weeklyReviewLastTriggeredSlotDate,
           calendar.isDate(lastTriggeredSlot, equalTo: slotDate, toGranularity: .minute) {
            nextRunDate = computeNextRunDate(after: slotDate.addingTimeInterval(60))
            publishSnapshot()
            return
        }

        let outcome = await triggerAction()
        switch outcome {
        case .started, .skippedNoReviewableEvents, .alreadyActive, .alreadyLaunching, .failed:
            preferencesStore.weeklyReviewLastTriggeredSlotDate = slotDate
            preferencesStore.weeklyReviewLastAutomaticRunDate = now
            lastRunDate = now
        }

        nextRunDate = computeNextRunDate(after: slotDate.addingTimeInterval(60))
        publishSnapshot()
    }

    private func computeNextRunDate(after date: Date) -> Date? {
        let weekday = preferencesStore.weeklyReviewWeekday.rawValue
        let hour = preferencesStore.weeklyReviewHour
        let minute = preferencesStore.weeklyReviewMinute

        var targetComponents = DateComponents()
        targetComponents.hour = hour
        targetComponents.minute = minute
        targetComponents.second = 0
        targetComponents.weekday = weekday

        return Calendar.autoupdatingCurrent.nextDate(
            after: date,
            matching: targetComponents,
            matchingPolicy: .nextTime,
            direction: .forward
        )
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }
            Task {
                await self.triggerIfNeeded()
            }
        }
    }

    private func installObservers() {
        guard notificationObservers.isEmpty else {
            return
        }

        let names: [Notification.Name] = [
            .NSSystemClockDidChange,
            .NSSystemTimeZoneDidChange,
            .NSCalendarDayChanged,
            NSApplication.didBecomeActiveNotification
        ]

        for name in names {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    self.recomputeNextRunDate()
                    await self.triggerIfNeeded()
                }
            }
            notificationObservers.append(observer)
        }
    }

    private func publishSnapshot() {
        onSnapshotChanged?(WeeklyReviewSchedulerSnapshot(
            isRunning: isRunning,
            isAutoEnabled: preferencesStore.weeklyReviewEnabled,
            nextRunDate: nextRunDate,
            lastRunDate: lastRunDate
        ))
    }
}
