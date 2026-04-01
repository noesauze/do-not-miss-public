import SwiftUI

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case features
    case connect

    var id: Int { rawValue }

    var index: Int { rawValue }

    var isFirst: Bool { self == .welcome }

    var isLast: Bool { self == .connect }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }

}

struct OnboardingContainerView: View {
    let onComplete: () -> Void
    let authService: AuthService
    let onGoogleConnected: (@MainActor () -> Void)?
    let onGoogleConnectionFailed: (@MainActor (_ errorMessage: String) -> Void)?

    @State private var currentStep: OnboardingStep = .welcome
    @State private var isTransitioning: Bool = false
    @State private var didComplete: Bool = false

    private let transitionDuration: TimeInterval = 0.32
    private let stepAnimation: Animation = .spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.12)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.10),
                    Color(red: 0.10, green: 0.13, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                progressIndicator
                    .padding(.top, 8)

                Group {
                    if currentStep.isFirst {
                        OnboardingWowStepView(
                            onShowMore: { goToNextStepOrComplete() },
                            onSkipIntro: { goToNextStepOrComplete() },
                            isInteractionDisabled: isTransitioning || didComplete
                        )
                    } else {
                        stepContent
                    }
                }
                .frame(
                    maxWidth: currentStep.isFirst ? 1240 : 760,
                    minHeight: currentStep.isFirst ? nil : 420,
                    maxHeight: currentStep.isFirst ? nil : 560
                )
            }
            .id(currentStep)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                )
            )
            .padding(currentStep.isFirst ? 28 : 24)
            .padding(.vertical, 16)
            .background(containerBackground)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progressIndicator: some View {
        HStack(spacing: 10) {
            ForEach(OnboardingStep.allCases) { step in
                Circle()
                    .fill(step == currentStep ? Color.white : Color.white.opacity(0.35))
                    .frame(width: 8, height: 8)
                    .animation(stepAnimation, value: currentStep)
                    .accessibilityLabel(
                        L10n.tr(
                            "onboarding.progress.step",
                            step.index + 1,
                            OnboardingStep.allCases.count
                        )
                    )
            }
        }
    }

    private var stepContent: some View {
        Group {
            switch currentStep {
            case .features:
                OnboardingPrivateBetaStepView(
                    onBack: { goToPreviousStep() },
                    onEmailRequested: { completeOnboardingIfNeeded() },
                    onAlreadyEmailed: { goToNextStepOrComplete() },
                    isInteractionDisabled: isTransitioning || didComplete
                )
            case .connect:
                OnboardingGoogleConnectStepView(
                    authService: authService,
                    onNotNow: { completeOnboardingIfNeeded() },
                    onConnectRequested: { completeOnboardingIfNeeded() },
                    onConnected: {
                        onGoogleConnected?()
                    },
                    onConnectionFailed: { errorMessage in
                        onGoogleConnectionFailed?(errorMessage)
                    },
                    isInteractionDisabled: isTransitioning || didComplete
                )
            case .welcome:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var containerBackground: some View {
        if currentStep.isFirst {
            EmptyView()
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 32, x: 0, y: 20)
        }
    }

    private func goToPreviousStep() {
        guard isTransitioning == false else {
            return
        }
        guard let previous = currentStep.previous else {
            return
        }

        isTransitioning = true
        withAnimation(stepAnimation) {
            currentStep = previous
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(transitionDuration * 1_000_000_000))
            isTransitioning = false
        }
    }

    private func goToNextStepOrComplete() {
        guard isTransitioning == false else {
            return
        }

        if currentStep.isLast {
            completeOnboardingIfNeeded()
            return
        }

        guard let next = currentStep.next else {
            return
        }

        isTransitioning = true
        withAnimation(stepAnimation) {
            currentStep = next
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(transitionDuration * 1_000_000_000))
            isTransitioning = false
        }
    }

    private func completeOnboardingIfNeeded() {
        guard didComplete == false else {
            return
        }
        didComplete = true
        onComplete()
    }
}

#if DEBUG
#Preview {
    OnboardingContainerView(
        onComplete: {},
        authService: AuthService(),
        onGoogleConnected: nil,
        onGoogleConnectionFailed: nil
    )
}
#endif
