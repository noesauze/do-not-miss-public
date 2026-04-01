import AppKit
import SwiftUI

@MainActor
final class WeeklyReviewCoordinator {
    private var reviewWindow: NSWindow?
    private var reviewSession: WeeklyReviewSession?
    private var windowDelegateProxy: WeeklyReviewWindowDelegate?
    private var onSessionEnded: ((WeeklyReviewResult) -> Void)?
    private var isDismissing: Bool = false
    private var isStarting: Bool = false

    var isReviewActive: Bool {
        guard let reviewWindow else {
            return false
        }
        return reviewWindow.isVisible
    }

    func startReview(
        events: [CalendarEvent],
        calendarService: CalendarService,
        onSessionEnded: @escaping (WeeklyReviewResult) -> Void
    ) {
        guard isStarting == false else {
            log("Ignored start request: already starting")
            return
        }

        guard isDismissing == false else {
            log("Ignored start request: dismissal in progress")
            return
        }

        isStarting = true
        defer { isStarting = false }
        log("Start requested with \(events.count) event(s)")

        recoverIfNeeded()

        if isReviewActive {
            if bringToFront() {
                log("Start skipped: review already active")
                return
            }
        }

        let session = WeeklyReviewSession(events: events, calendarService: calendarService)
        self.reviewSession = session
        self.onSessionEnded = onSessionEnded

        let reviewView = WeeklyReviewView(
            session: session,
            onClose: { [weak self] in
                self?.dismissReview()
            }
        )

        let hostingController = NSHostingController(rootView: reviewView)
        let targetScreen = NSScreen.main ?? NSScreen.screens.first
        let frame = targetScreen?.frame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)

        let window = WeeklyReviewWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )

        let delegateProxy = WeeklyReviewWindowDelegate(onWindowWillClose: { [weak self] in
            self?.dismissReview(triggeredByWindowClose: true)
        })

        window.delegate = delegateProxy
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary, .stationary]
        window.backgroundColor = NSColor.black
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        self.windowDelegateProxy = delegateProxy
        self.reviewWindow = window

        NSApp.activate(ignoringOtherApps: true)
        log("Window created and brought to front")
    }

    @discardableResult
    func bringToFront() -> Bool {
        recoverIfNeeded()

        guard let reviewWindow else {
            log("Bring-to-front failed: no window")
            return false
        }

        guard reviewWindow.contentViewController != nil else {
            cleanupWindowState(closeWindow: true)
            log("Bring-to-front failed: stale window state cleaned")
            return false
        }

        reviewWindow.makeKeyAndOrderFront(nil)
        reviewWindow.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        log("Window brought to front")
        return true
    }

    func dismissReview() {
        dismissReview(triggeredByWindowClose: false)
    }

    private func dismissReview(triggeredByWindowClose: Bool) {
        guard isDismissing == false else {
            log("Dismiss ignored: already dismissing")
            return
        }

        guard let reviewSession else {
            cleanupWindowState(closeWindow: triggeredByWindowClose == false)
            log("Dismiss completed without active session")
            return
        }

        log("Dismiss requested [triggeredByWindowClose: \(triggeredByWindowClose)]")
        isDismissing = true

        let reason: WeeklyReviewEndReason = reviewSession.isCompleted ? .completed : .cancelled
        let result = reviewSession.buildResult(endReason: reason)
        let completion = onSessionEnded

        cleanupWindowState(closeWindow: triggeredByWindowClose == false)

        isDismissing = false
        completion?(result)
        log("Dismiss completed")
    }

    private func cleanupWindowState(closeWindow: Bool) {
        let window = reviewWindow
        window?.delegate = nil

        if closeWindow, let window {
            window.orderOut(nil)
            window.contentViewController = nil
            window.close()
        } else {
            window?.contentViewController = nil
        }

        reviewWindow = nil
        reviewSession = nil
        windowDelegateProxy = nil

        onSessionEnded = nil
        log("Window/session state cleaned [closeWindow: \(closeWindow)]")
    }

    private func recoverIfNeeded() {
        guard let reviewWindow else {
            return
        }

        if reviewWindow.contentViewController == nil || reviewWindow.isVisible == false {
            log("Recovering stale window state")
            cleanupWindowState(closeWindow: true)
        }
    }

    private func log(_ message: String) {
        print("[WeeklyReview][Coordinator] \(message)")
    }
}

private final class WeeklyReviewWindowDelegate: NSObject, NSWindowDelegate {
    private let onWindowWillClose: () -> Void

    init(onWindowWillClose: @escaping () -> Void) {
        self.onWindowWillClose = onWindowWillClose
    }

    func windowWillClose(_ notification: Notification) {
        onWindowWillClose()
    }
}
private final class WeeklyReviewWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}
