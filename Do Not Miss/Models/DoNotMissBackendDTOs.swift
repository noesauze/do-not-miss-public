import Foundation

enum DoNotMissMessageWorkflow: String, Sendable {
    case startingApp = "starting_app"
    case afterEventAlert = "after_event_alert"
    case afterWeeklyReview = "after_weekly_review"
}

enum DoNotMissBackendLanguage: String, Codable, Sendable {
    case fr
    case en

    init(languageIdentifier: String) {
        let normalizedIdentifier = languageIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self = normalizedIdentifier.hasPrefix(Self.fr.rawValue) ? .fr : .en
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        self = DoNotMissBackendLanguage(languageIdentifier: rawValue)
    }
}

struct DoNotMissLatestMessageResponseDTO: Decodable {
    let message: DoNotMissMessageDTO?
}

struct DoNotMissMessageDTO: Decodable, Identifiable {
    let id: String
    let title: String?
    let body: String?
    let cta: DoNotMissMessageCTADTO?
    let language: DoNotMissBackendLanguage

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case cta
        case language
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        cta = try container.decodeIfPresent(DoNotMissMessageCTADTO.self, forKey: .cta)
        language = try container.decodeIfPresent(DoNotMissBackendLanguage.self, forKey: .language) ?? .en
    }
}

struct DoNotMissMessageCTADTO: Decodable {
    let label: String?
    let url: URL?
}

struct DoNotMissUpsertUserRequestDTO: Encodable {
    let email: String
    let name: String?
}

struct DoNotMissImpressionRequestDTO: Encodable {
    let googleEmail: String
    let appVersion: String
    let contextEventId: String?
    let contextEventStartAt: String?

    init(
        googleEmail: String,
        appVersion: String,
        contextEventId: String? = nil,
        contextEventStartAt: String? = nil
    ) {
        self.googleEmail = googleEmail
        self.appVersion = appVersion
        self.contextEventId = contextEventId
        self.contextEventStartAt = contextEventStartAt
    }
}

struct DoNotMissImpressionResponseDTO: Decodable {
    let status: Status?

    enum Status: String, Decodable {
        case recorded
        case alreadyRecorded = "already_recorded"
    }
}

struct DoNotMissCTAClickRequestDTO: Encodable {
    let googleEmail: String
}
