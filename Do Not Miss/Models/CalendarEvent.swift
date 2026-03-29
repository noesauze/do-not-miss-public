import Foundation

struct EventAttendee: Identifiable, Equatable {
    var id: String { email.lowercased() }
    let name: String?
    let email: String
    let responseStatus: String?
    let isOrganizer: Bool
    let isSelf: Bool
}

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let videoLink: URL?
    let videoProvider: String?
    let notes: String?
    let location: String?
    let isAllDay: Bool
    let organizerName: String?
    let organizerEmail: String?
    let attendees: [EventAttendee]
    let isUserOrganizer: Bool

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        videoLink: URL?,
        videoProvider: String? = nil,
        notes: String? = nil,
        location: String? = nil,
        isAllDay: Bool = false,
        organizerName: String? = nil,
        organizerEmail: String? = nil,
        attendees: [EventAttendee] = [],
        isUserOrganizer: Bool = false
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.videoLink = videoLink
        self.videoProvider = videoProvider
        self.notes = notes
        self.location = location
        self.isAllDay = isAllDay
        self.organizerName = organizerName
        self.organizerEmail = organizerEmail
        self.attendees = attendees
        self.isUserOrganizer = isUserOrganizer
    }
}
