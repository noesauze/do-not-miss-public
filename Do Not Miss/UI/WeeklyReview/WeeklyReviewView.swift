import AppKit
import SwiftUI

struct WeeklyReviewView: View {
    @ObservedObject var session: WeeklyReviewSession
    let onClose: () -> Void

    @StateObject private var cardViewModel = WeeklyReviewCardViewModel()
    @State private var keyMonitor: Any?
    @State private var isSubmittingDecision: Bool = false
    @State private var isUndoingAction: Bool = false
    @State private var submissionErrorMessage: String?
    @State private var undoErrorMessage: String?
    @State private var pendingRetryDecision: WeeklyReviewDecision?
    @State private var previewNextEvent: CalendarEvent?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.10),
                    Color(red: 0.08, green: 0.12, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                header

                Group {
                    if session.isEmpty {
                        emptyState
                    } else if session.isCompleted {
                        WeeklyReviewSummaryView(
                            session: session,
                            onClose: onClose,
                            onReviewAgain: session.events.count > 1 ? {
                                restartReviewFromSummary()
                            } : nil
                        )
                    } else if let event = session.currentEvent {
                        if let previewNextEvent, isSubmittingDecision {
                            WeeklyReviewCardView(
                                event: previewNextEvent,
                                viewModel: cardViewModel,
                                onDecisionRequested: { _ in }
                            )
                            .allowsHitTesting(false)
                        } else if cardViewModel.isAwaitingNextCard && isSubmittingDecision {
                            nextCardLoader
                        } else {
                            WeeklyReviewCardView(
                                event: event,
                                viewModel: cardViewModel,
                                onDecisionRequested: { decision in
                                    applyDecision(decision)
                                }
                            )
                        }
                    } else {
                        unexpectedState
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isReviewingCurrentCard {
                    actionBar
                }

                if session.canUndoLastAction || isUndoingAction {
                    undoBar
                }

                if isSubmittingDecision {
                    progressPill(text: L10n.tr("weekly_review.submission.in_progress"))
                }

                if isUndoingAction {
                    progressPill(text: L10n.tr("weekly_review.undo.in_progress"))
                }

                if let submissionErrorMessage {
                    submissionErrorPanel(message: submissionErrorMessage)
                }

                if let undoErrorMessage {
                    undoErrorPanel(message: undoErrorMessage)
                }

                footer
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .onChange(of: currentEventID) { _ in
            cardViewModel.resetForNextCard()
            isSubmittingDecision = false
            submissionErrorMessage = nil
            pendingRetryDecision = nil
            undoErrorMessage = nil
            previewNextEvent = nil
        }
        .onAppear {
            installKeyMonitorIfNeeded()
        }
        .onDisappear {
            removeKeyMonitor()
            cardViewModel.cancelPendingDecision()
            isSubmittingDecision = false
            isUndoingAction = false
            previewNextEvent = nil
        }
    }

    private var isBusy: Bool {
        isSubmittingDecision || isUndoingAction
    }

    private var isReviewingCurrentCard: Bool {
        session.isEmpty == false && session.isCompleted == false && session.currentEvent != nil
    }

    private var currentEventID: String? {
        session.currentEvent?.id
    }

    private var header: some View {
        HStack {
            Text(L10n.tr("weekly_review.title"))
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Spacer()

            Text(session.progressText)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if isReviewingCurrentCard {
                Text(L10n.tr("weekly_review.hint.left"))
                Text(L10n.tr("weekly_review.hint.right"))
                Text(L10n.tr("weekly_review.hint.down_or_space"))
                Text(L10n.tr("weekly_review.hint.undo"))
            }

            Spacer()

            Button(L10n.tr("weekly_review.close")) {
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .tint(.gray.opacity(0.3))
            .keyboardShortcut(.cancelAction)
            .disabled(cardViewModel.isInteractionLocked || isBusy)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var actionBar: some View {
        HStack(spacing: 18) {
            decisionButton(
                title: L10n.tr("weekly_review.action.decline"),
                systemImage: "xmark",
                tint: .red,
                decision: .decline
            )

            decisionButton(
                title: L10n.tr("weekly_review.action.tentative"),
                systemImage: "questionmark",
                tint: .orange,
                decision: .tentative
            )

            decisionButton(
                title: L10n.tr("weekly_review.action.accept"),
                systemImage: "checkmark",
                tint: .green,
                decision: .accept
            )
        }
    }

    private var undoBar: some View {
        HStack(spacing: 12) {
            Button(L10n.tr("weekly_review.undo.button")) {
                triggerUndo()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("z", modifiers: [.command])
            .disabled(session.canUndoLastAction == false || isBusy)

            if let action = session.lastAction {
                Text(L10n.tr("weekly_review.undo.last_action", action.eventTitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private func decisionButton(
        title: String,
        systemImage: String,
        tint: Color,
        decision: WeeklyReviewDecision
    ) -> some View {
        Button {
            applyDecision(decision)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(minWidth: 140)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint.opacity(0.82))
        .disabled(cardViewModel.isInteractionLocked || isBusy)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(L10n.tr("weekly_review.empty.title"))
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text(L10n.tr("weekly_review.empty.description"))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 640)
    }

    private var nextCardLoader: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            Text(L10n.tr("weekly_review.next_card.loading"))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 920, minHeight: 420)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private var unexpectedState: some View {
        VStack(spacing: 14) {
            Text(L10n.tr("weekly_review.state_error.title"))
                .font(.title2.weight(.bold))

            Text(L10n.tr("weekly_review.state_error.message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(L10n.tr("weekly_review.state_error.retry")) {
                session.restartReviewFromBeginning()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 520)
    }

    private func progressPill(text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func submissionErrorPanel(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("weekly_review.submission.error_title"))
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(L10n.tr("weekly_review.submission.retry")) {
                    retryCurrentDecision()
                }
                .buttonStyle(.borderedProminent)

                Button(L10n.tr("weekly_review.submission.skip")) {
                    skipCurrentEvent()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func undoErrorPanel(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("weekly_review.undo.error_title"))
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(L10n.tr("weekly_review.undo.retry")) {
                triggerUndo()
            }
            .buttonStyle(.bordered)
            .disabled(session.canUndoLastAction == false || isBusy)
        }
        .padding(14)
        .frame(maxWidth: 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private func applyDecision(_ decision: WeeklyReviewDecision) {
        guard isReviewingCurrentCard, isBusy == false else {
            return
        }

        submissionErrorMessage = nil
        undoErrorMessage = nil
        pendingRetryDecision = nil
        previewNextEvent = session.nextEvent

        cardViewModel.trigger(decision: decision) { chosenDecision in
            Task {
                await submitDecision(chosenDecision)
            }
        }
    }

    private func retryCurrentDecision() {
        guard let pendingRetryDecision else {
            return
        }

        applyDecision(pendingRetryDecision)
    }

    private func skipCurrentEvent() {
        guard isBusy == false else {
            return
        }

        submissionErrorMessage = nil
        undoErrorMessage = nil
        pendingRetryDecision = nil
        previewNextEvent = nil
        session.skipCurrentEventAfterFailure()
    }

    private func restartReviewFromSummary() {
        guard isBusy == false else {
            return
        }

        submissionErrorMessage = nil
        undoErrorMessage = nil
        pendingRetryDecision = nil
        previewNextEvent = nil
        session.restartReviewFromBeginning()
    }

    private func triggerUndo() {
        guard isBusy == false, session.canUndoLastAction else {
            return
        }

        Task {
            await undoLastAction()
        }
    }

    private func undoLastAction() async {
        guard isBusy == false else {
            return
        }

        isUndoingAction = true
        defer {
            isUndoingAction = false
        }

        do {
            try await session.undoLastAction()
            submissionErrorMessage = nil
            undoErrorMessage = nil
            pendingRetryDecision = nil
            previewNextEvent = nil
            cardViewModel.resetForNextCard()
        } catch {
            undoErrorMessage = L10n.tr("weekly_review.undo.error_message", error.localizedDescription)
        }
    }

    private func submitDecision(_ decision: WeeklyReviewDecision) async {
        guard isReviewingCurrentCard,
              let event = session.currentEvent,
              isBusy == false else {
            return
        }

        isSubmittingDecision = true
        defer {
            isSubmittingDecision = false
        }

        do {
            try await session.submitCurrentDecision(decision)
            submissionErrorMessage = nil
            undoErrorMessage = nil
            pendingRetryDecision = nil
        } catch {
            let message = error.localizedDescription
            session.recordSubmissionFailure(for: event, decision: decision, errorMessage: message)
            previewNextEvent = nil
            cardViewModel.resetForNextCard()
            submissionErrorMessage = L10n.tr("weekly_review.submission.error_message", message)
            pendingRetryDecision = decision
        }
    }

    private func handle(event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            triggerUndo()
            return true
        }

        switch event.keyCode {
        case 53:
            if cardViewModel.isInteractionLocked || isBusy {
                return true
            }
            onClose()
            return true
        case 123:
            applyDecision(.decline)
            return true
        case 124:
            applyDecision(.accept)
            return true
        case 125, 49:
            applyDecision(.tentative)
            return true
        default:
            return false
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else {
            return
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handle(event: event) {
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else {
            return
        }

        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}
