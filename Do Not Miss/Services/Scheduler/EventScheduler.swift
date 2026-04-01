import Foundation

@MainActor
final class EventScheduler {
    struct Configuration {
        let eventsPollingInterval: TimeInterval
        let tickInterval: TimeInterval
        let triggerOffset: TimeInterval
        let triggerTolerance: TimeInterval

        static let `default` = Configuration(
            eventsPollingInterval: 45,
            tickInterval: 1,
            triggerOffset: 60,
            triggerTolerance: 1.5
        )
    }

    struct DebugSnapshot {
        let isRunning: Bool
        let monitoredEventsCount: Int
        let nextTriggerDescription: String
        let recentTriggeredTitles: [String]
        let lastRefreshError: String?
        let snoozedEventTitle: String?
        let snoozeUntilDate: Date?
    }

    var onTrigger: ((CalendarEvent) -> Void)?
    var onDebugSnapshotChanged: ((DebugSnapshot) -> Void)?

    private let configuration: Configuration
    private let fetchEvents: () async throws -> [CalendarEvent]
    private let dateProvider: () -> Date

    private var isRunning = false
    private var scheduledEvents: [CalendarEvent] = []
    private var triggeredEventIDs: Set<String> = []
    private var recentTriggeredTitles: [String] = []
    private var lastRefreshError: String?
    private var loopTask: Task<Void, Never>?
    private var lastEventsRefreshDate: Date?
    private var snoozedEventsByID: [String: Date] = [:]

    init(
        configuration: Configuration? = nil,
        fetchEvents: @escaping () async throws -> [CalendarEvent],
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration ?? .default
        self.fetchEvents = fetchEvents
        self.dateProvider = dateProvider
    }

    func start() {
        guard loopTask == nil else {
            publishDebugSnapshot()
            return
        }

        isRunning = true
        publishDebugSnapshot()

        loopTask = Task { [weak self] in
            guard let self else { return }
            await self.runLoop()
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        isRunning = false
        publishDebugSnapshot()
    }

    func refreshEvents() async {
        do {
            let fetched = try await fetchEvents()
            scheduledEvents = normalize(events: fetched, now: dateProvider())
            lastRefreshError = nil
            lastEventsRefreshDate = dateProvider()
            pruneTriggeredEventIDs(now: dateProvider())
            pruneSnoozedEvents(now: dateProvider())
            publishDebugSnapshot()
        } catch {
            lastRefreshError = error.localizedDescription
            publishDebugSnapshot()
        }
    }

    func snooze(event: CalendarEvent, duration: TimeInterval) {
        guard duration > 0 else {
            return
        }

        let now = dateProvider()
        guard event.endDate > now else {
            return
        }

        let until = now.addingTimeInterval(duration)
        snoozedEventsByID[event.id] = until
        publishDebugSnapshot()
    }
}

private extension EventScheduler {
    func runLoop() async {
        await refreshEvents()

        while Task.isCancelled == false {
            evaluateSnoozedTriggers(now: dateProvider())
            evaluateTriggers(now: dateProvider())
            await refreshEventsIfNeeded(now: dateProvider())

            let nanoseconds = UInt64(configuration.tickInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    }

    func refreshEventsIfNeeded(now: Date) async {
        guard let lastEventsRefreshDate else {
            await refreshEvents()
            return
        }

        let shouldRefresh = now.timeIntervalSince(lastEventsRefreshDate) >= configuration.eventsPollingInterval
        if shouldRefresh {
            await refreshEvents()
        }
    }

    func evaluateTriggers(now: Date) {
        var didTrigger = false

        for event in scheduledEvents {
            guard shouldConsider(event: event, now: now) else {
                continue
            }

            let triggerDate = event.startDate.addingTimeInterval(-configuration.triggerOffset)
            let lowerBound = triggerDate.addingTimeInterval(-configuration.triggerTolerance)

            if now >= lowerBound, now < event.startDate {
                triggeredEventIDs.insert(event.id)
                appendTriggeredHistory(event.title)
                didTrigger = true
                onTrigger?(event)
            }
        }

        if didTrigger {
            publishDebugSnapshot()
        }
    }

    func evaluateSnoozedTriggers(now: Date) {
        guard snoozedEventsByID.isEmpty == false else {
            return
        }

        var didTrigger = false
        let dueIDs = snoozedEventsByID
            .filter { $0.value <= now }
            .map(\.key)

        for eventID in dueIDs {
            snoozedEventsByID.removeValue(forKey: eventID)

            guard let event = scheduledEvents.first(where: { $0.id == eventID }) else {
                continue
            }

            guard event.endDate > now else {
                continue
            }

            appendTriggeredHistory(event.title)
            didTrigger = true
            onTrigger?(event)
        }

        if didTrigger || dueIDs.isEmpty == false {
            publishDebugSnapshot()
        }
    }

    func shouldConsider(event: CalendarEvent, now: Date) -> Bool {
        if event.isAllDay {
            return false
        }

        if triggeredEventIDs.contains(event.id) {
            return false
        }

        if let snoozeUntil = snoozedEventsByID[event.id], now < snoozeUntil {
            return false
        }

        if event.endDate <= now {
            return false
        }

        return true
    }

    func normalize(events: [CalendarEvent], now: Date) -> [CalendarEvent] {
        events
            .filter { event in
                event.isAllDay == false && event.endDate > now
            }
            .sorted { lhs, rhs in
                lhs.startDate < rhs.startDate
            }
    }

    func appendTriggeredHistory(_ title: String) {
        recentTriggeredTitles.insert(title, at: 0)
        if recentTriggeredTitles.count > 5 {
            recentTriggeredTitles = Array(recentTriggeredTitles.prefix(5))
        }
    }

    func pruneTriggeredEventIDs(now: Date) {
        let aliveIDs = Set(
            scheduledEvents
                .filter { $0.endDate > now }
                .map(\.id)
        )

        triggeredEventIDs = triggeredEventIDs.intersection(aliveIDs)
    }

    func pruneSnoozedEvents(now: Date) {
        let aliveEventsByID = Dictionary(uniqueKeysWithValues: scheduledEvents.map { ($0.id, $0) })

        snoozedEventsByID = snoozedEventsByID.filter { eventID, snoozeUntil in
            guard let event = aliveEventsByID[eventID] else {
                return false
            }

            if event.endDate <= now {
                return false
            }

            return snoozeUntil > now
        }
    }

    func nextTriggerDescription(now: Date) -> String {
        guard let nextEvent = scheduledEvents.first(where: { event in
            shouldConsider(event: event, now: now)
        }) else {
            return L10n.tr("scheduler.no_upcoming_trigger")
        }

        let triggerDate = nextEvent.startDate.addingTimeInterval(-configuration.triggerOffset)
        let timeFormatter = RelativeDateTimeFormatter()
        timeFormatter.unitsStyle = .short
        let relative = timeFormatter.localizedString(for: triggerDate, relativeTo: now)
        return "\(nextEvent.title) (\(relative))"
    }

    func publishDebugSnapshot() {
        let now = dateProvider()
        let currentSnooze = snoozedEventsByID
            .filter { $0.value > now }
            .min { $0.value < $1.value }
        let snoozedEvent = currentSnooze.flatMap { pair in
            scheduledEvents.first(where: { $0.id == pair.key })
        }

        onDebugSnapshotChanged?(
            DebugSnapshot(
                isRunning: isRunning,
                monitoredEventsCount: scheduledEvents.count,
                nextTriggerDescription: nextTriggerDescription(now: now),
                recentTriggeredTitles: recentTriggeredTitles,
                lastRefreshError: lastRefreshError,
                snoozedEventTitle: snoozedEvent?.title,
                snoozeUntilDate: currentSnooze?.value
            )
        )
    }
}
