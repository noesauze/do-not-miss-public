import SwiftUI

struct OnboardingGoogleConnectStepView: View {
    let authService: AuthService
    let onNotNow: () -> Void
    let onConnectRequested: () -> Void
    let onConnected: () -> Void
    let onConnectionFailed: (String) -> Void
    let isInteractionDisabled: Bool

    @State private var isConnecting: Bool = false
    @State private var alreadyConnectedMessage: String?

    private var isButtonDisabled: Bool {
        isInteractionDisabled || isConnecting
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack {
                    Spacer(minLength: 0)

                    VStack(spacing: 26) {
                        googleBadge

                        Text(L10n.tr("onboarding.google_connect.title"))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(L10n.tr("onboarding.google_connect.subtitle"))
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.86))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 640)
                            .fixedSize(horizontal: false, vertical: true)

                        usageCard

                        if let alreadyConnectedMessage {
                            statusMessageView(
                                text: alreadyConnectedMessage,
                                foregroundColor: Color(red: 0.73, green: 0.95, blue: 0.80),
                                fillColor: Color.green.opacity(0.18),
                                strokeColor: Color.green.opacity(0.42)
                            )
                        }

                        HStack(spacing: 12) {
                            Button {
                                connectWithGoogle()
                            } label: {
                                HStack(spacing: 8) {
                                    if isConnecting {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(.white)
                                    }

                                    Text(isConnecting
                                        ? L10n.tr("onboarding.google_connect.action.connecting")
                                        : L10n.tr("onboarding.google_connect.action.connect")
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .keyboardShortcut(.defaultAction)
                            .tint(Color(red: 0.18, green: 0.58, blue: 0.98))
                            .disabled(isButtonDisabled)

                            Button(L10n.tr("onboarding.google_connect.action.not_now")) {
                                onNotNow()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(isButtonDisabled)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)

                    Spacer(minLength: 0)
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .task {
            updateAlreadyConnectedMessage()
        }
    }

    private var googleBadge: some View {
        Text(L10n.tr("onboarding.google_connect.badge"))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color(red: 0.63, green: 0.80, blue: 1.0))
            .tracking(1.1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("onboarding.google_connect.usage.title"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))

            usageRow(text: L10n.tr("onboarding.google_connect.usage.fullscreen"), systemImage: "rectangle.inset.filled.and.person.filled")
            usageRow(text: L10n.tr("onboarding.google_connect.usage.weekly_review"), systemImage: "checklist")
            usageRow(text: L10n.tr("onboarding.google_connect.usage.actions"), systemImage: "paperplane.fill")
        }
        .frame(maxWidth: 640, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private func usageRow(text: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.86))
                .frame(width: 16, alignment: .leading)

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusMessageView(
        text: String,
        foregroundColor: Color,
        fillColor: Color,
        strokeColor: Color
    ) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .frame(maxWidth: 640)
    }

    private func updateAlreadyConnectedMessage() {
        guard authService.isSignedIn else {
            alreadyConnectedMessage = nil
            return
        }

        alreadyConnectedMessage = L10n.tr(
            "onboarding.google_connect.status.already_connected",
            authService.connectedAccountDescription
        )
    }

    private func connectWithGoogle() {
        guard isButtonDisabled == false else {
            return
        }

        isConnecting = true
        onConnectRequested()

        Task { @MainActor in
            defer {
                isConnecting = false
            }

            if authService.isSignedIn {
                onConnected()
                return
            }

            do {
                try await authService.signIn()
                onConnected()
            } catch {
                onConnectionFailed(error.localizedDescription)
            }
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingGoogleConnectStepView(
            authService: AuthService(),
            onNotNow: {},
            onConnectRequested: {},
            onConnected: {},
            onConnectionFailed: { _ in },
            isInteractionDisabled: false
        )
        .padding(24)
    }
}
#endif
