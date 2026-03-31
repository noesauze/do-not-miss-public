import AppKit
import SwiftUI

struct OnboardingPrivateBetaStepView: View {
    let onBack: () -> Void
    let onEmailRequested: () -> Void
    let onAlreadyEmailed: () -> Void
    let isInteractionDisabled: Bool

    @State private var localErrorMessage: String?
    @State private var isOpeningEmail: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack {
                    Spacer(minLength: 0)

                    VStack(spacing: 28) {
                        privateBetaBadge

                        Text(L10n.tr("onboarding.private_beta.title"))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(L10n.tr("onboarding.private_beta.subtitle"))
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 620)
                            .fixedSize(horizontal: false, vertical: true)

                        if let localErrorMessage {
                            Text(localErrorMessage)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.76))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.red.opacity(0.20))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.red.opacity(0.45), lineWidth: 1)
                                )
                                .frame(maxWidth: 620)
                        }

                        HStack(spacing: 12) {
                            Button(L10n.tr("onboarding.action.back")) {
                                onBack()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(isInteractionDisabled)

                            Button(L10n.tr("onboarding.private_beta.action.email")) {
                                openBetaRegistrationEmail()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(Color(red: 0.18, green: 0.58, blue: 0.98))
                            .disabled(isInteractionDisabled || isOpeningEmail)

                            Button(L10n.tr("onboarding.private_beta.action.already_emailed")) {
                                onAlreadyEmailed()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(isInteractionDisabled)
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
    }

    private var privateBetaBadge: some View {
        Text(L10n.tr("onboarding.private_beta.badge"))
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

    private func openBetaRegistrationEmail() {
        guard isOpeningEmail == false else {
            return
        }

        onEmailRequested()

        localErrorMessage = nil
        isOpeningEmail = true

        defer {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                isOpeningEmail = false
            }
        }

        let subject = L10n.tr("onboarding.private_beta.mail.subject")
        let body = L10n.tr("onboarding.private_beta.mail.body")

        guard var components = URLComponents(string: "mailto:noesauzede@gmail.com") else {
            localErrorMessage = L10n.tr("onboarding.private_beta.error.prepare_email")
            print("[OnboardingPrivateBetaStepView] Failed to create mailto URL components.")
            return
        }

        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]

        guard let mailtoURL = components.url else {
            localErrorMessage = L10n.tr("onboarding.private_beta.error.prepare_email")
            print("[OnboardingPrivateBetaStepView] Failed to encode mailto URL.")
            return
        }

        let didOpen = NSWorkspace.shared.open(mailtoURL)
        if didOpen == false {
            localErrorMessage = L10n.tr("onboarding.private_beta.error.open_mail")
            print("[OnboardingPrivateBetaStepView] Unable to open mailto URL: \(mailtoURL.absoluteString)")
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingPrivateBetaStepView(onBack: {}, onEmailRequested: {}, onAlreadyEmailed: {}, isInteractionDisabled: false)
            .padding(24)
    }
}
#endif
