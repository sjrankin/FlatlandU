import Foundation

#if os(macOS)
import AppKit

/// macOS: tells Godot whether anything it draws could be seen. While the display sleeps, the screen is locked, or the
/// window is minimized or completely covered, macOS stops presenting frames. If Godot keeps rendering, its Metal
/// driver eventually waits on a frame that never completes ("timeout waiting for fence") and the app aborts, which
/// happened after about 41 hours. PowerManager polls [method FlatlandNativeUI.windowIsShown] and stops the render
/// loop while it is false. Everything here runs on the main thread, where Godot calls it.
final class DisplayWatch: @unchecked Sendable {
    static let shared = DisplayWatch()

    /// True from the display going to sleep (or the session being switched away or locked) until it wakes.
    nonisolated(unsafe) private var asleep = false
    nonisolated(unsafe) private var observing = false

    /// Starts listening for sleep, wake and screen-lock notifications; does nothing after the first call.
    private func startObserving() {
        guard !observing else { return }
        observing = true
        let center = NSWorkspace.shared.notificationCenter
        let changes: [(NSNotification.Name, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, true),
            (NSWorkspace.screensDidWakeNotification, false),
            (NSWorkspace.willSleepNotification, true),
            (NSWorkspace.didWakeNotification, false),
            (NSWorkspace.sessionDidResignActiveNotification, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, false),
        ]
        for (name, sleeping) in changes {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.asleep = sleeping
            }
        }
    }

    /// Whether Godot's window is on screen to be seen.
    ///
    /// - Returns: false while the display sleeps, the screen is locked, or Godot's window is minimized or fully
    ///   covered; true otherwise, and also whenever the window cannot be found (so a failure here never stops drawing).
    func windowIsShown() -> Bool {
        startObserving()
        if asleep { return false }
        guard let app = NSApp as NSApplication? else { return true }
        let candidates = app.windows.filter { $0.canBecomeMain }
        guard let window = candidates.first(where: { String(describing: type(of: $0)).contains("Godot") }) ?? candidates.first
        else { return true }
        if window.isMiniaturized { return false }
        return window.occlusionState.contains(.visible)
    }
}
#endif
