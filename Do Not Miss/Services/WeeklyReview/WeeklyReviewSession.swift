import Foundation
import Combine

enum WeeklyReviewDecision: String, CaseIterable {
    case accept
    case decline
    case tentative

    var localizedLabel: String {
        switch self {
        case .accept:
            return L10n.tr("weekly_review.decision.accept")
        case .decline:
            return L10n.tr("weekly_review.decision.decline")
        case .tentative:
            return L10n.tr("weekly_review.decision.tentative")
        }
    }

    var eventResponseStatus: EventResponseStatus {
        switch self {
        case .accept:
            return .accepted
        case .decline:
            return .declined
        case .tentative:
            return .tentative
        }
    }
}

enum WeeklyReviewEndReason {
    case completed
    case cancelled
}

struct WeeklyReviewResult {
    let totalEvents: Int
    let acceptedCount: Int
    let declinedCount: Int
    let tentativeCount: Int
    let successfulSubmissionCount: Int
    let failedSubmissionCount: Int
    let failedEvents: [WeeklyReviewFailedEvent]
    let endReason: WeeklyReviewEndReason
}

struct WeeklyReviewFailedEvent: Identifiable {
    var id: String { eventID }
    let eventID: String
    let eventTitle: String
    let attemptedDecision: WeeklyReviewDecision
    let errorMessage: String
}

struct WeeklyReviewLastAction {
    enum Kind {
        case submitted(
            previousResponseStatus: EventResponseStatus,
            decision: WeeklyReviewDecision
        )
        case failedSubmission(
            decision: WeeklyReviewDecision
        )
    }

    let eventID: String
    let eventTitle: String
    let eventIndex: Int
    let kind: Kind
}

enum WeeklyReviewUndoError: LocalizedError {
    case noActionToUndo
    case unsupportedPreviousStatus

    var errorDescription: String? {
        switch self {
        case .noActionToUndo:
            return L10n.tr("weekly_review.undo.error.no_action")
        case .unsupportedPreviousStatus:
            return L10n.tr("weekly_review.undo.error.unsupported_previous_status")
        }
    }
}

@MainActor
final class WeeklyReviewSession: ObservableObject {
    @Published private(set) var events: [CalendarEvent]

    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var decisionsByEventID: [String: WeeklyReviewDecision] = [:]
    @Published private(set) var failedEventsByID: [String: WeeklyReviewFailedEvent] = [:]
    @Published private(set) var successfulEventIDs: Set<String> = []
    @Published private(set) var lastAction: WeeklyReviewLastAction?

    private let calendarService: CalendarService

    init(events: [CalendarEvent], calendarService: CalendarService) {
        self.events = events
        self.calendarService = calendarService
    }

    var currentEvent: CalendarEvent? {
        guard currentIndex < events.count else {
            return nil
        }
        return events[currentIndex]
    }

    var nextEvent: CalendarEvent? {
        let nextIndex = currentIndex + 1
        guard nextIndex < events.count else {
            return nil
        }
        return events[nextIndex]
    }

    var isEmpty: Bool {
        events.isEmpty
    }

    var isCompleted: Bool {
        events.isEmpty == false && currentIndex >= events.count
    }

    var progressText: String {
        guard events.isEmpty == false else {
            return L10n.tr("weekly_review.progress.empty")
        }

        if isCompleted {
            return L10n.tr("weekly_review.progress.complete", events.count, events.count)
        }

        return L10n.tr("weekly_review.progress.value", currentIndex + 1, events.count)
    }

    var acceptedCount: Int {
        decisionsByEventID.values.filter { $0 == .accept }.count
    }

    var declinedCount: Int {
        decisionsByEventID.values.filter { $0 == .decline }.count
    }

    var tentativeCount: Int {
        decisionsByEventID.values.filter { $0 == .tentative }.count
    }

    var successfulSubmissionCount: Int {
        successfulEventIDs.count
    }

    var failedSubmissionCount: Int {
        failedEventsByID.count
    }

    var submissionAttemptCount: Int {
        successfulSubmissionCount + failedSubmissionCount
    }

    var processedEventCount: Int {
        min(currentIndex, events.count)
    }

    var decidedEventCount: Int {
        acceptedCount + declinedCount + tentativeCount
    }

    var canUndoLastAction: Bool {
        lastAction != nil
    }

    var failedEvents: [WeeklyReviewFailedEvent] {
        failedEventsByID.values.sorted {
            $0.eventTitle.localizedCaseInsensitiveCompare($1.eventTitle) == .orderedAscending
        }
    }

    func submitCurrentDecision(_ decision: WeeklyReviewDecision) async throws {
        guard currentIndex < events.count else {
            return
        }

        let currentEventSnapshot = events[currentIndex]
        let previousResponseStatus = currentEventSnapshot.userResponseStatus
        try await calendarService.updateResponseStatus(
            for: currentEventSnapshot,
            to: decision.eventResponseStatus
        )

        events[currentIndex] = updatedEvent(
            currentEventSnapshot,
            withResponseStatus: decision.eventResponseStatus
        )

        failedEventsByID.removeValue(forKey: currentEventSnapshot.id)
        successfulEventIDs.insert(currentEventSnapshot.id)

        let event = events[currentIndex]
        decisionsByEventID[event.id] = decision
        lastAction = WeeklyReviewLastAction(
            eventID: event.id,
            eventTitle: event.title,
            eventIndex: currentIndex,
            kind: .submitted(
                previousResponseStatus: previousResponseStatus,
                decision: decision
            )
        )
        currentIndex += 1
    }

    func recordSubmissionFailure(
        for event: CalendarEvent,
        decision: WeeklyReviewDecision,
        errorMessage: String
    ) {
        let failedEvent = WeeklyReviewFailedEvent(
            eventID: event.id,
            eventTitle: event.title,
            attemptedDecision: decision,
            errorMessage: errorMessage
        )
        failedEventsByID[event.id] = failedEvent
        lastAction = WeeklyReviewLastAction(
            eventID: event.id,
            eventTitle: event.title,
            eventIndex: currentIndex,
            kind: .failedSubmission(decision: decision)
        )
    }

    func skipCurrentEventAfterFailure() {
        guard let event = currentEvent else {
            return
        }

        if failedEventsByID[event.id] == nil {
            failedEventsByID[event.id] = WeeklyReviewFailedEvent(
                eventID: event.id,
                eventTitle: event.title,
                attemptedDecision: .tentative,
                errorMessage: L10n.tr("weekly_review.error.skipped_without_submission")
            )
        }

        currentIndex += 1
        lastAction = nil
    }

    func buildResult(endReason: WeeklyReviewEndReason) -> WeeklyReviewResult {
        WeeklyReviewResult(
            totalEvents: events.count,
            acceptedCount: acceptedCount,
            declinedCount: declinedCount,
            tentativeCount: tentativeCount,
            successfulSubmissionCount: successfulSubmissionCount,
            failedSubmissionCount: failedSubmissionCount,
            failedEvents: failedEvents,
            endReason: endReason
        )
    }

    func restartReviewFromBeginning() {
        currentIndex = 0
        decisionsByEventID = [:]
        failedEventsByID = [:]
        successfulEventIDs = []
        lastAction = nil
    }

    func undoLastAction() async throws {
        guard let lastAction else {
            throw WeeklyReviewUndoError.noActionToUndo
        }

        switch lastAction.kind {
        case .failedSubmission:
            failedEventsByID.removeValue(forKey: lastAction.eventID)
            self.lastAction = nil
        case .submitted(let previousResponseStatus, _):
            guard let targetStatus = undoTargetStatus(from: previousResponseStatus) else {
                throw WeeklyReviewUndoError.unsupportedPreviousStatus
            }

            guard events.indices.contains(lastAction.eventIndex) else {
                throw WeeklyReviewUndoError.noActionToUndo
            }

            let currentEventSnapshot = events[lastAction.eventIndex]
            try await calendarService.updateResponseStatus(
                for: currentEventSnapshot,
                to: targetStatus
            )

            events[lastAction.eventIndex] = updatedEvent(
                currentEventSnapshot,
                withResponseStatus: targetStatus
            )

            successfulEventIDs.remove(lastAction.eventID)
            failedEventsByID.removeValue(forKey: lastAction.eventID)
            decisionsByEventID.removeValue(forKey: lastAction.eventID)
            currentIndex = lastAction.eventIndex
            self.lastAction = nil
        }
    }
}

private extension WeeklyReviewSession {
    func undoTargetStatus(from status: EventResponseStatus) -> EventResponseStatus? {
        switch status {
        case .accepted, .declined, .tentative, .needsAction:
            return status
        case .unknown:
            return nil
        }
    }

    func updatedEvent(
        _ event: CalendarEvent,
        withResponseStatus responseStatus: EventResponseStatus
    ) -> CalendarEvent {
        let currentUserEmail = normalizedEmail(calendarService.authenticatedAccountEmail)

        let updatedAttendees = event.attendees.map { attendee in
            let isCurrentUserByEmail = currentUserEmail.map {
                attendee.email.caseInsensitiveCompare($0) == .orderedSame
            } ?? false
            let shouldUpdate = attendee.isSelf || isCurrentUserByEmail

            return EventAttendee(
                name: attendee.name,
                email: attendee.email,
                responseStatus: shouldUpdate ? responseStatus.rawValue : attendee.responseStatus,
                isOrganizer: attendee.isOrganizer,
                isSelf: attendee.isSelf
            )
        }

        return CalendarEvent(
            id: event.id,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            videoLink: event.videoLink,
            videoProvider: event.videoProvider,
            notes: event.notes,
            location: event.location,
            isAllDay: event.isAllDay,
            organizerName: event.organizerName,
            organizerEmail: event.organizerEmail,
            attendees: updatedAttendees,
            isUserOrganizer: event.isUserOrganizer,
            userResponseStatus: responseStatus
        )
    }

    func normalizedEmail(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        return trimmed.lowercased()
    }
}
