import SwiftUI

// Puts the SwiftUI button bar on screen.
//   iOS:   a view along the bottom edge of Godot's view, over it, reaching down behind the home indicator.
//   macOS: a view along the bottom edge of Godot's window, over it (the window has no bottom safe area).
// Both report the bar's height, in pixels and without the bottom safe area, through `onHeight`.

#if os(iOS)
import UIKit

@MainActor
final class ToolbarPresenter {
    var onHeight: (Int) -> Void = { _ in }
    private var controller: ToolbarController?

    func show(model: ToolbarModel) {
        guard controller == nil else { return }
        attach(model: model, triesLeft: 40)
    }

    /// Godot may call before the app's window exists; try again for a few seconds.
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

    func hide() {
        guard let bar = controller else { return }
        controller = nil
        bar.willMove(toParent: nil)
        bar.view.removeFromSuperview()
        bar.removeFromParent()
        onHeight(0)
    }

    private static func rootViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    }
}

/// Hosts the SwiftUI bar, sizes itself to the rows it needs, and reports the height.
@MainActor
final class ToolbarController: UIViewController {
    let model: ToolbarModel
    var onHeight: (Int) -> Void = { _ in }
    var heightConstraint: NSLayoutConstraint?
    private var lastPixels = -1

    init(model: ToolbarModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

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

@MainActor
final class ToolbarPresenter {
    var onHeight: (Int) -> Void = { _ in }
    private var model: ToolbarModel?
    private var window: NSWindow?
    private var bar: NSHostingView<ToolbarView>?
    private var heightConstraint: NSLayoutConstraint?
    private var observer: NSObjectProtocol?
    private var lastPixels = -1

    func show(model: ToolbarModel) {
        guard bar == nil else { return }
        self.model = model
        attach(triesLeft: 40)
    }

    /// Godot may call before its window is on screen; try again for a few seconds.
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

    /// Chooses the number of rows for the window's width, sizes the bar to them and reports the height in pixels.
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

    /// Godot's own window: not one of the windows this extension opens for its screens.
    private static func godotWindow() -> NSWindow? {
        // NSApp is still nil if Godot has not created the application object yet.
        guard let app = NSApp as NSApplication? else { return nil }
        let candidates = app.windows.filter { $0.isVisible && $0.canBecomeMain }
        return candidates.first { String(describing: type(of: $0)).contains("Godot") } ?? candidates.first
    }
}
#endif
