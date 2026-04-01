import SwiftUI
import Combine

@MainActor
final class WeeklyReviewCardViewModel: ObservableObject {
    @Published private(set) var dragOffset: CGSize = .zero
    @Published private(set) var cardOpacity: Double = 1.0
    @Published private(set) var cardScale: CGFloat = 1.0
    @Published private(set) var isInteractionLocked: Bool = false
    @Published private(set) var forcedBadgeDecision: WeeklyReviewDecision?
    @Published private(set) var isAwaitingNextCard: Bool = false
    private var pendingDecisionWorkItem: DispatchWorkItem?

    let swipeThreshold: CGFloat = 180

    var rotationAngle: Double {
        let maxRotation: Double = 12
        let raw = Double(dragOffset.width / 26)
        return max(-maxRotation, min(maxRotation, raw))
    }

    var acceptFeedbackOpacity: Double {
        if forcedBadgeDecision == .accept {
            return 1
        }
        return max(0, min(1, dragOffset.width / swipeThreshold))
    }

    var declineFeedbackOpacity: Double {
        if forcedBadgeDecision == .decline {
            return 1
        }
        return max(0, min(1, -dragOffset.width / swipeThreshold))
    }

    func updateDrag(_ value: DragGesture.Value) {
        guard isInteractionLocked == false else {
            return
        }

        dragOffset = CGSize(
            width: value.translation.width,
            height: value.translation.height * 0.20
        )
    }

    func endDrag(onDecision: @escaping (WeeklyReviewDecision) -> Void) {
        guard isInteractionLocked == false else {
            return
        }

        if dragOffset.width >= swipeThreshold {
            animateOut(decision: .accept, direction: 1, onDecision: onDecision)
            return
        }

        if dragOffset.width <= -swipeThreshold {
            animateOut(decision: .decline, direction: -1, onDecision: onDecision)
            return
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            dragOffset = .zero
        }
    }

    func trigger(decision: WeeklyReviewDecision, onDecision: @escaping (WeeklyReviewDecision) -> Void) {
        guard isInteractionLocked == false else {
            return
        }

        switch decision {
        case .accept:
            animateOut(decision: .accept, direction: 1, onDecision: onDecision)
        case .decline:
            animateOut(decision: .decline, direction: -1, onDecision: onDecision)
        case .tentative:
            animateOutTentative(onDecision: onDecision)
        }
    }

    func resetForNextCard() {
        pendingDecisionWorkItem?.cancel()
        pendingDecisionWorkItem = nil
        dragOffset = .zero
        cardOpacity = 1
        cardScale = 1
        isInteractionLocked = false
        forcedBadgeDecision = nil
        isAwaitingNextCard = false
    }

    func cancelPendingDecision() {
        pendingDecisionWorkItem?.cancel()
        pendingDecisionWorkItem = nil
        isInteractionLocked = false
        isAwaitingNextCard = false
    }

    private func animateOut(
        decision: WeeklyReviewDecision,
        direction: CGFloat,
        onDecision: @escaping (WeeklyReviewDecision) -> Void
    ) {
        isInteractionLocked = true
        isAwaitingNextCard = true
        forcedBadgeDecision = decision

        withAnimation(.easeIn(duration: 0.22)) {
            dragOffset = CGSize(width: direction * 1_100, height: dragOffset.height)
            cardOpacity = 0
            cardScale = 0.94
        }
        
        scheduleDecisionAfterAnimation(delay: 0.23, decision: decision, onDecision: onDecision)
    }

    private func animateOutTentative(onDecision: @escaping (WeeklyReviewDecision) -> Void) {
        isInteractionLocked = true
        isAwaitingNextCard = true
        forcedBadgeDecision = .tentative

        withAnimation(.easeInOut(duration: 0.18)) {
            dragOffset = CGSize(width: 0, height: 90)
            cardOpacity = 0
            cardScale = 0.95
        }
        
        scheduleDecisionAfterAnimation(delay: 0.21, decision: .tentative, onDecision: onDecision)
    }
    
    private func scheduleDecisionAfterAnimation(
        delay: TimeInterval,
        decision: WeeklyReviewDecision,
        onDecision: @escaping (WeeklyReviewDecision) -> Void
    ) {
        pendingDecisionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            onDecision(decision)
            self.resetForNextCard()
        }

        pendingDecisionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
