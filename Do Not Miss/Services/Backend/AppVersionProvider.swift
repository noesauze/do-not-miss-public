import Foundation

struct AppVersionProvider {
    static func resolved(bundle: Bundle = .main) -> String {
        let shortVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let shortVersion, shortVersion.isEmpty == false {
            return shortVersion
        }

        let bundleVersion = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let bundleVersion, bundleVersion.isEmpty == false {
            return bundleVersion
        }

        return "unknown"
    }
}
