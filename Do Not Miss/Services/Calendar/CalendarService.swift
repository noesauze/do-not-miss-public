import Foundation

enum CalendarServiceError: LocalizedError {
    case notAuthenticated
    case invalidRequestURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case invalidPayload
    case attendeeSelfNotFound
    case organizerEventResponseNotSupported
    case eventNotFound
    case insufficientPermissions
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
        case .attendeeSelfNotFound:
            return L10n.tr("calendar.error.attendee_self_not_found")
        case .organizerEventResponseNotSupported:
            return L10n.tr("calendar.error.organizer_event_response_not_supported")
        case .eventNotFound:
            return L10n.tr("calendar.error.event_not_found")
        case .insufficientPermissions:
            return L10n.tr("calendar.error.insufficient_permissions")
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

    var authenticatedAccountEmail: String? {
        authService.currentSession?.accountEmail
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

            return transformEvents(from: payload, now: now)
        } catch {
            if error is CancellationError || error is CalendarServiceError {
                throw error
            }

            throw CalendarServiceError.networkError(error.localizedDescription)
        }
    }

    func fetchReviewableEventsForUpcomingWeek() async throws -> [CalendarEvent] {
        let now = Date()
        let endBoundary = Calendar.current.date(byAdding: .day, value: 7, to: now)
            ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        let upcomingEvents = try await fetchUpcomingEvents()

        return upcomingEvents
            .filter { event in
                event.startDate >= now
                    && event.startDate <= endBoundary
                    && event.isReviewableInvitation
            }
            .sorted(by: { $0.startDate < $1.startDate })
    }

    func updateResponseStatus(
        for event: CalendarEvent,
        to status: EventResponseStatus
    ) async throws {
        guard status == .accepted
            || status == .declined
            || status == .tentative
            || status == .needsAction else {
            throw CalendarServiceError.invalidPayload
        }

        let accessToken = try await validAccessToken()
        let attendeeEmail = try resolveCurrentUserAttendeeEmail(for: event)
        let request = try makeResponseStatusUpdateRequest(
            eventID: event.id,
            attendeeEmail: attendeeEmail,
            status: status,
            accessToken: accessToken
        )

        do {
            let (data, response) = try await performRequestWithRetry(request)

            guard (200...299).contains(response.statusCode) else {
                let serverMessage = decodeServerMessage(from: data)

                switch response.statusCode {
                case 401:
                    throw CalendarServiceError.notAuthenticated
                case 403:
                    throw CalendarServiceError.insufficientPermissions
                case 404, 410:
                    throw CalendarServiceError.eventNotFound
                default:
                    throw CalendarServiceError.httpError(statusCode: response.statusCode, message: serverMessage)
                }
            }
        } catch {
            if error is CancellationError || error is CalendarServiceError {
                throw error
            }

            throw CalendarServiceError.networkError(error.localizedDescription)
        }
    }
}

private extension CalendarService {
    struct RSVPUpdateRequestBody: Encodable {
        let attendeesOmitted: Bool
        let attendees: [RSVPUpdateAttendee]
    }

    struct RSVPUpdateAttendee: Encodable {
        let email: String
        let responseStatus: String
    }

    var transientURLErrorCodes: Set<URLError.Code> {
        [
            .timedOut,
            .networkConnectionLost,
            .notConnectedToInternet,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .resourceUnavailable
        ]
    }

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

    func makeResponseStatusUpdateRequest(
        eventID: String,
        attendeeEmail: String,
        status: EventResponseStatus,
        accessToken: String
    ) throws -> URLRequest {
        // We patch only the authenticated attendee and set attendeesOmitted=true so Google
        // does not require a full attendees array and we avoid overwriting other attendees.
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(encodedPathComponent(eventID))")
        components?.queryItems = [
            URLQueryItem(name: "sendUpdates", value: "none")
        ]

        guard let url = components?.url else {
            throw CalendarServiceError.invalidRequestURL
        }

        let body = RSVPUpdateRequestBody(
            attendeesOmitted: true,
            attendees: [
                RSVPUpdateAttendee(
                    email: attendeeEmail,
                    responseStatus: status.rawValue
                )
            ]
        )

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    func resolveCurrentUserAttendeeEmail(for event: CalendarEvent) throws -> String {
        if let selfAttendee = event.attendees.first(where: { $0.isSelf }) {
            return selfAttendee.email
        }

        if let currentUserEmail = normalizedEmail(authService.currentSession?.accountEmail),
           let matchedAttendee = event.attendees.first(where: {
               $0.email.caseInsensitiveCompare(currentUserEmail) == .orderedSame
           }) {
            return matchedAttendee.email
        }

        if event.isUserOrganizer {
            throw CalendarServiceError.organizerEventResponseNotSupported
        }

        throw CalendarServiceError.attendeeSelfNotFound
    }

    func performRequestWithRetry(
        _ request: URLRequest,
        maxAttempts: Int = 3
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 1

        while true {
            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CalendarServiceError.invalidResponse
                }

                if attempt < maxAttempts, isRetryable(statusCode: httpResponse.statusCode) {
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds(forAttempt: attempt))
                    attempt += 1
                    continue
                }

                return (data, httpResponse)
            } catch {
                if error is CancellationError {
                    throw error
                }

                if let urlError = error as? URLError,
                   transientURLErrorCodes.contains(urlError.code),
                   attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds(forAttempt: attempt))
                    attempt += 1
                    continue
                }

                throw error
            }
        }
    }

    func isRetryable(statusCode: Int) -> Bool {
        statusCode == 429 || (500...599).contains(statusCode)
    }

    func retryDelayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let delaySeconds = min(pow(2.0, Double(attempt - 1)) * 0.35, 1.5)
        return UInt64(delaySeconds * 1_000_000_000)
    }

    func encodedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
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

    func transformEvents(from payload: GoogleCalendarEventsResponse, now: Date) -> [CalendarEvent] {
        let calendarTimeZone = payload.timeZone.flatMap(TimeZone.init(identifier:))
        let currentUserEmail = normalizedEmail(authService.currentSession?.accountEmail)

        let mappedEvents = payload.items.compactMap { eventItem in
            mapGoogleEvent(
                eventItem,
                calendarTimeZone: calendarTimeZone,
                currentUserEmail: currentUserEmail
            )
        }

        var deduplicatedByID: [String: CalendarEvent] = [:]
        for event in mappedEvents where event.endDate > now {
            guard let existing = deduplicatedByID[event.id] else {
                deduplicatedByID[event.id] = event
                continue
            }

            deduplicatedByID[event.id] = existing.startDate <= event.startDate ? existing : event
        }

        return deduplicatedByID.values.sorted { $0.startDate < $1.startDate }
    }

    func mapGoogleEvent(
        _ item: GoogleCalendarEventItem,
        calendarTimeZone: TimeZone?,
        currentUserEmail: String?
    ) -> CalendarEvent? {
        if item.status?.caseInsensitiveCompare("cancelled") == .orderedSame {
            return nil
        }

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
        let userResponseStatus = resolveUserResponseStatus(
            attendees: attendees,
            currentUserEmail: currentUserEmail,
            isUserOrganizer: isUserOrganizer
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
            isUserOrganizer: isUserOrganizer,
            userResponseStatus: userResponseStatus
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

    func resolveUserResponseStatus(
        attendees: [EventAttendee],
        currentUserEmail: String?,
        isUserOrganizer: Bool
    ) -> EventResponseStatus {
        if let selfAttendee = attendees.first(where: { $0.isSelf }) {
            return EventResponseStatus(googleResponseStatus: selfAttendee.responseStatus)
        }

        if let currentUserEmail,
           let matchedAttendee = attendees.first(where: {
               $0.email.caseInsensitiveCompare(currentUserEmail) == .orderedSame
           }) {
            return EventResponseStatus(googleResponseStatus: matchedAttendee.responseStatus)
        }

        if isUserOrganizer {
            return .accepted
        }

        return .unknown
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
