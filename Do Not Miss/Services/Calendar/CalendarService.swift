import Foundation

enum CalendarServiceError: LocalizedError {
    case notAuthenticated
    case invalidRequestURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case invalidPayload
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return L10n.tr("error.sign_in_with_google_before_fetching")
        case .invalidRequestURL:
            return L10n.tr("calendar.error.invalid_request_url")
        case .invalidResponse:
            return L10n.tr("calendar.error.invalid_response")
        case .httpError(let statusCode, let message):
            if let message, message.isEmpty == false {
                return L10n.tr("calendar.error.http_with_message", statusCode, message)
            }
            return L10n.tr("calendar.error.http_without_message", statusCode)
        case .invalidPayload:
            return L10n.tr("calendar.error.invalid_payload")
        case .networkError(let details):
            return L10n.tr("error.network_with_details", details)
        }
    }
}

@MainActor
final class CalendarService {
    private let authService: AuthService
    private let urlSession: URLSession
    private let videoLinkExtractor = VideoLinkExtractor()

    init(
        authService: AuthService,
        urlSession: URLSession = .shared
    ) {
        self.authService = authService
        self.urlSession = urlSession
    }

    func fetchUpcomingEvents() async throws -> [CalendarEvent] {
        let accessToken = try await validAccessToken()
        let request = try makeUpcomingEventsRequest(accessToken: accessToken)
        let now = Date()

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CalendarServiceError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let serverMessage = decodeServerMessage(from: data)
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw CalendarServiceError.notAuthenticated
                }
                throw CalendarServiceError.httpError(statusCode: httpResponse.statusCode, message: serverMessage)
            }

            let decoder = JSONDecoder()
            guard let payload = try? decoder.decode(GoogleCalendarEventsResponse.self, from: data) else {
                throw CalendarServiceError.invalidPayload
            }

            let calendarTimeZone = payload.timeZone.flatMap(TimeZone.init(identifier:))
            let mappedEvents = payload.items.compactMap { eventItem in
                mapGoogleEvent(eventItem, calendarTimeZone: calendarTimeZone)
            }

            return mappedEvents
                .filter { $0.endDate > now }
                .sorted { $0.startDate < $1.startDate }
        } catch {
            if error is CancellationError || error is CalendarServiceError {
                throw error
            }

            throw CalendarServiceError.networkError(error.localizedDescription)
        }
    }
}

private extension CalendarService {
    func validAccessToken() async throws -> String {
        do {
            return try await authService.getValidAccessToken()
        } catch let authError as AuthServiceError {
            switch authError {
            case .noStoredSession, .accessTokenExpiredWithoutRefreshToken:
                throw CalendarServiceError.notAuthenticated
            default:
                throw CalendarServiceError.networkError(authError.localizedDescription)
            }
        } catch {
            throw CalendarServiceError.networkError(error.localizedDescription)
        }
    }

    func makeUpcomingEventsRequest(accessToken: String) throws -> URLRequest {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")
        components?.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "timeMin", value: nowAsRFC3339String()),
            URLQueryItem(name: "maxResults", value: "50")
        ]

        guard let url = components?.url else {
            throw CalendarServiceError.invalidRequestURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        return request
    }

    func nowAsRFC3339String() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    func decodeServerMessage(from data: Data) -> String? {
        if let envelope = try? JSONDecoder().decode(GoogleCalendarErrorEnvelope.self, from: data) {
            return envelope.error.message
        }
        return nil
    }

    func mapGoogleEvent(
        _ item: GoogleCalendarEventItem,
        calendarTimeZone: TimeZone?
    ) -> CalendarEvent? {
        guard let start = item.start else {
            return nil
        }

        let startTimeZone = start.timeZone.flatMap(TimeZone.init(identifier:)) ?? calendarTimeZone
        let endTimeZone = item.end?.timeZone.flatMap(TimeZone.init(identifier:)) ?? calendarTimeZone

        let parsedStartDateTime = GoogleCalendarDateParser.parseDateTime(start.dateTime)
        let parsedStartAllDay = GoogleCalendarDateParser.parseAllDayDate(start.date, in: startTimeZone)

        guard let startDate = parsedStartDateTime ?? parsedStartAllDay else {
            return nil
        }

        let isAllDay = start.date != nil && parsedStartDateTime == nil

        let parsedEndDateTime = GoogleCalendarDateParser.parseDateTime(item.end?.dateTime)
        let parsedEndAllDay = GoogleCalendarDateParser.parseAllDayDate(item.end?.date, in: endTimeZone)

        let endDate: Date
        if let parsedEndDateTime {
            endDate = parsedEndDateTime
        } else if let parsedEndAllDay {
            // For all-day events Google returns an exclusive end date.
            endDate = parsedEndAllDay
        } else if isAllDay {
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        } else {
            endDate = startDate
        }

        let resolvedVideoMatch = videoLinkExtractor.extractBestVideoLink(from: item)

        let normalizedSummary = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventTitle = normalizedSummary.flatMap { $0.isEmpty ? nil : $0 } ?? L10n.tr("event.untitled")
        let organizerName = nonEmptyTrimmed(item.organizer?.displayName)
        let organizerEmail = normalizedEmail(item.organizer?.email)
        let attendees = mapAttendees(item.attendees)
        let isUserOrganizer = resolveIsUserOrganizer(
            item: item,
            organizerEmail: organizerEmail,
            attendees: attendees
        )

        return CalendarEvent(
            id: item.id ?? UUID().uuidString,
            title: eventTitle,
            startDate: startDate,
            endDate: endDate,
            videoLink: resolvedVideoMatch?.url,
            videoProvider: resolvedVideoMatch?.provider.rawValue,
            notes: item.description,
            location: item.location,
            isAllDay: isAllDay,
            organizerName: organizerName,
            organizerEmail: organizerEmail,
            attendees: attendees,
            isUserOrganizer: isUserOrganizer
        )
    }

    func mapAttendees(_ rawAttendees: [GoogleCalendarAttendee]?) -> [EventAttendee] {
        guard let rawAttendees else {
            return []
        }

        var deduplicated: [String: EventAttendee] = [:]

        for attendee in rawAttendees {
            guard let normalizedEmail = normalizedEmail(attendee.email) else {
                continue
            }

            let key = normalizedEmail.lowercased()
            let mappedAttendee = EventAttendee(
                name: nonEmptyTrimmed(attendee.displayName),
                email: normalizedEmail,
                responseStatus: nonEmptyTrimmed(attendee.responseStatus),
                isOrganizer: attendee.organizer ?? false,
                isSelf: attendee.selfValue ?? false
            )

            if let existing = deduplicated[key] {
                deduplicated[key] = mergeAttendee(existing: existing, incoming: mappedAttendee)
            } else {
                deduplicated[key] = mappedAttendee
            }
        }

        return deduplicated.values.sorted { $0.email.localizedCaseInsensitiveCompare($1.email) == .orderedAscending }
    }

    func mergeAttendee(existing: EventAttendee, incoming: EventAttendee) -> EventAttendee {
        EventAttendee(
            name: existing.name ?? incoming.name,
            email: existing.email,
            responseStatus: existing.responseStatus ?? incoming.responseStatus,
            isOrganizer: existing.isOrganizer || incoming.isOrganizer,
            isSelf: existing.isSelf || incoming.isSelf
        )
    }

    func resolveIsUserOrganizer(
        item: GoogleCalendarEventItem,
        organizerEmail: String?,
        attendees: [EventAttendee]
    ) -> Bool {
        if item.organizer?.selfValue == true || item.creator?.selfValue == true {
            return true
        }

        if attendees.contains(where: { $0.isSelf && $0.isOrganizer }) {
            return true
        }

        guard let organizerEmail else {
            return false
        }

        return attendees.contains {
            $0.isSelf && $0.email.caseInsensitiveCompare(organizerEmail) == .orderedSame
        }
    }

    func nonEmptyTrimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    func normalizedEmail(_ value: String?) -> String? {
        guard let trimmed = nonEmptyTrimmed(value) else {
            return nil
        }
        return trimmed.lowercased()
    }
}
