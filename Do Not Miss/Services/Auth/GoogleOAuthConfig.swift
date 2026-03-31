import Foundation

enum GoogleOAuthConfig {
    static let clientID = infoValue(for: "GoogleClientID")
    static let callbackURLScheme = infoValue(for: "GoogleCallbackScheme")
    static let redirectURI = infoValue(for: "GoogleRedirectURI")
    static let calendarEventsScope = "https://www.googleapis.com/auth/calendar.events"

    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    static let keychainService = "com.donotmiss.oauth"
    static let keychainAccount = "google.calendar.session"

    static var isConfigured: Bool {
        !clientID.contains("GOOGLE_CLIENT_ID_PLACEHOLDER")
            && !callbackURLScheme.contains("GOOGLE_CLIENT_ID_PLACEHOLDER")
            && !redirectURI.contains("GOOGLE_CLIENT_ID_PLACEHOLDER")
    }

    private static func infoValue(for key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
