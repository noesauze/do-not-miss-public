import Foundation

enum DoNotMissBackendConfig {
    static let environmentVariableKey = "DO_NOT_MISS_BACKEND_BASE_URL"
    static let infoPlistKey = "DoNotMissBackendBaseURL"
    static let defaultBaseURLString = "https://do-not-miss-backend.vercel.app"

    static var resolvedBaseURLString: String {
        let environmentValue = ProcessInfo.processInfo.environment[environmentVariableKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentValue, environmentValue.isEmpty == false {
            return environmentValue
        }

        let infoPlistValue = (Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let infoPlistValue, infoPlistValue.isEmpty == false {
            return infoPlistValue
        }

        return defaultBaseURLString
    }
}
