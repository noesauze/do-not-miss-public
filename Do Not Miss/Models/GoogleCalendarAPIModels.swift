import Foundation

struct GoogleCalendarEventsResponse: Decodable {
    let items: [GoogleCalendarEventItem]
    let timeZone: String?
}

struct GoogleCalendarEventItem: Decodable {
    let id: String?
    let summary: String?
    let description: String?
    let location: String?
    let hangoutLink: String?
    let start: GoogleCalendarEventDateTime?
    let end: GoogleCalendarEventDateTime?
    let conferenceData: GoogleCalendarConferenceData?
    let organizer: GoogleCalendarParticipant?
    let creator: GoogleCalendarParticipant?
    let attendees: [GoogleCalendarAttendee]?
}

struct GoogleCalendarParticipant: Decodable {
    let displayName: String?
    let email: String?
    let selfValue: Bool?

    private enum CodingKeys: String, CodingKey {
        case displayName
        case email
        case selfValue = "self"
    }
}

struct GoogleCalendarAttendee: Decodable {
    let displayName: String?
    let email: String?
    let responseStatus: String?
    let organizer: Bool?
    let selfValue: Bool?

    private enum CodingKeys: String, CodingKey {
        case displayName
        case email
        case responseStatus
        case organizer
        case selfValue = "self"
    }
}

struct GoogleCalendarEventDateTime: Decodable {
    let dateTime: String?
    let date: String?
    let timeZone: String?
}

struct GoogleCalendarConferenceData: Decodable {
    let conferenceId: String?
    let conferenceSolution: GoogleCalendarConferenceSolution?
    let entryPoints: [GoogleCalendarConferenceEntryPoint]?
}

struct GoogleCalendarConferenceSolution: Decodable {
    let name: String?
}

struct GoogleCalendarConferenceEntryPoint: Decodable {
    let entryPointType: String?
    let uri: String?
}

struct GoogleCalendarErrorEnvelope: Decodable {
    let error: GoogleCalendarErrorBody
}

struct GoogleCalendarErrorBody: Decodable {
    let code: Int?
    let message: String?
}

enum GoogleCalendarDateParser {
    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601WithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseDateTime(_ rawValue: String?) -> Date? {
        guard let rawValue else {
            return nil
        }

        return iso8601WithFractionalSeconds.date(from: rawValue)
            ?? iso8601WithoutFractionalSeconds.date(from: rawValue)
    }

    static func parseAllDayDate(_ rawValue: String?, in timeZone: TimeZone?) -> Date? {
        guard let rawValue else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timeZone ?? .current
        return formatter.date(from: rawValue)
    }
}
