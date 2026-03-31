import AppKit
import Foundation

struct OrganizerContactService {
    func makeRunningLateURL(for event: CalendarEvent, minutesLate: Int) -> URL? {
        guard minutesLate > 0 else {
            return nil
        }

        guard let recipient = preferredRecipientEmail(for: event) else {
            return nil
        }

        let title = normalizedEventTitle(for: event)
        let subject = L10n.tr("organizer_contact.running_late.subject", minutesLate, title)
        let body = L10n.tr(
            "organizer_contact.running_late.body",
            salutationSuffix(for: event),
            minutesLate,
            title
        )

        return makeMailtoURL(
            recipient: recipient,
            subject: subject,
            body: body
        )
    }

    func makeContactOrganizerURL(for event: CalendarEvent) -> URL? {
        guard let recipient = preferredRecipientEmail(for: event) else {
            return nil
        }

        return makeMailtoURL(recipient: recipient)
    }

    func copyOrganizerEmail(for event: CalendarEvent) -> Bool {
        guard let email = preferredRecipientEmail(for: event) else {
            return false
        }

        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(email, forType: .string)
    }
}

private extension OrganizerContactService {
    func preferredRecipientEmail(for event: CalendarEvent) -> String? {
        if let organizerEmail = normalizeEmail(event.organizerEmail) {
            return organizerEmail
        }

        return event.attendees.first(where: { attendee in
            attendee.isSelf == false && normalizeEmail(attendee.email) != nil
        }).flatMap { normalizeEmail($0.email) }
    }

    func normalizedEventTitle(for event: CalendarEvent) -> String {
        let trimmed = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.tr("organizer_contact.default_event_title") : trimmed
    }

    func salutationSuffix(for event: CalendarEvent) -> String {
        guard let name = event.organizerName?.trimmingCharacters(in: .whitespacesAndNewlines),
              name.isEmpty == false else {
            return ""
        }
        return " \(name)"
    }

    func normalizeEmail(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false,
              trimmed.contains("@"),
              trimmed.contains(" ") == false else {
            return nil
        }

        return trimmed
    }

    func makeMailtoURL(
        recipient: String,
        subject: String? = nil,
        body: String? = nil
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient

        var queryItems: [URLQueryItem] = []
        if let subject, subject.isEmpty == false {
            queryItems.append(URLQueryItem(name: "subject", value: subject))
        }
        if let body, body.isEmpty == false {
            queryItems.append(URLQueryItem(name: "body", value: body))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        return components.url
    }
}
