import Foundation

enum DoNotMissBackendLanguageResolver {
    static func resolveCurrentLanguage(
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> DoNotMissBackendLanguage {
        if let appLanguageIdentifier = bundle.preferredLocalizations.first {
            return DoNotMissBackendLanguage(languageIdentifier: appLanguageIdentifier)
        }

        return DoNotMissBackendLanguage(languageIdentifier: locale.identifier)
    }
}
