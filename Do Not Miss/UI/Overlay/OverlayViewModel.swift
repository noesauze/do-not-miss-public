import Foundation
import Combine

enum OverlayActionAvailability {
    case enabled
    case disabled

    var isEnabled: Bool {
        if case .enabled = self {
            return true
        }
        return false
    }
}

@MainActor
final class OverlayViewModel: ObservableObject {
    let event: CalendarEvent
    let onJoinNow: (URL) -> Void
    let onSnooze: (CalendarEvent) -> Void
    let onRunningLate: (CalendarEvent) -> Bool
    let onOpenContact: (CalendarEvent) -> Bool
    let onClose: () -> Void

    @Published private(set) var countdownText: String = ""
    @Published private(set) var actionFeedback: String?

    private var timer: Timer?
    private var lastActionTapTime: Date?

    init(
        event: CalendarEvent,
        onJoinNow: @escaping (URL) -> Void,
        onSnooze: @escaping (CalendarEvent) -> Void,
        onRunningLate: @escaping (CalendarEvent) -> Bool,
        onOpenContact: @escaping (CalendarEvent) -> Bool,
        onClose: @escaping () -> Void,
    ) {
        self.event = event
        self.onJoinNow = onJoinNow
        self.onSnooze = onSnooze
        self.onRunningLate = onRunningLate
        self.onOpenContact = onOpenContact
        self.onClose = onClose
        updateCountdownText(now: Date())
    }

    deinit {
        timer?.invalidate()
    }

    var resolvedTitle: String {
        let trimmedTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? L10n.tr("event.untitled") : trimmedTitle
    }

    var formattedStartTime: String {
        Self.startDateFormatter.string(from: event.startDate)
    }

    var providerDisplayName: String? {
        let trimmedProvider = event.videoProvider?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedProvider, trimmedProvider.isEmpty == false else {
            return nil
        }

        return trimmedProvider
    }

    var joinURL: URL? {
        guard let url = event.videoLink,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              host.isEmpty == false,
              ["http", "https"].contains(scheme) else {
            return nil
        }

        return url
    }

    var canJoin: Bool {
        joinURL != nil
    }

    var organizerEmail: String? {
        let trimmedEmail = event.organizerEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedEmail, trimmedEmail.isEmpty == false else {
            return nil
        }
        return trimmedEmail
    }

    var joinActionAvailability: OverlayActionAvailability {
        canJoin ? .enabled : .disabled
    }

    var openContactAvailability: OverlayActionAvailability {
        validOrganizerEmail == nil ? .disabled : .enabled
    }

    var runningLateAvailability: OverlayActionAvailability {
        validOrganizerEmail == nil ? .disabled : .enabled
    }

    func startCountdown() {
        guard timer == nil else {
            return
        }

        updateCountdownText(now: Date())

        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCountdownText(now: Date())
            }
        }

        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopCountdown() {
        timer?.invalidate()
        timer = nil
    }

    func closeTapped() {
        guard canHandleTapAction() else {
            return
        }

        stopCountdown()
        onClose()
    }

    func joinNowTapped() {
        guard canHandleTapAction() else {
            return
        }

        guard let url = joinURL else {
            return
        }

        stopCountdown()
        onJoinNow(url)
    }

    func snoozeTapped() {
        guard canHandleTapAction() else {
            return
        }

        print("[Overlay] Snooze 2 min tapped for event: \(event.title)")
        actionFeedback = L10n.tr("overlay.feedback.snoozed")
        stopCountdown()
        onSnooze(event)
    }

    func runningLateTapped() {
        guard canHandleTapAction() else {
            return
        }

        let wasOpened = onRunningLate(event)
        actionFeedback = wasOpened
            ? L10n.tr("overlay.feedback.running_late_opened")
            : L10n.tr("overlay.feedback.running_late_unavailable")
    }

    func openContactTapped() {
        guard canHandleTapAction() else {
            return
        }

        guard validOrganizerEmail != nil else {
            return
        }

        let wasOpened = onOpenContact(event)
        actionFeedback = wasOpened
            ? L10n.tr("overlay.feedback.contact_opened")
            : L10n.tr("overlay.feedback.contact_unavailable")
    }
}

private extension OverlayViewModel {
    var validOrganizerEmail: String? {
        guard let organizerEmail,
              organizerEmail.contains("@"),
              organizerEmail.contains(" ") == false else {
            return nil
        }
        return organizerEmail
    }

    func canHandleTapAction() -> Bool {
        let now = Date()
        if let lastActionTapTime,
           now.timeIntervalSince(lastActionTapTime) < 0.35 {
            return false
        }

        lastActionTapTime = now
        return true
    }

    func updateCountdownText(now: Date) {
        let delta = event.startDate.timeIntervalSince(now)

        if delta >= 0 {
            countdownText = L10n.tr("overlay.countdown.starts_in", Self.formatDuration(delta))
            return
        }

        countdownText = L10n.tr("overlay.countdown.started_ago", Self.formatDuration(abs(delta)))
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let rounded = Int(interval.rounded())

        if rounded < 60 {
            return String(format: "00:%02d", rounded)
        }

        if rounded < 3_600 {
            let minutes = rounded / 60
            let seconds = rounded % 60
            return String(format: "%02d:%02d", minutes, seconds)
        }

        if rounded < 86_400 {
            let hours = rounded / 3_600
            let minutes = (rounded % 3_600) / 60
            let seconds = rounded % 60
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }

        let days = rounded / 86_400
        let hours = (rounded % 86_400) / 3_600
        let minutes = (rounded % 3_600) / 60
        return String(format: "%dd %02dh %02dm", days, hours, minutes)
    }

    static let startDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
