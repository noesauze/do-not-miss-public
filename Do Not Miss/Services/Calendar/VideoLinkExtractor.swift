import Foundation

enum VideoProvider: String, Equatable {
    case googleMeet = "Google Meet"
    case zoom = "Zoom"
    case teams = "Microsoft Teams"
    case other = "Other"
}

enum VideoLinkSource: String, Equatable {
    case hangoutLink
    case conferenceData
    case description
    case location
}

struct VideoLinkMatch: Equatable {
    let provider: VideoProvider
    let url: URL
    let source: VideoLinkSource
}

struct VideoLinkExtractor {
    func extractBestVideoLink(from rawEvent: GoogleCalendarEventItem) -> VideoLinkMatch? {
        if let hangoutLink = rawEvent.hangoutLink,
           let normalizedURL = normalizeURL(from: hangoutLink),
           let provider = provider(for: normalizedURL) {
            return VideoLinkMatch(provider: provider, url: normalizedURL, source: .hangoutLink)
        }

        if let conferenceMatch = extractFromConferenceData(rawEvent.conferenceData) {
            return conferenceMatch
        }

        if let descriptionMatch = extractFirstVideoURL(fromText: rawEvent.description, source: .description) {
            return descriptionMatch
        }

        if let locationMatch = extractFirstVideoURL(fromText: rawEvent.location, source: .location) {
            return locationMatch
        }

        return nil
    }
}

private extension VideoLinkExtractor {
    func extractFromConferenceData(_ conferenceData: GoogleCalendarConferenceData?) -> VideoLinkMatch? {
        guard let conferenceData else {
            return nil
        }

        let entryPoints = conferenceData.entryPoints ?? []

        if let preferredVideoEntry = entryPoints.first(where: { entryPoint in
            (entryPoint.entryPointType ?? "").lowercased() == "video"
        }),
           let uri = preferredVideoEntry.uri,
           let normalizedURL = normalizeURL(from: uri),
           let provider = provider(for: normalizedURL) {
            return VideoLinkMatch(provider: provider, url: normalizedURL, source: .conferenceData)
        }

        for entryPoint in entryPoints {
            guard let uri = entryPoint.uri,
                  let normalizedURL = normalizeURL(from: uri),
                  let provider = provider(for: normalizedURL) else {
                continue
            }

            return VideoLinkMatch(provider: provider, url: normalizedURL, source: .conferenceData)
        }

        return nil
    }

    func extractFirstVideoURL(fromText text: String?, source: VideoLinkSource) -> VideoLinkMatch? {
        guard let text,
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []

        for match in matches {
            guard let url = match.url,
                  let normalizedURL = normalizeURL(from: url.absoluteString),
                  let provider = provider(for: normalizedURL) else {
                continue
            }

            return VideoLinkMatch(provider: provider, url: normalizedURL, source: source)
        }

        return nil
    }

    func normalizeURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        guard var components = URLComponents(string: trimmed) else {
            return nil
        }

        if components.scheme == nil {
            components.scheme = "https"
        }

        guard let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host,
              host.isEmpty == false,
              let url = components.url else {
            return nil
        }

        return url
    }

    func provider(for url: URL) -> VideoProvider? {
        guard let host = url.host?.lowercased() else {
            return nil
        }

        if host == "meet.google.com" || host == "g.co" {
            return .googleMeet
        }

        if host == "zoom.us" || host.hasSuffix(".zoom.us") || host == "zoomgov.com" || host.hasSuffix(".zoomgov.com") {
            return .zoom
        }

        if host == "teams.microsoft.com" || host.hasSuffix(".teams.microsoft.com") || host == "teams.live.com" {
            return .teams
        }

        return nil
    }
}
