import AppKit
import Foundation

enum ExternalURLOpenResult {
    case opened
    case blockedScheme
    case unsupported
    case failed
}

@MainActor
final class ExternalURLOpener {
    private let explicitlyAllowedSchemes: Set<String>
    private let blockedSchemes: Set<String>

    init(
        explicitlyAllowedSchemes: Set<String> = ["http", "https", "mailto"],
        blockedSchemes: Set<String> = ["javascript", "data", "file"]
    ) {
        self.explicitlyAllowedSchemes = explicitlyAllowedSchemes
        self.blockedSchemes = blockedSchemes
    }

    func canOpen(_ url: URL) -> Bool {
        resolvedPolicy(for: url) != .blocked
    }

    func open(_ url: URL) -> ExternalURLOpenResult {
        let policy = resolvedPolicy(for: url)

        switch policy {
        case .blocked:
            return .blockedScheme
        case .allowedExplicitly, .allowedBySystemSupport:
            let didOpen = NSWorkspace.shared.open(url)
            return didOpen ? .opened : .failed
        case .unsupported:
            return .unsupported
        }
    }
}

private extension ExternalURLOpener {
    enum OpenPolicy {
        case allowedExplicitly
        case allowedBySystemSupport
        case blocked
        case unsupported
    }

    func resolvedPolicy(for url: URL) -> OpenPolicy {
        guard let scheme = url.scheme?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              scheme.isEmpty == false else {
            return .unsupported
        }

        if blockedSchemes.contains(scheme) {
            return .blocked
        }

        if explicitlyAllowedSchemes.contains(scheme) {
            return .allowedExplicitly
        }

        if NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            return .allowedBySystemSupport
        }

        return .unsupported
    }
}
