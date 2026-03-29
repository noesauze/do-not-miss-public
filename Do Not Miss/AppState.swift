import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var statusMessage: String = L10n.tr("status.initializing")
    @Published private(set) var isReady: Bool = false
    @Published private(set) var authStatusText: String = L10n.tr("auth.disconnected")
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var isFetchingCalendar: Bool = false
    @Published private(set) var fetchedEvents: [CalendarEvent] = []
    @Published private(set) var calendarFetchError: String?
    @Published private(set) var isMonitoringActive: Bool = false
    @Published private(set) var schedulerStatus: String = L10n.tr("status.inactive")
    @Published private(set) var nextTriggerDescription: String = L10n.tr("scheduler.no_upcoming_trigger")
    @Published private(set) var lastTriggeredEventTitle: String = L10n.tr("common.none")
    @Published private(set) var recentlyTriggeredEventTitles: [String] = []
    @Published private(set) var snoozedEventTitle: String = L10n.tr("common.none")
    @Published private(set) var snoozeUntilDescription: String = L10n.tr("common.none")

    // Centralized services for future dependency injection and testing.
    let authService: AuthService
    let calendarService: CalendarService
    let overlayCoordinator: OverlayCoordinator
    let loginItemManager: LoginItemManager

    private var debugInjectedEvents: [CalendarEvent] = []
    private let autoStartSchedulerOnLaunch: Bool

    lazy var eventScheduler: EventScheduler = {
        let scheduler = EventScheduler(fetchEvents: { [weak self] in
            guard let self else { return [] }

            var combinedEvents: [CalendarEvent] = []

            if self.isAuthenticated {
                let remoteEvents = try await self.calendarService.fetchUpcomingEvents()
                combinedEvents.append(contentsOf: remoteEvents)
            }

            let now = Date()
            self.debugInjectedEvents = self.debugInjectedEvents.filter { $0.endDate > now }
            combinedEvents.append(contentsOf: self.debugInjectedEvents)

            var deduplicatedByID: [String: CalendarEvent] = [:]
            for event in combinedEvents {
                deduplicatedByID[event.id] = event
            }

            return deduplicatedByID.values.sorted(by: { $0.startDate < $1.startDate })
        })

        scheduler.onTrigger = { [weak self] event in
            guard let self else { return }
            self.overlayCoordinator.showOverlay(
                for: event,
                onSnoozeRequested: { [weak self] event in
                    guard let self else { return }
                    self.eventScheduler.snooze(event: event, duration: 120)
                    self.statusMessage = "Overlay snoozed for 2 minutes: \(event.title)"
                }
            )
            self.lastTriggeredEventTitle = event.title
            self.statusMessage = L10n.tr("status.overlay_shown_for", event.title)
        }

        scheduler.onDebugSnapshotChanged = { [weak self] snapshot in
            guard let self else { return }
            self.isMonitoringActive = snapshot.isRunning
            if let refreshError = snapshot.lastRefreshError {
                self.schedulerStatus = L10n.tr("status.active_refresh_error", refreshError)
            } else {
                self.schedulerStatus = snapshot.isRunning ? L10n.tr("status.active") : L10n.tr("status.inactive")
            }
            self.nextTriggerDescription = snapshot.nextTriggerDescription
            self.recentlyTriggeredEventTitles = snapshot.recentTriggeredTitles
            self.snoozedEventTitle = snapshot.snoozedEventTitle ?? L10n.tr("common.none")
            if let snoozeUntil = snapshot.snoozeUntilDate {
                self.snoozeUntilDescription = DateFormatter.localizedString(
                    from: snoozeUntil,
                    dateStyle: .none,
                    timeStyle: .medium
                )
            } else {
                self.snoozeUntilDescription = L10n.tr("common.none")
            }
        }

        return scheduler
    }()

    @MainActor
    init(
        authService: AuthService? = nil,
        calendarService: CalendarService? = nil,
        overlayCoordinator: OverlayCoordinator? = nil,
        loginItemManager: LoginItemManager? = nil,
        autoStartSchedulerOnLaunch: Bool = true
    ) {
        let resolvedAuthService = authService ?? AuthService()
        self.authService = resolvedAuthService
        self.calendarService = calendarService ?? CalendarService(authService: resolvedAuthService)
        self.overlayCoordinator = overlayCoordinator ?? OverlayCoordinator()
        self.loginItemManager = loginItemManager ?? LoginItemManager()
        self.autoStartSchedulerOnLaunch = autoStartSchedulerOnLaunch

        refreshAuthState()
        self.loginItemManager.refreshStatus()
        handleAppLaunch()
        isReady = true
        statusMessage = L10n.tr("status.ready")
    }

    var authButtonTitle: String {
        isAuthenticated ? L10n.tr("action.sign_out") : L10n.tr("action.sign_in")
    }

    var monitoringToggleTitle: String {
        isMonitoringActive ? L10n.tr("action.pause_monitoring") : L10n.tr("action.resume_monitoring")
    }

    var startStopSchedulerTitle: String {
        isMonitoringActive ? L10n.tr("action.stop_scheduler") : L10n.tr("action.start_scheduler")
    }

    func testOverlay(with event: CalendarEvent) {
        overlayCoordinator.showOverlay(
            for: event,
            onSnoozeRequested: { [weak self] event in
                guard let self else { return }
                self.eventScheduler.snooze(event: event, duration: 120)
                self.statusMessage = "Overlay snoozed for 2 minutes: \(event.title)"
            }
        )
        statusMessage = L10n.tr("status.overlay_shown_for", event.title)
    }

    func dismissOverlay() {
        overlayCoordinator.dismissOverlay()
        statusMessage = L10n.tr("status.overlay_dismissed")
    }

    func startScheduler() {
        eventScheduler.start()
        statusMessage = L10n.tr("status.scheduler_started")
    }

    func stopScheduler() {
        eventScheduler.stop()
        statusMessage = L10n.tr("status.scheduler_stopped")
    }

    func toggleMonitoring() {
        if isMonitoringActive {
            stopScheduler()
        } else {
            startScheduler()
        }
    }

    func signOut() {
        authService.signOut()
        refreshAuthState()
        statusMessage = L10n.tr("status.signed_out_keychain_removed")
    }

    func signIn() async {
        do {
            try await authService.signIn()
            refreshAuthState()
            statusMessage = L10n.tr("status.oauth_sign_in_succeeded")
        } catch {
            refreshAuthState()
            statusMessage = L10n.tr("status.auth_failed", error.localizedDescription)
        }
    }

    func triggerTestOverlay() {
        let startDate = Date().addingTimeInterval(90)
        let mockEvent = CalendarEvent(
            id: UUID().uuidString,
            title: L10n.tr("mock.focus_session"),
            startDate: startDate,
            endDate: startDate.addingTimeInterval(1_800),
            videoLink: URL(string: "https://meet.google.com/abc-defg-hij")
        )
        testOverlay(with: mockEvent)
    }

    func injectMockEventIn70Seconds() {
        let startDate = Date().addingTimeInterval(70)
        let event = CalendarEvent(
            id: "debug-\(UUID().uuidString)",
            title: L10n.tr("mock.meeting_70s"),
            startDate: startDate,
            endDate: startDate.addingTimeInterval(1_800),
            videoLink: URL(string: "https://meet.google.com/mock-debug-room"),
            notes: L10n.tr("mock.injected_local_debug_event"),
            location: L10n.tr("mock.local_debug"),
            isAllDay: false
        )

        debugInjectedEvents.append(event)

        Task {
            await eventScheduler.refreshEvents()
        }

        statusMessage = L10n.tr(
            "status.injected_mock_event_for",
            DateFormatter.localizedString(from: startDate, dateStyle: .none, timeStyle: .medium)
        )
    }

    func handleAuthButtonTapped() async {
        if isAuthenticated {
            signOut()
            return
        }

        await signIn()
    }

    func testCalendarFetch() async {
        guard isAuthenticated else {
            fetchedEvents = []
            calendarFetchError = L10n.tr("error.sign_in_with_google_first")
            statusMessage = L10n.tr(
                "status.calendar_fetch_failed",
                calendarFetchError ?? L10n.tr("common.unknown_error")
            )
            return
        }

        isFetchingCalendar = true
        calendarFetchError = nil
        fetchedEvents = []

        defer {
            isFetchingCalendar = false
        }

        do {
            let events = try await calendarService.fetchUpcomingEvents()
            fetchedEvents = events
            statusMessage = L10n.tr("status.calendar_fetch_ok_count", events.count)
        } catch {
            fetchedEvents = []
            calendarFetchError = error.localizedDescription
            statusMessage = L10n.tr("status.calendar_fetch_failed", error.localizedDescription)
        }
    }

    // Helper for future startup/session change hooks.
    func refreshAuthState() {
        authService.restoreSessionFromKeychain()

        isAuthenticated = authService.isSignedIn
        authStatusText = isAuthenticated
            ? L10n.tr("auth.connected_to", authService.connectedAccountDescription)
            : L10n.tr("auth.disconnected")
    }

    private func handleAppLaunch() {
        if autoStartSchedulerOnLaunch {
            startScheduler()
        }
    }
}
