import SwiftUI

// Puts the SwiftUI button bar on screen.
//   iOS:   a view along the bottom edge of Godot's view, over it, reaching down behind the home indicator.
//   macOS: a small window of its own (a development aid; the Mac app keeps its Godot toolbar at the top).
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

    func snapshot(to path: String) {}

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
    private var window: NSWindow?

    func show(model: ToolbarModel) {
        guard window == nil else { return }
        let width: CGFloat = 800
        let layout = ToolbarModel.layout(width: width, count: model.buttons.count)
        model.columns = layout.columns
        let height = ToolbarModel.height(rows: layout.rows)
        let window = NSWindow(contentViewController: NSHostingController(rootView: ToolbarView(model: model)))
        window.title = "Flatland Toolbar"
        window.styleMask = [.titled]
        window.setContentSize(NSSize(width: width, height: height))
        window.setFrameOrigin(NSPoint(x: 40, y: 80))
        window.orderFront(nil)
        self.window = window
        onHeight(Int(height))
    }

    func hide() {
        window?.close()
        window = nil
        onHeight(0)
    }

    /// Development aid: a picture of just the toolbar window.
    func snapshot(to path: String) {
        guard let window else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
        try? task.run()
        task.waitUntilExit()
    }
}
#endif
