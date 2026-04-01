import Foundation
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var statusMessage: String = L10n.tr("status.initializing")
    @Published private(set) var isReady: Bool = false
    @Published private(set) var authStatusText: String = L10n.tr("auth.disconnected")
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var currentUserEmail: String?
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
    @Published private(set) var pendingBackendMessage: DoNotMissMessageDTO?
    @Published private(set) var currentlyPresentedBackendMessage: DoNotMissMessageDTO?

    // Centralized services for future dependency injection and testing.
    let authService: AuthService
    let calendarService: CalendarService
    let overlayCoordinator: OverlayCoordinator
    let onboardingCoordinator: OnboardingCoordinator
    let onboardingStateStore: OnboardingStateStore
    let weeklyReviewLauncher: WeeklyReviewLauncher
    let weeklyReviewAutomation: WeeklyReviewAutomationController
    let loginItemManager: LoginItemManager
    private let backendClient: DoNotMissBackendClient?

    private var debugInjectedEvents: [CalendarEvent] = []
    private let autoStartSchedulerOnLaunch: Bool
    private var cancellables: Set<AnyCancellable> = []
    private var upsertedEmailsInSession: Set<String> = []
    private var lastUserUpsertAttemptAtByEmail: [String: Date] = [:]
    private var userUpsertInFlightEmail: String?
    private let userUpsertRetryCooldown: TimeInterval = 300
    private var latestMessageFetchedKeys: Set<LatestMessageFetchKey> = []
    private var latestMessageFetchInFlightKeys: Set<LatestMessageFetchKey> = []
    private var latestMessageFetchInFlightEmail: String?
    private var lastLatestMessageFetchAttemptAtByEmail: [String: Date] = [:]
    private var latestMessageFetchGeneration: Int = 0
    private let latestMessageFetchCooldown: TimeInterval = 10
    private let messagePopupCoordinator = MessagePopupCoordinator()
    private let externalURLOpener = ExternalURLOpener()
    private var queuedBackendMessages: [QueuedBackendMessage] = []
    private var queuedBackendMessageIDs: Set<String> = []
    private var shownBackendMessageIDs: Set<String> = []
    private var activeBackendMessageID: String?
    private var activeBackendMessagePresentationToken: UUID?
    private var hasRecordedImpressionForActiveBackendMessage: Bool = false
    private var isHandlingActiveBackendMessageCTA: Bool = false
    private var backendMessageSessionEmail: String?

    private struct BackendMessageEventContext {
        let eventId: String
        let eventStartDate: Date
    }

    private enum LatestMessageFetchKey: Hashable {
        case startingApp
        case event(String)
    }

    private struct QueuedBackendMessage {
        let message: DoNotMissMessageDTO
        let googleEmail: String
        let eventContext: BackendMessageEventContext?
    }

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
                },
                onDidShow: { [weak self] event in
                    guard let self else { return }
                    self.fetchLatestBackendMessageIfNeeded(for: event)
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
        backendClient: DoNotMissBackendClient? = nil,
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
        if let backendClient {
            self.backendClient = backendClient
        } else {
            self.backendClient = try? DoNotMissBackendService()
            if self.backendClient == nil {
                #if DEBUG
                print("[AppState][UserUpsert] Backend client unavailable, user upsert disabled for this session")
                #endif
            }
        }
        self.autoStartSchedulerOnLaunch = autoStartSchedulerOnLaunch
        self.overlayCoordinator.onDidDismiss = { [weak self] in
            self?.presentNextBackendMessageIfPossible()
        }

        self.weeklyReviewLauncher.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.presentNextBackendMessageIfPossible()
            }
            .store(in: &cancellables)

        self.weeklyReviewAutomation.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        self.weeklyReviewAutomation.setStatusMessageHandler { [weak self] message in
            self?.statusMessage = message
            self?.presentNextBackendMessageIfPossible()
        }
        self.weeklyReviewAutomation.setSessionEndedHandler { [weak self] result in
            self?.handleWeeklyReviewSessionEnded(result)
        }

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.presentNextBackendMessageIfPossible()
            }
            .store(in: &cancellables)

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

    func presentLatestBackendMessageForDebug() async {
        guard let backendClient else {
            statusMessage = L10n.tr("settings.debug.backend_message.unavailable")
            return
        }

        guard let email = normalizedCurrentUserEmailForBackendMessageFetch() else {
            statusMessage = L10n.tr("error.sign_in_with_google_first")
            return
        }

        statusMessage = L10n.tr("settings.debug.backend_message.loading")

        do {
            let response = try await backendClient.fetchLatestMessage(
                email: email,
                appVersion: AppVersionProvider.resolved(),
                workflow: .startingApp,
                language: DoNotMissBackendLanguageResolver.resolveCurrentLanguage()
            )
            guard let message = response.message else {
                statusMessage = L10n.tr("settings.debug.backend_message.none")
                return
            }

            enqueueBackendMessage(message, googleEmail: email, allowReplay: true)
            statusMessage = L10n.tr("settings.debug.backend_message.presented")
        } catch {
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

            self.handleWeeklyReviewSessionEnded(result)
            self.presentNextBackendMessageIfPossible()
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

        isAuthenticated = authService.isAuthenticated
        currentUserEmail = authService.currentUserEmail
        authStatusText = isAuthenticated
            ? L10n.tr("auth.connected_to", authService.connectedAccountDescription)
            : L10n.tr("auth.disconnected")

        let normalizedEmail = normalizedCurrentUserEmailForBackendMessageFetch()
        if backendMessageSessionEmail != normalizedEmail {
            let previousEmail = backendMessageSessionEmail
            backendMessageSessionEmail = normalizedEmail
            resetBackendMessageFlowState(
                reason: "Auth context changed (\(maskedEmailForDebug(previousEmail ?? "")) -> \(maskedEmailForDebug(normalizedEmail ?? "")))",
                dismissVisiblePopup: true
            )
        }

        triggerUserUpsertIfNeeded()
    }

    private func handleAppLaunch() {
        if autoStartSchedulerOnLaunch {
            startScheduler()
        }
        weeklyReviewAutomation.start()
        fetchLatestBackendMessageIfNeeded(workflow: .startingApp, dedupeKey: .startingApp)
    }

    private func handleWeeklyReviewSessionEnded(_ result: WeeklyReviewResult) {
        guard case .completed = result.endReason else {
            return
        }

        fetchLatestBackendMessageIfNeeded(workflow: .afterWeeklyReview)
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

    private func triggerUserUpsertIfNeeded() {
        guard isAuthenticated else {
            userUpsertInFlightEmail = nil
            return
        }

        guard let backendClient else {
            return
        }

        guard let email = currentUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              email.isEmpty == false else {
            debugLogUserUpsert("Skip upsert: authenticated user has no email")
            return
        }

        if upsertedEmailsInSession.contains(email) {
            return
        }

        if userUpsertInFlightEmail == email {
            return
        }

        let now = Date()
        if let lastAttemptAt = lastUserUpsertAttemptAtByEmail[email],
           now.timeIntervalSince(lastAttemptAt) < userUpsertRetryCooldown {
            return
        }

        lastUserUpsertAttemptAtByEmail[email] = now
        userUpsertInFlightEmail = email

        Task { [weak self] in
            guard let self else { return }

            do {
                try await backendClient.upsertUser(email: email, name: nil)
                await MainActor.run {
                    self.upsertedEmailsInSession.insert(email)
                    self.userUpsertInFlightEmail = nil
                    self.debugLogUserUpsert("Upsert succeeded for \(email)")
                }
            } catch {
                await MainActor.run {
                    if self.userUpsertInFlightEmail == email {
                        self.userUpsertInFlightEmail = nil
                    }
                    self.debugLogUserUpsert("Upsert failed for \(email): \(error.localizedDescription)")
                }
            }
        }
    }

    private func fetchLatestBackendMessageIfNeeded(for event: CalendarEvent) {
        fetchLatestBackendMessageIfNeeded(
            workflow: .afterEventAlert,
            dedupeKey: .event(event.id),
            contextEvent: event
        )
    }

    private func fetchLatestBackendMessageIfNeeded(
        workflow: DoNotMissMessageWorkflow,
        dedupeKey: LatestMessageFetchKey? = nil,
        contextEvent: CalendarEvent? = nil
    ) {
        guard let backendClient else {
            return
        }

        guard let email = normalizedCurrentUserEmailForBackendMessageFetch() else {
            debugLogLatestMessage("Skip latest message fetch for workflow \(workflow.rawValue): no current user email")
            return
        }

        if let dedupeKey, latestMessageFetchedKeys.contains(dedupeKey) {
            debugLogLatestMessage("Skip latest message fetch for workflow \(workflow.rawValue): already fetched")
            return
        }

        if let dedupeKey, latestMessageFetchInFlightKeys.contains(dedupeKey) {
            debugLogLatestMessage("Skip latest message fetch for workflow \(workflow.rawValue): request already in flight")
            return
        }

        if latestMessageFetchInFlightEmail == email {
            debugLogLatestMessage(
                "Skip latest message fetch for workflow \(workflow.rawValue): request already in flight for \(maskedEmailForDebug(email))"
            )
            return
        }

        let now = Date()
        if let lastAttemptAt = lastLatestMessageFetchAttemptAtByEmail[email],
           now.timeIntervalSince(lastAttemptAt) < latestMessageFetchCooldown {
            debugLogLatestMessage(
                "Skip latest message fetch for workflow \(workflow.rawValue): cooldown active for \(maskedEmailForDebug(email))"
            )
            return
        }

        lastLatestMessageFetchAttemptAtByEmail[email] = now
        if let dedupeKey {
            latestMessageFetchInFlightKeys.insert(dedupeKey)
        }
        latestMessageFetchInFlightEmail = email
        let fetchGeneration = latestMessageFetchGeneration

        Task { [weak self] in
            guard let self else { return }

            do {
                let response = try await backendClient.fetchLatestMessage(
                    email: email,
                    appVersion: AppVersionProvider.resolved(),
                    workflow: workflow,
                    language: DoNotMissBackendLanguageResolver.resolveCurrentLanguage()
                )
                await MainActor.run {
                    if let dedupeKey {
                        self.latestMessageFetchInFlightKeys.remove(dedupeKey)
                    }
                    if self.latestMessageFetchInFlightEmail == email {
                        self.latestMessageFetchInFlightEmail = nil
                    }
                    guard self.latestMessageFetchGeneration == fetchGeneration else {
                        self.debugLogLatestMessage(
                            "Ignored stale latest message response for workflow \(workflow.rawValue)"
                        )
                        return
                    }
                    if let dedupeKey {
                        self.latestMessageFetchedKeys.insert(dedupeKey)
                    }
                    if let message = response.message {
                        self.enqueueBackendMessage(message, googleEmail: email, contextEvent: contextEvent)
                        self.debugLogLatestMessage("Fetched pending message \(message.id) for workflow \(workflow.rawValue)")
                    } else {
                        self.debugLogLatestMessage("No latest message for workflow \(workflow.rawValue)")
                    }
                }
            } catch {
                await MainActor.run {
                    if let dedupeKey {
                        self.latestMessageFetchInFlightKeys.remove(dedupeKey)
                    }
                    if self.latestMessageFetchInFlightEmail == email {
                        self.latestMessageFetchInFlightEmail = nil
                    }
                    guard self.latestMessageFetchGeneration == fetchGeneration else {
                        self.debugLogLatestMessage(
                            "Ignored stale latest message error for workflow \(workflow.rawValue): \(error.localizedDescription)"
                        )
                        return
                    }
                    self.debugLogLatestMessage(
                        "Latest message fetch failed for workflow \(workflow.rawValue): \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func normalizedCurrentUserEmailForBackendMessageFetch() -> String? {
        guard let email = currentUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              email.isEmpty == false else {
            return nil
        }
        return email
    }

    private func enqueueBackendMessage(
        _ message: DoNotMissMessageDTO,
        googleEmail: String? = nil,
        contextEvent: CalendarEvent? = nil,
        allowReplay: Bool = false
    ) {
        if allowReplay == false, shownBackendMessageIDs.contains(message.id) {
            debugLogLatestMessage("Skipped already shown message \(message.id)")
            return
        }

        if allowReplay {
            shownBackendMessageIDs.remove(message.id)
        }

        if queuedBackendMessageIDs.contains(message.id) || activeBackendMessageID == message.id {
            debugLogLatestMessage("Skipped duplicate pending message \(message.id)")
            return
        }

        guard let resolvedGoogleEmail = googleEmail ?? normalizedCurrentUserEmailForBackendMessageFetch() else {
            debugLogLatestMessage("Skipped pending message \(message.id): missing googleEmail for CTA tracking")
            return
        }

        let queuedMessage = QueuedBackendMessage(
            message: message,
            googleEmail: resolvedGoogleEmail,
            eventContext: contextEvent.map {
                BackendMessageEventContext(eventId: $0.id, eventStartDate: $0.startDate)
            }
        )
        queuedBackendMessages.append(queuedMessage)
        queuedBackendMessageIDs.insert(message.id)
        pendingBackendMessage = queuedBackendMessages.first?.message
        debugLogLatestMessage("Enqueued message \(message.id) [queueCount=\(queuedBackendMessages.count)]")
        presentNextBackendMessageIfPossible()
    }

    private func presentNextBackendMessageIfPossible() {
        guard activeBackendMessageID == nil else {
            return
        }

        guard messagePopupCoordinator.isPopupVisible == false else {
            if queuedBackendMessages.isEmpty == false {
                debugLogLatestMessage("Presentation deferred: popup already visible")
            }
            return
        }

        guard overlayCoordinator.isOverlayVisible == false else {
            if queuedBackendMessages.isEmpty == false {
                debugLogLatestMessage("Presentation deferred: overlay visible")
            }
            return
        }

        guard onboardingCoordinator.isOnboardingVisible == false else {
            if queuedBackendMessages.isEmpty == false {
                debugLogLatestMessage("Presentation deferred: onboarding visible")
            }
            return
        }

        guard weeklyReviewLauncher.isReviewActive == false else {
            if queuedBackendMessages.isEmpty == false {
                debugLogLatestMessage("Presentation deferred: weekly review active")
            }
            return
        }

        guard let queuedMessage = queuedBackendMessages.first else {
            pendingBackendMessage = nil
            return
        }

        let message = queuedMessage.message
        let presentationToken = UUID()
        activeBackendMessageID = message.id
        activeBackendMessagePresentationToken = presentationToken
        hasRecordedImpressionForActiveBackendMessage = false
        isHandlingActiveBackendMessageCTA = false
        pendingBackendMessage = message
        currentlyPresentedBackendMessage = message

        let ctaAction = resolvedCTAAction(for: message)
        messagePopupCoordinator.present(
            title: resolvedMessageTitle(for: message),
            bodyText: resolvedMessageBody(for: message),
            ctaLabel: ctaAction?.label,
            onDismiss: { [weak self] in
                self?.handleBackendMessageDismissed()
            },
            onDidShow: { [weak self] in
                self?.handleBackendMessageDidShow(
                    expectedMessageID: message.id,
                    presentationToken: presentationToken,
                    eventContext: queuedMessage.eventContext
                )
            },
            onCTATap: { [weak self] in
                self?.handleBackendMessageCTATapped(for: queuedMessage)
            }
        )
        debugLogLatestMessage("Presenting message \(message.id)")
    }

    private func handleBackendMessageDismissed() {
        guard let activeBackendMessageID else {
            return
        }

        if let firstMessage = queuedBackendMessages.first, firstMessage.message.id == activeBackendMessageID {
            queuedBackendMessages.removeFirst()
        } else {
            queuedBackendMessages.removeAll(where: { $0.message.id == activeBackendMessageID })
        }

        queuedBackendMessageIDs.remove(activeBackendMessageID)
        shownBackendMessageIDs.insert(activeBackendMessageID)
        self.activeBackendMessageID = nil
        activeBackendMessagePresentationToken = nil
        hasRecordedImpressionForActiveBackendMessage = false
        isHandlingActiveBackendMessageCTA = false
        pendingBackendMessage = queuedBackendMessages.first?.message
        currentlyPresentedBackendMessage = nil
        debugLogLatestMessage("Dismissed message \(activeBackendMessageID) [remainingQueue=\(queuedBackendMessages.count)]")
        presentNextBackendMessageIfPossible()
    }

    private func handleBackendMessageCTATapped(for queuedMessage: QueuedBackendMessage) {
        guard isHandlingActiveBackendMessageCTA == false else {
            return
        }

        if let activeBackendMessageID, activeBackendMessageID != queuedMessage.message.id {
            debugLogLatestMessage(
                "CTA tap ignored for message \(queuedMessage.message.id): active message mismatch (\(activeBackendMessageID))"
            )
            return
        }

        let message = queuedMessage.message
        guard let ctaAction = resolvedCTAAction(for: message) else {
            debugLogLatestMessage("CTA tap ignored for message \(message.id): missing or unsupported CTA")
            return
        }

        isHandlingActiveBackendMessageCTA = true
        let openResult = externalURLOpener.open(ctaAction.url)
        switch openResult {
        case .opened:
            recordBackendMessageCTAClick(messageID: message.id, googleEmail: queuedMessage.googleEmail)
            DispatchQueue.main.async { [weak self] in
                self?.messagePopupCoordinator.dismiss()
            }
        case .blockedScheme, .unsupported:
            statusMessage = L10n.tr("message_popup.cta_invalid_url")
            debugLogLatestMessage("CTA URL blocked or unsupported for message \(message.id)")
            isHandlingActiveBackendMessageCTA = false
        case .failed:
            statusMessage = L10n.tr("message_popup.cta_open_failed")
            debugLogLatestMessage("CTA URL failed to open for message \(message.id)")
            isHandlingActiveBackendMessageCTA = false
        }
    }

    private func resolvedMessageTitle(for message: DoNotMissMessageDTO) -> String {
        guard let title = message.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              title.isEmpty == false else {
            return L10n.tr("message_popup.default_title")
        }
        return title
    }

    private func resolvedMessageBody(for message: DoNotMissMessageDTO) -> String {
        guard let body = message.body?.trimmingCharacters(in: .whitespacesAndNewlines),
              body.isEmpty == false else {
            return L10n.tr("message_popup.default_body")
        }
        return body
    }

    private func resolvedCTAAction(for message: DoNotMissMessageDTO) -> (label: String, url: URL)? {
        guard let cta = message.cta,
              let url = cta.url,
              externalURLOpener.canOpen(url) else {
            return nil
        }

        let label = cta.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel: String
        if let label, label.isEmpty == false {
            resolvedLabel = label
        } else {
            resolvedLabel = L10n.tr("message_popup.cta_default")
        }

        return (label: resolvedLabel, url: url)
    }

    private func handleBackendMessageDidShow(
        expectedMessageID: String,
        presentationToken: UUID,
        eventContext: BackendMessageEventContext?
    ) {
        guard activeBackendMessageID == expectedMessageID else {
            return
        }

        guard activeBackendMessagePresentationToken == presentationToken else {
            return
        }

        guard hasRecordedImpressionForActiveBackendMessage == false else {
            return
        }

        hasRecordedImpressionForActiveBackendMessage = true
        recordBackendMessageImpression(messageID: expectedMessageID, eventContext: eventContext)
    }

    private func recordBackendMessageImpression(
        messageID: String,
        eventContext: BackendMessageEventContext?
    ) {
        guard let backendClient else {
            debugLogLatestMessage("Skip impression for message \(messageID): backend client unavailable")
            return
        }

        guard let email = normalizedCurrentUserEmailForBackendMessageFetch() else {
            debugLogLatestMessage("Skip impression for message \(messageID): missing user email")
            return
        }

        let payload = DoNotMissImpressionRequestDTO(
            googleEmail: email,
            appVersion: AppVersionProvider.resolved(),
            contextEventId: eventContext?.eventId,
            contextEventStartAt: eventContext.map { iso8601String(from: $0.eventStartDate) }
        )

        Task {
            do {
                let response = try await backendClient.recordImpression(messageId: messageID, payload: payload)
                await MainActor.run {
                    let statusText = response.status?.rawValue ?? "unknown"
                    self.debugLogLatestMessage("Impression status for message \(messageID): \(statusText)")
                    if response.status == .alreadyRecorded {
                        self.debugLogLatestMessage(
                            "Impression already recorded server-side for message \(messageID) (deduplicated)"
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    self.debugLogLatestMessage(
                        "Failed to record impression for message \(messageID): \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func recordBackendMessageCTAClick(messageID: String, googleEmail: String) {
        guard let backendClient else {
            debugLogLatestMessage("Skip CTA click record for message \(messageID): backend client unavailable")
            return
        }

        debugLogLatestMessage(
            "Sending CTA click for message \(messageID) email=\(maskedEmailForDebug(googleEmail))"
        )

        Task {
            do {
                try await backendClient.recordCTAClick(messageId: messageID, googleEmail: googleEmail)
                await MainActor.run {
                    self.debugLogLatestMessage("CTA click recorded for message \(messageID)")
                }
            } catch {
                await MainActor.run {
                    self.debugLogLatestMessage(
                        "Failed to record CTA click for message \(messageID): \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func debugLogUserUpsert(_ message: String) {
        #if DEBUG
        print("[AppState][UserUpsert] \(message)")
        #endif
    }

    private func debugLogLatestMessage(_ message: String) {
        #if DEBUG
        print("[AppState][LatestMessage] \(message)")
        #endif
    }

    private func resetBackendMessageFlowState(reason: String, dismissVisiblePopup: Bool) {
        latestMessageFetchGeneration += 1
        latestMessageFetchedKeys.removeAll()
        latestMessageFetchInFlightKeys.removeAll()
        latestMessageFetchInFlightEmail = nil
        lastLatestMessageFetchAttemptAtByEmail.removeAll()
        queuedBackendMessages.removeAll()
        queuedBackendMessageIDs.removeAll()
        shownBackendMessageIDs.removeAll()
        activeBackendMessageID = nil
        activeBackendMessagePresentationToken = nil
        hasRecordedImpressionForActiveBackendMessage = false
        isHandlingActiveBackendMessageCTA = false
        pendingBackendMessage = nil
        currentlyPresentedBackendMessage = nil

        if dismissVisiblePopup, messagePopupCoordinator.isPopupVisible {
            messagePopupCoordinator.dismiss()
        }

        debugLogLatestMessage("Flow state reset: \(reason)")
    }

    private func maskedEmailForDebug(_ email: String) -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let atIndex = trimmed.firstIndex(of: "@") else {
            return "***"
        }

        let localPart = String(trimmed[..<atIndex])
        let domainPart = String(trimmed[atIndex...])
        let visiblePrefix = localPart.prefix(2)
        return "\(visiblePrefix)***\(domainPart)"
    }
}
