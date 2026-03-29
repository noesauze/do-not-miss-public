import AppKit
import SwiftUI

final class OverlayCoordinator {
    private var overlayWindows: [NSWindow] = []
    private let organizerContactService = OrganizerContactService()

    @MainActor
    func showOverlay(
        for event: CalendarEvent,
        onSnoozeRequested: ((CalendarEvent) -> Void)? = nil
    ) {
        // Replace any existing overlay to keep state predictable on double calls.
        dismissOverlay()

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            print("[OverlayCoordinator] No screen detected, overlay skipped.")
            return
        }

        for screen in screens {
            let viewModel = OverlayViewModel(
                event: event,
                onJoinNow: { [weak self] url in
                    _ = NSWorkspace.shared.open(url)
                    self?.dismissOverlay()
                },
                onSnooze: { [weak self] event in
                    onSnoozeRequested?(event)
                    print("[OverlayCoordinator] Snooze 2 min requested for event: \(event.title)")
                    self?.dismissOverlay()
                },
                onRunningLate: { [weak self] event in
                    guard let self else { return false }
                    guard let url = self.organizerContactService.makeRunningLateURL(for: event, minutesLate: 5) else {
                        print("[OverlayCoordinator] Running-late URL unavailable for event: \(event.title)")
                        return false
                    }

                    let opened = NSWorkspace.shared.open(url)
                    if opened {
                        self.dismissOverlay()
                    } else {
                        print("[OverlayCoordinator] Failed to open running-late URL for event: \(event.title)")
                    }
                    return opened
                },
                onOpenContact: { [weak self] event in
                    guard let self else { return false }
                    guard let url = self.organizerContactService.makeContactOrganizerURL(for: event) else {
                        print("[OverlayCoordinator] Organizer contact URL unavailable for event: \(event.title)")
                        return false
                    }

                    let opened = NSWorkspace.shared.open(url)
                    if opened {
                        self.dismissOverlay()
                    } else {
                        print("[OverlayCoordinator] Failed to open organizer contact URL for event: \(event.title)")
                    }
                    return opened
                },
                onClose: { [weak self] in
                    self?.dismissOverlay()
                }
            )

            let overlayView = OverlayView(viewModel: viewModel)
            let hostingController = NSHostingController(rootView: overlayView)
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            // Borderless + screenSaver level keeps the window above regular/fullscreen apps.
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

            overlayWindows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    func dismissOverlay() {
        guard !overlayWindows.isEmpty else {
            return
        }

        for window in overlayWindows {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        }

        overlayWindows.removeAll()
    }
}
