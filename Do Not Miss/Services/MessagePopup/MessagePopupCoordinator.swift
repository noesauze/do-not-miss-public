import AppKit
import SwiftUI

@MainActor
final class MessagePopupCoordinator {
    private var popupWindow: MessagePopupWindow?
    private var windowDelegateProxy: MessagePopupWindowDelegate?
    private var onDismiss: (() -> Void)?
    private var onDidShow: (() -> Void)?
    private var isDismissing: Bool = false
    private var hasNotifiedDidShowForCurrentPresentation: Bool = false

    var isPopupVisible: Bool {
        popupWindow?.isVisible == true
    }

    func present(
        title: String,
        bodyText: String,
        ctaLabel: String?,
        onDismiss: @escaping () -> Void,
        onDidShow: @escaping () -> Void,
        onCTATap: @escaping () -> Void
    ) {
        if isPopupVisible {
            popupWindow?.makeKeyAndOrderFront(nil)
            popupWindow?.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        self.onDismiss = onDismiss
        self.onDidShow = onDidShow
        hasNotifiedDidShowForCurrentPresentation = false

        let popupView = MessagePopupView(
            title: title,
            bodyText: bodyText,
            ctaLabel: ctaLabel,
            onDismiss: { [weak self] in
                self?.dismiss()
            },
            onCTATap: onCTATap
        )

        let hostingController = NSHostingController(rootView: popupView)
        let fittingSize = hostingController.view.fittingSize
        let contentSize = NSSize(
            width: max(420, min(560, fittingSize.width)),
            height: max(200, min(420, fittingSize.height))
        )

        let window = MessagePopupWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let delegateProxy = MessagePopupWindowDelegate(
            onWindowCloseRequest: { [weak self] in
                self?.dismiss()
            },
            onWindowDidBecomeKey: { [weak self] in
                self?.notifyDidShowIfNeeded()
            }
        )

        window.delegate = delegateProxy
        window.title = "DoNotMiss"
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace]
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentViewController = hostingController
        window.setContentSize(contentSize)
        window.setFrame(centeredFrame(forContentSize: contentSize, window: window), display: false)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        popupWindow = window
        windowDelegateProxy = delegateProxy

        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self] in
            self?.notifyDidShowIfNeeded()
        }
    }

    func dismiss() {
        dismiss(triggeredByWindowClose: false)
    }

    private func dismiss(triggeredByWindowClose: Bool) {
        guard isDismissing == false else {
            return
        }

        guard let window = popupWindow else {
            onDismiss?()
            onDismiss = nil
            onDidShow = nil
            hasNotifiedDidShowForCurrentPresentation = false
            return
        }

        isDismissing = true

        window.delegate = nil
        window.contentViewController = nil
        if triggeredByWindowClose == false {
            window.orderOut(nil)
        }

        popupWindow = nil
        windowDelegateProxy = nil
        onDidShow = nil
        hasNotifiedDidShowForCurrentPresentation = false

        let completion = onDismiss
        onDismiss = nil
        isDismissing = false
        DispatchQueue.main.async {
            completion?()
        }
    }
}

private extension MessagePopupCoordinator {
    func centeredFrame(forContentSize contentSize: NSSize, window: NSWindow) -> NSRect {
        let screen = activeScreen() ?? NSScreen.main ?? NSScreen.screens.first
        let referenceFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let fullFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        let originX = referenceFrame.midX - (fullFrame.width / 2)
        let originY = referenceFrame.midY - (fullFrame.height / 2)
        return NSRect(x: originX, y: originY, width: fullFrame.width, height: fullFrame.height)
    }

    func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
    }

    func notifyDidShowIfNeeded() {
        guard hasNotifiedDidShowForCurrentPresentation == false else {
            return
        }

        guard popupWindow?.isVisible == true else {
            return
        }

        hasNotifiedDidShowForCurrentPresentation = true
        onDidShow?()
    }
}

private final class MessagePopupWindowDelegate: NSObject, NSWindowDelegate {
    private let onWindowCloseRequest: () -> Void
    private let onWindowDidBecomeKey: () -> Void

    init(
        onWindowCloseRequest: @escaping () -> Void,
        onWindowDidBecomeKey: @escaping () -> Void
    ) {
        self.onWindowCloseRequest = onWindowCloseRequest
        self.onWindowDidBecomeKey = onWindowDidBecomeKey
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onWindowCloseRequest()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        onWindowCloseRequest()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onWindowDidBecomeKey()
    }
}

private final class MessagePopupWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}
