import Foundation
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var statusMessage: String = L10n.tr("status.initializing")
    @Published private(set) var isReady: Bool = false
    @Published private(set) var authStatusText: String = L10n.tr("auth.disconnected")
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var isFetchingCalendar: Bool = false
    @Published private(set) var fetchedEvents: [CalendarEvent] = []
    @Published private(set) var reviewableEvents: [CalendarEvent] = []
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
    let onboardingCoordinator: OnboardingCoordinator
    let onboardingStateStore: OnboardingStateStore
    let weeklyReviewLauncher: WeeklyReviewLauncher
    let weeklyReviewAutomation: WeeklyReviewAutomationController
    let loginItemManager: LoginItemManager

    private var debugInjectedEvents: [CalendarEvent] = []
    private let autoStartSchedulerOnLaunch: Bool
    private var cancellables: Set<AnyCancellable> = []

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
                    self.statusMessage = L10n.tr("status.overlay_snoozed_for", event.title)
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
        onboardingCoordinator: OnboardingCoordinator? = nil,
        onboardingStateStore: OnboardingStateStore? = nil,
        weeklyReviewCoordinator: WeeklyReviewCoordinator? = nil,
        weeklyReviewLauncher: WeeklyReviewLauncher? = nil,
        loginItemManager: LoginItemManager? = nil,
        preferencesStore: PreferencesStore? = nil,
        autoStartSchedulerOnLaunch: Bool = true
    ) {
        let resolvedAuthService = authService ?? AuthService()
        let resolvedCalendarService = calendarService ?? CalendarService(authService: resolvedAuthService)
        let resolvedWeeklyReviewCoordinator = weeklyReviewCoordinator ?? WeeklyReviewCoordinator()
        let resolvedWeeklyReviewLauncher = weeklyReviewLauncher
            ?? WeeklyReviewLauncher(
                authService: resolvedAuthService,
                calendarService: resolvedCalendarService,
                coordinator: resolvedWeeklyReviewCoordinator
            )
        let resolvedOnboardingStateStore = onboardingStateStore ?? OnboardingStateStore()
        let resolvedPreferencesStore = preferencesStore ?? PreferencesStore()

        self.authService = resolvedAuthService
        self.calendarService = resolvedCalendarService
        self.overlayCoordinator = overlayCoordinator ?? OverlayCoordinator()
        self.onboardingStateStore = resolvedOnboardingStateStore
        self.onboardingCoordinator = onboardingCoordinator
            ?? OnboardingCoordinator(
                onboardingStateStore: resolvedOnboardingStateStore,
                authService: resolvedAuthService
            )
        self.weeklyReviewLauncher = resolvedWeeklyReviewLauncher
        self.weeklyReviewAutomation = WeeklyReviewAutomationController(
            preferencesStore: resolvedPreferencesStore,
            weeklyReviewLauncher: resolvedWeeklyReviewLauncher
        )
        self.loginItemManager = loginItemManager ?? LoginItemManager()
        self.autoStartSchedulerOnLaunch = autoStartSchedulerOnLaunch

        self.weeklyReviewLauncher.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        self.weeklyReviewAutomation.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        self.weeklyReviewAutomation.setStatusMessageHandler { [weak self] message in
            self?.statusMessage = message
        }

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

    var isLaunchingWeeklyReview: Bool {
        weeklyReviewLauncher.isLaunching
    }

    var weeklyReviewLaunchError: String? {
        weeklyReviewLauncher.launchError
    }

    func testOverlay(with event: CalendarEvent) {
        overlayCoordinator.showOverlay(
            for: event,
            onSnoozeRequested: { [weak self] event in
                guard let self else { return }
                self.eventScheduler.snooze(event: event, duration: 120)
                self.statusMessage = L10n.tr("status.overlay_snoozed_for", event.title)
            }
        )
        statusMessage = L10n.tr("status.overlay_shown_for", event.title)
    }

    func dismissOverlay() {
        overlayCoordinator.dismissOverlay()
        statusMessage = L10n.tr("status.overlay_dismissed")
    }

    func showOnboardingIfNeeded() {
        guard onboardingStateStore.hasCompleted == false else {
            return
        }
        onboardingCoordinator.showOnboarding(
            onGoogleConnected: { [weak self] in
                guard let self else { return }
                handleGoogleAuthSucceeded()
            },
            onGoogleConnectionFailed: { [weak self] errorMessage in
                guard let self else { return }
                handleGoogleAuthFailed(errorMessage)
            }
        )
    }

    func relaunchOnboarding() {
        onboardingCoordinator.showOnboarding(
            onGoogleConnected: { [weak self] in
                guard let self else { return }
                handleGoogleAuthSucceeded()
            },
            onGoogleConnectionFailed: { [weak self] errorMessage in
                guard let self else { return }
                handleGoogleAuthFailed(errorMessage)
            }
        )
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
            handleGoogleAuthSucceeded()
        } catch {
            handleGoogleAuthFailed(error.localizedDescription)
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
            reviewableEvents = []
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
        reviewableEvents = []

        defer {
            isFetchingCalendar = false
        }

        do {
            let events = try await calendarService.fetchUpcomingEvents()
            fetchedEvents = events
            statusMessage = L10n.tr("status.calendar_fetch_ok_count", events.count)
        } catch {
            fetchedEvents = []
            reviewableEvents = []
            calendarFetchError = error.localizedDescription
            statusMessage = L10n.tr("status.calendar_fetch_failed", error.localizedDescription)
        }
    }

    func fetchReviewableEventsForDebug() async {
        guard isAuthenticated else {
            reviewableEvents = []
            calendarFetchError = L10n.tr("error.sign_in_with_google_first")
            statusMessage = L10n.tr(
                "status.calendar_fetch_failed",
                calendarFetchError ?? L10n.tr("common.unknown_error")
            )
            return
        }

        isFetchingCalendar = true
        calendarFetchError = nil
        reviewableEvents = []

        defer {
            isFetchingCalendar = false
        }

        do {
            let events = try await calendarService.fetchReviewableEventsForUpcomingWeek()
            reviewableEvents = events
            statusMessage = L10n.tr("status.reviewable_fetch_ok_count", events.count)
        } catch {
            reviewableEvents = []
            calendarFetchError = error.localizedDescription
            statusMessage = L10n.tr("status.calendar_fetch_failed", error.localizedDescription)
        }
    }

    func startWeeklyReviewManually() async {
        let launchOutcome = await weeklyReviewLauncher.startReview { [weak self] result in
            guard let self else {
                return
            }

            let decidedCount = result.acceptedCount + result.declinedCount + result.tentativeCount
            switch result.endReason {
            case .completed:
                self.statusMessage = L10n.tr(
                    "status.weekly_review_completed_counts_with_sync",
                    result.acceptedCount,
                    result.declinedCount,
                    result.tentativeCount,
                    result.successfulSubmissionCount,
                    result.failedSubmissionCount
                )
            case .cancelled:
                self.statusMessage = L10n.tr(
                    "status.weekly_review_cancelled_progress",
                    decidedCount,
                    result.totalEvents
                )
            }
        }

        switch launchOutcome {
        case .alreadyLaunching:
            statusMessage = L10n.tr("status.weekly_review_loading")
        case .alreadyActive:
            statusMessage = L10n.tr("status.weekly_review_already_active")
        case .notAuthenticated(let errorMessage):
            reviewableEvents = []
            calendarFetchError = errorMessage
            statusMessage = L10n.tr("status.calendar_fetch_failed", errorMessage)
        case .failed(let errorMessage):
            reviewableEvents = []
            calendarFetchError = errorMessage
            statusMessage = L10n.tr("status.calendar_fetch_failed", errorMessage)
        case .noReviewableEvents:
            reviewableEvents = []
            calendarFetchError = nil
            statusMessage = L10n.tr("status.weekly_review_no_reviewable_events")
        case .started(let events):
            reviewableEvents = events
            calendarFetchError = nil
            statusMessage = L10n.tr("status.weekly_review_started_count", events.count)
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
        weeklyReviewAutomation.start()
    }

    private func handleGoogleAuthSucceeded() {
        refreshAuthState()
        statusMessage = L10n.tr("status.oauth_sign_in_succeeded")

        Task { @MainActor in
            await presentAuthSuccessFeedback()
        }
    }

    private func handleGoogleAuthFailed(_ errorMessage: String) {
        refreshAuthState()
        statusMessage = L10n.tr("status.auth_failed", errorMessage)
    }

    private func presentAuthSuccessFeedback() async {
        guard isAuthenticated else {
            return
        }

        let nextEvent = await fetchNextEventForAuthFeedback()
        let informativeText: String

        if let nextEvent {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .full
            let relativeTime = relativeFormatter.localizedString(for: nextEvent.startDate, relativeTo: Date())
            informativeText = L10n.tr(
                "auth.success.feedback.body.next_event",
                relativeTime,
                nextEvent.title
            )
        } else {
            informativeText = L10n.tr("auth.success.feedback.body.no_event")
        }

        let alert = NSAlert()
        alert.messageText = L10n.tr("auth.success.feedback.title")
        alert.informativeText = informativeText
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("auth.success.feedback.button"))

        if let checkImage = NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: nil
        ) {
            checkImage.size = NSSize(width: 40, height: 40)
            alert.icon = checkImage
        }

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func fetchNextEventForAuthFeedback() async -> CalendarEvent? {
        guard isAuthenticated else {
            return nil
        }

        return await withTaskGroup(of: CalendarEvent?.self) { group in
            group.addTask { [weak self] in
                guard let self else {
                    return nil
                }

                guard let events = try? await self.calendarService.fetchUpcomingEvents() else {
                    return nil
                }

                let now = Date()
                return events.first(where: { $0.startDate > now })
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                return nil
            }

            let firstCompleted = await group.next() ?? nil
            group.cancelAll()
            return firstCompleted
        }
    }
}
