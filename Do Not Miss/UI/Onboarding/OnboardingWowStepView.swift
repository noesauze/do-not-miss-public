import SwiftUI

struct OnboardingWowStepView: View {
    let onShowMore: () -> Void
    let onSkipIntro: () -> Void
    let isInteractionDisabled: Bool

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 1180

            ZStack {
                decorativeBackground

                VStack(spacing: 34) {
                    headline

                    if isCompact {
                        VStack(spacing: 20) {
                            fullscreenAlertDemoCard
                            runningLateDemoCard
                            weeklySwipeDemoCard
                        }
                    } else {
                        HStack(spacing: 20) {
                            fullscreenAlertDemoCard
                            runningLateDemoCard
                            weeklySwipeDemoCard
                        }
                    }

                    ctaRow
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, isCompact ? 16 : 24)
                .padding(.top, 28)
                .padding(.bottom, 28)
            }
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .frame(minHeight: 670)
    }

    private var headline: some View {
        VStack(spacing: 16) {
            Text(L10n.tr("onboarding.wow.headline.title"))
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(L10n.tr("onboarding.wow.headline.subtitle"))
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.86))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 930)
        }
    }

    private var fullscreenAlertDemoCard: some View {
        OnboardingDemoCard(
            title: L10n.tr("onboarding.wow.card.fullscreen.title"),
            subtitle: L10n.tr("onboarding.wow.card.fullscreen.subtitle")
        ) {
            OnboardingFullscreenAlertDemoView()
        }
    }

    private var runningLateDemoCard: some View {
        OnboardingDemoCard(
            title: L10n.tr("onboarding.wow.card.running_late.title"),
            subtitle: L10n.tr("onboarding.wow.card.running_late.subtitle")
        ) {
            OnboardingRunningLateDemoView()
        }
    }

    private var weeklySwipeDemoCard: some View {
        OnboardingDemoCard(
            title: L10n.tr("onboarding.wow.card.swipe.title"),
            subtitle: L10n.tr("onboarding.wow.card.swipe.subtitle")
        ) {
            OnboardingWeeklySwipeDemoView()
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 12) {
            Button(L10n.tr("onboarding.wow.action.skip_intro")) {
                onSkipIntro()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .foregroundStyle(Color.white.opacity(0.88))
            .tint(Color.white.opacity(0.40))
            .disabled(isInteractionDisabled)

            Button(L10n.tr("onboarding.wow.action.show_me_more")) {
                onShowMore()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .tint(Color(red: 0.18, green: 0.58, blue: 0.98))
            .disabled(isInteractionDisabled)
        }
        .padding(.top, 10)
    }

    private var decorativeBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.07, blue: 0.13),
                            Color(red: 0.07, green: 0.10, blue: 0.16),
                            Color(red: 0.04, green: 0.05, blue: 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color(red: 0.26, green: 0.50, blue: 0.98).opacity(0.40))
                .frame(width: 420, height: 420)
                .blur(radius: 135)
                .offset(x: -360, y: -240)

            Circle()
                .fill(Color(red: 0.99, green: 0.58, blue: 0.19).opacity(0.25))
                .frame(width: 320, height: 320)
                .blur(radius: 120)
                .offset(x: 390, y: -180)

            Circle()
                .fill(Color(red: 0.31, green: 0.80, blue: 0.64).opacity(0.24))
                .frame(width: 380, height: 380)
                .blur(radius: 145)
                .offset(x: 280, y: 210)
        }
    }
}

private struct OnboardingDemoCard<DemoContent: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let demoContent: DemoContent

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.78))
            }

            demoContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.black.opacity(0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(isHovered ? 0.28 : 0.14), lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.012 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.36 : 0.24), radius: isHovered ? 28 : 20, x: 0, y: isHovered ? 18 : 12)
        .animation(.easeOut(duration: 0.18), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct OnboardingFullscreenAlertDemoView: View {
    @StateObject private var demoViewModel = OverlayViewModel(
        event: CalendarEvent(
            id: "onboarding-overlay-preview",
            title: L10n.tr("onboarding.wow.demo.overlay.event_title"),
            startDate: Date().addingTimeInterval(120),
            endDate: Date().addingTimeInterval(2_400),
            videoLink: URL(string: "https://meet.google.com/abc-defg-hij"),
            videoProvider: "Google Meet",
            notes: L10n.tr("onboarding.wow.demo.overlay.notes"),
            organizerName: L10n.tr("onboarding.wow.demo.overlay.organizer_name"),
            organizerEmail: "nora@example.com",
            attendees: [
                EventAttendee(name: "Nora Chen", email: "nora@example.com", responseStatus: "accepted", isOrganizer: true, isSelf: false),
                EventAttendee(name: "You", email: "you@example.com", responseStatus: "accepted", isOrganizer: false, isSelf: true)
            ],
            userResponseStatus: .accepted
        ),
        onJoinNow: { _ in },
        onSnooze: { _ in },
        onRunningLate: { _ in true },
        onOpenContact: { _ in true },
        onClose: {}
    )

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.10, blue: 0.16),
                    Color(red: 0.05, green: 0.07, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            GeometryReader { geometry in
                let referenceSize = CGSize(width: 760, height: 560)
                let fittedScale = min(
                    geometry.size.width / referenceSize.width,
                    geometry.size.height / referenceSize.height
                )
                let clampedScale = min(max(fittedScale, 0.40), 1.0)
                let fittedWidth = referenceSize.width * clampedScale
                let fittedHeight = referenceSize.height * clampedScale

                OverlayView(viewModel: demoViewModel, showsBackdrop: false)
                    .frame(width: referenceSize.width, height: referenceSize.height)
                    .scaleEffect(clampedScale, anchor: .center)
                    .frame(width: fittedWidth, height: fittedHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .clipped()
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct OnboardingRunningLateDemoView: View {
    @StateObject private var demoViewModel = OverlayViewModel(
        event: CalendarEvent(
            id: "onboarding-running-late-preview",
            title: L10n.tr("onboarding.wow.demo.running_late.event_title"),
            startDate: Date().addingTimeInterval(300),
            endDate: Date().addingTimeInterval(3_000),
            videoLink: URL(string: "https://zoom.us/j/123456789"),
            videoProvider: "Zoom",
            organizerName: L10n.tr("onboarding.wow.demo.running_late.organizer_name"),
            organizerEmail: "alex@example.com",
            attendees: [
                EventAttendee(name: "Alex Martin", email: "alex@example.com", responseStatus: "accepted", isOrganizer: true, isSelf: false)
            ],
            userResponseStatus: .needsAction
        ),
        onJoinNow: { _ in },
        onSnooze: { _ in },
        onRunningLate: { _ in true },
        onOpenContact: { _ in true },
        onClose: {}
    )

    @State private var didTap: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.10, blue: 0.16),
                    Color(red: 0.05, green: 0.07, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("onboarding.wow.demo.running_late.event_title"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Text(L10n.tr("onboarding.wow.demo.running_late.starts_in"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.80))

                HStack(spacing: 10) {
                    Button {
                        demoViewModel.runningLateTapped()
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.80)) {
                            didTap = true
                        }

                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 550_000_000)
                            withAnimation(.easeOut(duration: 0.20)) {
                                didTap = false
                            }
                        }
                    } label: {
                        Label(L10n.tr("onboarding.wow.demo.running_late.button_running_late"), systemImage: "hare.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.95, green: 0.46, blue: 0.20))

                    Button(L10n.tr("onboarding.wow.demo.running_late.button_contact")) {
                        demoViewModel.openContactTapped()
                    }
                    .buttonStyle(.bordered)
                }

                if let feedback = demoViewModel.actionFeedback {
                    Text(feedback)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(18)
            .scaleEffect(didTap ? 1.02 : 1.0)
        }
    }
}

private struct OnboardingWeeklySwipeDemoView: View {
    @StateObject private var cardViewModel = WeeklyReviewCardViewModel()
    @State private var currentIndex: Int = 0
    @State private var latestDecision: WeeklyReviewDecision?

    private let events: [CalendarEvent] = [
        CalendarEvent(
            id: "weekly-demo-1",
            title: L10n.tr("onboarding.wow.demo.swipe.event_1.title"),
            startDate: Date().addingTimeInterval(86_400),
            endDate: Date().addingTimeInterval(89_400),
            videoLink: URL(string: "https://meet.google.com/aaa-bbbb-ccc"),
            videoProvider: "Google Meet",
            notes: L10n.tr("onboarding.wow.demo.swipe.event_1.notes"),
            location: L10n.tr("onboarding.wow.demo.swipe.event_1.location"),
            organizerName: L10n.tr("onboarding.wow.demo.swipe.event_1.organizer_name"),
            organizerEmail: "sophie@example.com",
            attendees: [
                EventAttendee(name: "Sophie", email: "sophie@example.com", responseStatus: "accepted", isOrganizer: true, isSelf: false),
                EventAttendee(name: "You", email: "you@example.com", responseStatus: "needsAction", isOrganizer: false, isSelf: true)
            ],
            userResponseStatus: .needsAction
        ),
        CalendarEvent(
            id: "weekly-demo-2",
            title: L10n.tr("onboarding.wow.demo.swipe.event_2.title"),
            startDate: Date().addingTimeInterval(172_800),
            endDate: Date().addingTimeInterval(175_200),
            videoLink: URL(string: "https://zoom.us/j/987654321"),
            videoProvider: "Zoom",
            notes: L10n.tr("onboarding.wow.demo.swipe.event_2.notes"),
            location: L10n.tr("onboarding.wow.demo.swipe.event_2.location"),
            organizerName: L10n.tr("onboarding.wow.demo.swipe.event_2.organizer_name"),
            organizerEmail: "mika@example.com",
            attendees: [
                EventAttendee(name: "Mika", email: "mika@example.com", responseStatus: "accepted", isOrganizer: true, isSelf: false)
            ],
            userResponseStatus: .tentative
        ),
        CalendarEvent(
            id: "weekly-demo-3",
            title: L10n.tr("onboarding.wow.demo.swipe.event_3.title"),
            startDate: Date().addingTimeInterval(259_200),
            endDate: Date().addingTimeInterval(261_000),
            videoLink: nil,
            notes: L10n.tr("onboarding.wow.demo.swipe.event_3.notes"),
            location: L10n.tr("onboarding.wow.demo.swipe.event_3.location"),
            organizerName: L10n.tr("onboarding.wow.demo.swipe.event_3.organizer_name"),
            organizerEmail: "jules@example.com",
            attendees: [
                EventAttendee(name: "Jules", email: "jules@example.com", responseStatus: "accepted", isOrganizer: true, isSelf: false)
            ],
            userResponseStatus: .needsAction
        )
    ]

    private var currentEvent: CalendarEvent {
        events[currentIndex]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.14),
                    Color(red: 0.04, green: 0.05, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 10) {
                GeometryReader { geometry in
                    let referenceSize = CGSize(width: 920, height: 420)
                    let fittedScale = min(
                        geometry.size.width / referenceSize.width,
                        geometry.size.height / referenceSize.height
                    )
                    let clampedScale = min(max(fittedScale, 0.34), 1.0)
                    let fittedWidth = referenceSize.width * clampedScale
                    let fittedHeight = referenceSize.height * clampedScale

                    WeeklyReviewCardView(
                        event: currentEvent,
                        viewModel: cardViewModel,
                        onDecisionRequested: { decision in
                            latestDecision = decision
                            currentIndex = (currentIndex + 1) % events.count
                        }
                    )
                    .frame(width: referenceSize.width, height: referenceSize.height)
                    .scaleEffect(clampedScale, anchor: .center)
                    .frame(width: fittedWidth, height: fittedHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: 250)

                HStack(spacing: 8) {
                    decisionButton(title: L10n.tr("onboarding.wow.demo.swipe.action.decline"), systemImage: "xmark", decision: .decline, tint: .red)
                    decisionButton(title: L10n.tr("onboarding.wow.demo.swipe.action.tentative"), systemImage: "questionmark", decision: .tentative, tint: .orange)
                    decisionButton(title: L10n.tr("onboarding.wow.demo.swipe.action.accept"), systemImage: "checkmark", decision: .accept, tint: .green)
                }

                if let latestDecision {
                    Text(L10n.tr("onboarding.wow.demo.swipe.last_action", latestDecision.localizedLabel))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.82))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
    }

    private func decisionButton(
        title: String,
        systemImage: String,
        decision: WeeklyReviewDecision,
        tint: Color
    ) -> some View {
        Button {
            cardViewModel.trigger(decision: decision) { chosenDecision in
                latestDecision = chosenDecision
                currentIndex = (currentIndex + 1) % events.count
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(minWidth: 110)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(tint)
        .foregroundStyle(.white)
        .disabled(cardViewModel.isInteractionLocked)
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingWowStepView(onShowMore: {}, onSkipIntro: {}, isInteractionDisabled: false)
            .padding(24)
    }
}
#endif
