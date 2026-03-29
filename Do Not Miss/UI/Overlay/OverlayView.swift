import SwiftUI

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.88),
                    Color(red: 0.07, green: 0.08, blue: 0.12).opacity(0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Text("Upcoming event")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )

                Text(viewModel.resolvedTitle)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)
                    .accessibilityLabel("Event title: \(viewModel.resolvedTitle)")

                Text(viewModel.formattedStartTime)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .accessibilityLabel("Starts at \(viewModel.formattedStartTime)")

                Text(viewModel.countdownText)
                    .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .accessibilityLabel(viewModel.countdownText)

                if let provider = viewModel.providerDisplayName {
                    Text(provider)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        actionButton(
                            title: "Join now",
                            action: viewModel.joinNowTapped,
                            isPrimary: true,
                            isEnabled: viewModel.joinActionAvailability.isEnabled
                        )
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel(Text("overlay.accessibility.join_video_call"))

                        actionButton(
                            title: "Snooze 2 min",
                            action: viewModel.snoozeTapped
                        )
                    }

                    HStack(spacing: 10) {
                        actionButton(
                            title: "Running 5 min late",
                            action: viewModel.runningLateTapped,
                            isEnabled: viewModel.runningLateAvailability.isEnabled
                        )

                        actionButton(
                            title: "Open chat/email",
                            action: viewModel.openContactTapped,
                            isEnabled: viewModel.openContactAvailability.isEnabled
                        )
                    }
                }

                if let actionFeedback = viewModel.actionFeedback {
                    Text(actionFeedback)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.82))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.1))
                        )
                }

                Button("Close") {
                    viewModel.closeTapped()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(Text("overlay.accessibility.close"))
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 760)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.17).opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 36, x: 0, y: 20)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.startCountdown()
        }
        .onDisappear {
            viewModel.stopCountdown()
        }
    }
}

#if DEBUG
#Preview {
    OverlayView(
        viewModel: OverlayViewModel(
            event: CalendarEvent(
                id: "preview",
                title: "Review Sprint",
                startDate: Date().addingTimeInterval(120),
                endDate: Date().addingTimeInterval(1_800),
                videoLink: URL(string: "https://meet.google.com/abc-defg-hij"),
                videoProvider: "Google Meet"
            ),
            onJoinNow: { _ in },
            onSnooze: { _ in },
            onRunningLate: { _ in false },
            onOpenContact: { _ in false },
            onClose: {},
        )
    )
}
#endif

private extension OverlayView {
    @ViewBuilder
    func actionButton(
        title: String,
        action: @escaping () -> Void,
        isPrimary: Bool = false,
        isEnabled: Bool = true
    ) -> some View {
        Group {
            if isPrimary {
                Button(title, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.19, green: 0.56, blue: 1.0))
            } else {
                Button(title, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .disabled(isEnabled == false)
    }
}
