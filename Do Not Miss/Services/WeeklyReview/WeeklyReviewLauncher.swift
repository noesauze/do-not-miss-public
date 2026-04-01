import Foundation
import Combine

enum WeeklyReviewLaunchOutcome {
    case started([CalendarEvent])
    case noReviewableEvents
    case alreadyActive
    case alreadyLaunching
    case notAuthenticated(String)
    case failed(String)
}

@MainActor
final class WeeklyReviewLauncher: ObservableObject {
    @Published private(set) var isLaunching: Bool = false
    @Published private(set) var launchError: String?

    private let authService: AuthService
    private let calendarService: CalendarService
    private let coordinator: WeeklyReviewCoordinator
    private var launchRequestID: UUID?

    var isReviewActive: Bool {
        coordinator.isReviewActive
    }

    init(
        authService: AuthService,
        calendarService: CalendarService,
        coordinator: WeeklyReviewCoordinator
    ) {
        self.authService = authService
        self.calendarService = calendarService
        self.coordinator = coordinator
    }

    func startReview(
        startWhenEmpty: Bool = true,
        onSessionEnded: @escaping (WeeklyReviewResult) -> Void
    ) async -> WeeklyReviewLaunchOutcome {
        log("Launch requested")

        guard isLaunching == false else {
            log("Ignored: launch already in progress")
            return .alreadyLaunching
        }

        if coordinator.isReviewActive {
            log("Review already active, bringing window to front")
            _ = coordinator.bringToFront()
            return .alreadyActive
        }

        guard authService.isSignedIn else {
            let message = L10n.tr("error.sign_in_with_google_first")
            launchError = message
            log("Blocked: user not authenticated")
            return .notAuthenticated(message)
        }

        let requestID = UUID()
        launchRequestID = requestID
        isLaunching = true
        launchError = nil
        log("Fetch start [request: \(requestID.uuidString)]")

        defer {
            if launchRequestID == requestID {
                isLaunching = false
                launchRequestID = nil
            }
            log("Launch flow ended [request: \(requestID.uuidString)]")
        }

        do {
            let events = try await fetchReviewableEventsWithTimeout(seconds: 15)
            log("Fetch finished [request: \(requestID.uuidString)] with \(events.count) event(s)")

            if events.isEmpty, startWhenEmpty == false {
                log("Launch skipped: no reviewable event to display [request: \(requestID.uuidString)]")
                return .noReviewableEvents
            }

            coordinator.startReview(
                events: events,
                calendarService: calendarService,
                onSessionEnded: onSessionEnded
            )
            log("Review window started [request: \(requestID.uuidString)]")
            return .started(events)
        } catch {
            let message = error.localizedDescription
            launchError = message
            log("Launch failed [request: \(requestID.uuidString)] error: \(message)")
            return .failed(message)
        }
    }

    private func fetchReviewableEventsWithTimeout(seconds: TimeInterval) async throws -> [CalendarEvent] {
        try await withThrowingTaskGroup(of: [CalendarEvent].self) { group in
            group.addTask { [calendarService] in
                try await calendarService.fetchReviewableEventsForUpcomingWeek()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw WeeklyReviewLaunchError.fetchTimedOut
            }

            guard let firstResult = try await group.next() else {
                group.cancelAll()
                throw WeeklyReviewLaunchError.fetchFailedWithoutResult
            }

            group.cancelAll()
            return firstResult
        }
    }

    private func log(_ message: String) {
        print("[WeeklyReview][Launcher] \(message)")
    }
}

private enum WeeklyReviewLaunchError: LocalizedError {
    case fetchTimedOut
    case fetchFailedWithoutResult

    var errorDescription: String? {
        switch self {
        case .fetchTimedOut:
            return L10n.tr("weekly_review.error.fetch_timeout")
        case .fetchFailedWithoutResult:
            return L10n.tr("weekly_review.error.fetch_empty_result")
        }
    }
}
