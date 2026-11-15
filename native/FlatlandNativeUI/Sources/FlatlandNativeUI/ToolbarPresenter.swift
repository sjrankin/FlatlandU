import SwiftUI

// Puts the SwiftUI button bar on screen.
//   iOS:   a view along the bottom edge of Godot's view, over it, reaching down behind the home indicator.
//   macOS: a view along the bottom edge of Godot's window, over it (the window has no bottom safe area).
// Both report the bar's height, in pixels and without the bottom safe area, through `onHeight`.

#if os(iOS)
import UIKit

/// Puts the SwiftUI button bar on screen. On iOS it is a view along the bottom edge of Godot's view, over it,
/// reaching down behind the home indicator. On macOS it is a view along the bottom edge of Godot's window, over it
/// (the window has no bottom safe area). Both report the bar's height, in pixels and without the bottom safe area,
/// through `onHeight`, so Godot can leave that much room.
@MainActor
final class ToolbarPresenter {
    /// Called with the bar's height in pixels when it changes (0 when the bar is hidden).
    var onHeight: (Int) -> Void = { _ in }
    /// iOS: the view controller hosting the bar.
    private var controller: ToolbarController?

    /// Shows the bar, if it is not already showing. Tries to attach to the window (for up to ten seconds if it does
    /// not exist yet).
    ///
    /// - Parameter model: the bar's model.
    func show(model: ToolbarModel) {
        guard controller == nil else { return }
        attach(model: model, triesLeft: 40)
    }

    /// Adds the bar to the window. Godot may call before its window is on screen, so if there is none it tries again
    /// every 250 ms until `triesLeft` runs out. On macOS the bar is pinned to the bottom of the content view and
    /// relaid out whenever the window is resized.
    ///
    /// - Parameter model: the bar's model (iOS only; on macOS it is the stored one).
    /// - Parameter triesLeft: how many more attempts are allowed.
    private func attach(model: ToolbarModel, triesLeft: Int) {
        guard controller == nil else { return }
        guard let root = Self.rootViewController() else {
            guard triesLeft > 0 else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.attach(model: model, triesLeft: triesLeft - 1)
            }
            return
        }
        let bar = ToolbarController(model: model)
        bar.onHeight = { [weak self] in self?.onHeight($0) }
        root.addChild(bar)
        bar.view.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(bar.view)
        let height = bar.view.heightAnchor.constraint(equalToConstant: 60)
        bar.heightConstraint = height
        NSLayoutConstraint.activate([
            bar.view.leadingAnchor.constraint(equalTo: root.view.leadingAnchor),
            bar.view.trailingAnchor.constraint(equalTo: root.view.trailingAnchor),
            bar.view.bottomAnchor.constraint(equalTo: root.view.bottomAnchor),
            height,
        ])
        bar.didMove(toParent: root)
        controller = bar
    }

    /// Takes the bar off the window and reports a height of 0.
    func hide() {
        guard let bar = controller else { return }
        controller = nil
        bar.willMove(toParent: nil)
        bar.view.removeFromSuperview()
        bar.removeFromParent()
        onHeight(0)
    }

    /// iOS: the root view controller of the key window (or the first window).
    ///
    /// - Returns: the controller, or nil if there is no window yet.
    private static func rootViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    }
}

/// iOS: hosts the SwiftUI bar in a view controller, sizes itself to the rows it needs and reports the height.
@MainActor
final class ToolbarController: UIViewController {
    /// The bar's model.
    let model: ToolbarModel
    /// Called with the height in pixels when it changes.
    var onHeight: (Int) -> Void = { _ in }
    /// The constraint on the bar's height (the bar plus the bottom safe area).
    var heightConstraint: NSLayoutConstraint?
    /// The last height reported.
    private var lastPixels = -1

    /// Creates the controller.
    ///
    /// - Parameter model: the bar's model.
    init(model: ToolbarModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    /// Creates the controller.
    ///
    /// - Parameter model: the bar's model.
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Puts the SwiftUI bar view inside this controller's view and arranges a layout whenever the buttons change.
    override func viewDidLoad() {
        super.viewDidLoad()
        let hosting = UIHostingController(rootView: ToolbarView(model: model))
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
        model.onButtonsChanged = { [weak self] in self?.view.setNeedsLayout() }
    }

    /// Works out the columns and rows for the width (leaving the side safe areas), sizes the bar to them plus the
    /// bottom safe area, and reports the height in pixels when it changes.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let usable = view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right
        let layout = ToolbarModel.layout(width: usable, count: model.buttons.count)
        if model.columns != layout.columns { model.columns = layout.columns }
        let bar = ToolbarModel.height(rows: layout.rows)
        let total = bar + (parent?.view.safeAreaInsets.bottom ?? 0)
        if let heightConstraint, abs(heightConstraint.constant - total) > 0.5 {
            heightConstraint.constant = total
        }
        let pixels = Int((bar * traitCollection.displayScale).rounded())
        if pixels != lastPixels {
            lastPixels = pixels
            onHeight(pixels)
        }
    }
}

#elseif os(macOS)
import AppKit

/// Puts the SwiftUI button bar on screen. On iOS it is a view along the bottom edge of Godot's view, over it,
/// reaching down behind the home indicator. On macOS it is a view along the bottom edge of Godot's window, over it
/// (the window has no bottom safe area). Both report the bar's height, in pixels and without the bottom safe area,
/// through `onHeight`, so Godot can leave that much room.
@MainActor
final class ToolbarPresenter {
    /// Called with the bar's height in pixels when it changes (0 when the bar is hidden).
    var onHeight: (Int) -> Void = { _ in }
    /// macOS: the bar's model (nil after `hide`, which also stops a pending `attach` retry).
    private var model: ToolbarModel?
    /// macOS: Godot's window the bar sits in.
    private var window: NSWindow?
    /// macOS: the hosting view of the bar.
    private var bar: NSHostingView<ToolbarView>?
    /// macOS: the bar's height constraint, changed as the number of rows changes.
    private var heightConstraint: NSLayoutConstraint?
    /// macOS: the window-resize observer that triggers `relayout` (the number of rows depends on the width).
    private var observer: NSObjectProtocol?
    /// The last height reported, so `onHeight` is called only when it changes.
    private var lastPixels = -1

    /// Shows the bar, if it is not already showing. Tries to attach to the window (for up to ten seconds if it does
    /// not exist yet).
    ///
    /// - Parameter model: the bar's model.
    func show(model: ToolbarModel) {
        guard bar == nil else { return }
        self.model = model
        attach(triesLeft: 40)
    }

    /// Adds the bar to the window. Godot may call before its window is on screen, so if there is none it tries again
    /// every 250 ms until `triesLeft` runs out. On macOS the bar is pinned to the bottom of the content view and
    /// relaid out whenever the window is resized.
    ///
    /// - Parameter model: the bar's model (iOS only; on macOS it is the stored one).
    /// - Parameter triesLeft: how many more attempts are allowed.
    private func attach(triesLeft: Int) {
        guard bar == nil, let model else { return }
        guard let window = Self.godotWindow(), let content = window.contentView else {
            guard triesLeft > 0 else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.attach(triesLeft: triesLeft - 1)
            }
            return
        }
        let hosting = NSHostingView(rootView: ToolbarView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hosting)
        let height = hosting.heightAnchor.constraint(equalToConstant: ToolbarModel.height(rows: 1))
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            height,
        ])
        self.window = window
        bar = hosting
        heightConstraint = height
        // The number of rows depends on the window's width, so lay out again whenever it changes.
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }
        model.onButtonsChanged = { [weak self] in self?.relayout() }
        relayout()
    }

    /// macOS: chooses the number of rows for the window's width, sizes the bar to them and reports the height in
    /// pixels.
    private func relayout() {
        guard let model, let window, let content = window.contentView, let heightConstraint else { return }
        let layout = ToolbarModel.layout(width: content.bounds.width, count: model.buttons.count)
        if model.columns != layout.columns { model.columns = layout.columns }
        let height = ToolbarModel.height(rows: layout.rows)
        if abs(heightConstraint.constant - height) > 0.5 { heightConstraint.constant = height }
        let pixels = Int((height * window.backingScaleFactor).rounded())
        if pixels != lastPixels {
            lastPixels = pixels
            onHeight(pixels)
        }
    }

    /// Takes the bar off the window and reports a height of 0.
    func hide() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        bar?.removeFromSuperview()
        bar = nil
        model = nil          // a pending attach() retry then does nothing
        window = nil
        lastPixels = -1
        onHeight(0)
    }

    /// macOS: finds Godot's own window, not one of the windows this extension opens for its screens. NSApp is still
    /// nil if Godot has not created the application object yet.
    ///
    /// - Returns: the window, or nil.
    private static func godotWindow() -> NSWindow? {
        // NSApp is still nil if Godot has not created the application object yet.
        guard let app = NSApp as NSApplication? else { return nil }
        let candidates = app.windows.filter { $0.isVisible && $0.canBecomeMain }
        return candidates.first { String(describing: type(of: $0)).contains("Godot") } ?? candidates.first
    }
}
#endif
