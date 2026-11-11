import SwiftUI

#if os(iOS)
import UIKit

/// Shows a SwiftUI view as a native sheet over Godot's view (iOS). Presenting a real view controller keeps
/// UIKit's touch handling separate from Godot's, and gives the standard swipe-down dismissal.
@MainActor
final class SheetPresenter: NSObject, UIAdaptivePresentationControllerDelegate {
    var onClosed: () -> Void = {}
    private var controller: UIViewController?

    init(title: String) { super.init() }

    func present<V: View>(_ view: V) {
        guard let top = Self.topMostViewController() else { return }
        let hosting = UIHostingController(rootView: view)
        hosting.modalPresentationStyle = .pageSheet
        hosting.presentationController?.delegate = self
        controller = hosting
        top.present(hosting, animated: true)
    }

    func dismiss(notify: Bool) {
        guard let c = controller else { return }
        controller = nil
        c.dismiss(animated: true) { [onClosed] in if notify { onClosed() } }
    }

    // The user swiped the sheet down.
    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        MainActor.assumeIsolated {
            controller = nil
            onClosed()
        }
    }

    /// Development aid; only implemented on macOS.
    func snapshot(to path: String) {}

    private static func topMostViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

#elseif os(macOS)
import AppKit

/// Shows a SwiftUI view in its own window (macOS).
@MainActor
final class SheetPresenter: NSObject, NSWindowDelegate {
    var onClosed: () -> Void = {}
    private var window: NSWindow?
    private let title: String
    private var notifyOnClose = true

    init(title: String) {
        self.title = title
        super.init()
    }

    func present<V: View>(_ view: V) {
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 640))
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func dismiss(notify: Bool) {
        notifyOnClose = notify
        window?.close()
    }

    /// Development aid: save a picture of just this window (by its window number; the rest of the desktop is
    /// not captured) as a PNG, with the system's screencapture tool.
    func snapshot(to path: String) {
        guard let window else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
        try? task.run()
        task.waitUntilExit()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        if notifyOnClose { onClosed() }
        notifyOnClose = true
    }
}
#endif
