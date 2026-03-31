import AppKit
import SwiftUI

@MainActor
final class OnboardingCoordinator {
    private var onboardingWindows: [NSWindow] = []
    private let onboardingStateStore: OnboardingStateStore
    private let authService: AuthService

    init(onboardingStateStore: OnboardingStateStore, authService: AuthService) {
        self.onboardingStateStore = onboardingStateStore
        self.authService = authService
    }

    convenience init() {
        self.init(onboardingStateStore: OnboardingStateStore(), authService: AuthService())
    }

    func showOnboarding(
        onGoogleConnected: (@MainActor () -> Void)? = nil,
        onGoogleConnectionFailed: (@MainActor (_ errorMessage: String) -> Void)? = nil
    ) {
        guard onboardingWindows.isEmpty else {
            NSApp.activate(ignoringOtherApps: true)
            onboardingWindows.first?.makeKeyAndOrderFront(nil)
            return
        }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            print("[OnboardingCoordinator] No screen detected, onboarding skipped.")
            return
        }

        for screen in screens {
            let onboardingView = OnboardingContainerView(onComplete: { [weak self] in
                guard let self else { return }
                self.completeOnboarding()
            }, authService: authService, onGoogleConnected: onGoogleConnected, onGoogleConnectionFailed: onGoogleConnectionFailed)

            let hostingController = NSHostingController(rootView: onboardingView)
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.contentViewController = hostingController
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()

            onboardingWindows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissOnboarding() {
        guard !onboardingWindows.isEmpty else {
            return
        }

        for window in onboardingWindows {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        onboardingWindows.removeAll()
    }

    private func completeOnboarding() {
        onboardingStateStore.markCompleted()
        dismissOnboarding()
    }
}
