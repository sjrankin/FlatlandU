import SwiftUI

#if os(iOS)
import UIKit

/// Shows a SwiftUI view as a screen over Godot's. On iOS it is a native sheet (presenting a real view controller
/// keeps UIKit's touch handling separate from Godot's and gives the standard swipe-down dismissal); on macOS it is a
/// window of its own.
@MainActor
final class SheetPresenter: NSObject, UIAdaptivePresentationControllerDelegate {
    /// Called when the screen has gone away (closed by the user or by `dismiss` with notification).
    var onClosed: () -> Void = {}
    /// iOS: the view controller showing the sheet; nil when none.
    private var controller: UIViewController?

    /// Creates the presenter.
    ///
    /// - Parameter title: the window title (macOS; the sheet on iOS has none of its own).
    init(title: String) { super.init() }

    /// Puts the view on screen: a page sheet over the top-most view controller (iOS), or a 520 by 640 titled,
    /// closable, resizable window in the middle of the screen (macOS).
    ///
    /// - Parameter view: the SwiftUI view to show.
    func present<V: View>(_ view: V) {
        guard let top = Self.topMostViewController() else { return }
        let hosting = UIHostingController(rootView: view)
        hosting.modalPresentationStyle = .pageSheet
        hosting.presentationController?.delegate = self
        controller = hosting
        top.present(hosting, animated: true)
    }

    /// Closes the screen.
    ///
    /// - Parameter notify: true to call `onClosed` afterwards; false when Godot asked for the close or is replacing
    /// the screen.
    func dismiss(notify: Bool) {
        guard let c = controller else { return }
        controller = nil
        c.dismiss(animated: true) { [onClosed] in if notify { onClosed() } }
    }

    // The user swiped the sheet down.
    /// iOS: the user swiped the sheet down; forgets the controller and calls `onClosed`.
    ///
    /// - Parameter presentationController: the sheet's presentation controller (unused).
    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        MainActor.assumeIsolated {
            controller = nil
            onClosed()
        }
    }

    /// Development aid: saves a picture of just this window (found by its window number, so the rest of the desktop
    /// is not captured) as a PNG with the system's screencapture tool. Only implemented on macOS; does nothing on
    /// iOS.
    ///
    /// - Parameter path: where to save the PNG.
    func snapshot(to path: String) {}

    /// iOS: the view controller to present from: the key window's root view controller, followed along any sheet
    /// already presented.
    ///
    /// - Returns: the controller, or nil if there is no active window scene.
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

/// Shows a SwiftUI view as a screen over Godot's. On iOS it is a native sheet (presenting a real view controller
/// keeps UIKit's touch handling separate from Godot's and gives the standard swipe-down dismissal); on macOS it is a
/// window of its own.
@MainActor
final class SheetPresenter: NSObject, NSWindowDelegate {
    /// Called when the screen has gone away (closed by the user or by `dismiss` with notification).
    var onClosed: () -> Void = {}
    /// macOS: the window showing the screen; nil when closed.
    private var window: NSWindow?
    /// macOS: the window's title.
    private let title: String
    /// macOS: whether closing the window should call `onClosed` (false when Godot asked for the close).
    private var notifyOnClose = true

    /// Creates the presenter.
    ///
    /// - Parameter title: the window title (macOS; the sheet on iOS has none of its own).
    init(title: String) {
        self.title = title
        super.init()
    }

    /// Puts the view on screen: a page sheet over the top-most view controller (iOS), or a 520 by 640 titled,
    /// closable, resizable window in the middle of the screen (macOS).
    ///
    /// - Parameter view: the SwiftUI view to show.
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

    /// Closes the screen.
    ///
    /// - Parameter notify: true to call `onClosed` afterwards; false when Godot asked for the close or is replacing
    /// the screen.
    func dismiss(notify: Bool) {
        notifyOnClose = notify
        window?.close()
    }

    /// Development aid: saves a picture of just this window (found by its window number, so the rest of the desktop
    /// is not captured) as a PNG with the system's screencapture tool. Only implemented on macOS; does nothing on
    /// iOS.
    ///
    /// - Parameter path: where to save the PNG.
    func snapshot(to path: String) {
        guard let window else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
        try? task.run()
        task.waitUntilExit()
    }

    /// macOS: the window is closing: forgets it and calls `onClosed` unless the close was Godot's own request.
    ///
    /// - Parameter notification: the close notification (unused).
    func windowWillClose(_ notification: Notification) {
        window = nil
        if notifyOnClose { onClosed() }
        notifyOnClose = true
    }
}
#endif
