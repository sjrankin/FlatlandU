import SwiftGodotRuntime
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The class Godot sees. GDScript instantiates it by name (ClassDB.instantiate("FlatlandNativeUI")), calls the
/// @Callable methods and connects to the signals to hear back. It shows native screens (see Schema.swift for their
/// JSON), the button bar (NativeToolbar.swift) and reports the power state. All UI work happens on the main thread.
/// The GDScript side is NativeUI (scripts/core/native_ui.gd).
///
/// Godot to native: showScreen, updateScreen, updateValue, closeScreen, showToolbar, updateToolbar, hideToolbar,
/// powerState, windowIsShown.
/// Native to Godot (signals): value_changed, action_triggered, sheet_closed, toolbar_tapped, toolbar_height_changed.
@Godot
final class FlatlandNativeUI: RefCounted, @unchecked Sendable {
    /// Signal `value_changed(key, value_json)`: the user edited a control.
    @Signal var valueChanged: SignalWithArguments<String, String>
    /// Signal `action_triggered(id)`: the user tapped a button or row.
    @Signal var actionTriggered: SignalWithArguments<String>
    /// Signal `sheet_closed()`: the screen went away.
    @Signal var sheetClosed: SimpleSignal
    /// Signal `toolbar_tapped(id)`: a button, or an entry of a button's menu, was tapped.
    @Signal var toolbarTapped: SignalWithArguments<String>
    /// Signal `toolbar_height_changed(pixels)`: the bar's height, without the bottom safe area, in pixels.
    @Signal var toolbarHeightChanged: SignalWithArguments<Int>

    // Only touched on the main thread, where Godot runs and where UI must be built.
    /// The model of the screen being shown (nil when none). Only touched on the main thread, where Godot runs and
    /// where UI must be built.
    nonisolated(unsafe) private var model: ScreenModel?
    /// The object that shows the screen as a sheet (nil when none).
    nonisolated(unsafe) private var presenter: SheetPresenter?
    /// The model of the button bar (nil when it is not shown).
    nonisolated(unsafe) private var toolbarModel: ToolbarModel?
    /// The object that puts the bar on screen (nil when it is not shown).
    nonisolated(unsafe) private var toolbarPresenter: ToolbarPresenter?

    /// Opens a native screen described by JSON. If one is already open it is closed first without notifying Godot.
    /// Edits and taps come back through `valueChanged` and `actionTriggered`; closing through `sheetClosed`.
    ///
    /// - Parameter schemaJson: the screen description (see ScreenSchema).
    /// - Parameter valuesJson: the current values, a JSON object.
    @Callable
    func showScreen(schemaJson: String, valuesJson: String) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                presenter?.dismiss(notify: false)
                let model = ScreenModel(schema: ScreenSchema(json: schemaJson), values: ScreenSchema.values(json: valuesJson))
                model.onChange = { [weak self] key, value in self?.valueChanged.emit(key, value.jsonText) }
                model.onAction = { [weak self] id in self?.actionTriggered.emit(id) }
                let presenter = SheetPresenter(title: model.schema.title)
                presenter.onClosed = { [weak self] in
                    self?.presenter = nil
                    self?.model = nil
                    self?.sheetClosed.emit()
                }
                model.onDone = { [weak presenter] in presenter?.dismiss(notify: true) }
                self.model = model
                self.presenter = presenter
                presenter.present(ScreenRoot(model: model))
            }
        }
    }

    /// Replaces the content of the open screen (the data changed); navigation inside it stays where it is. Does
    /// nothing if no screen is open.
    ///
    /// - Parameter schemaJson: the new description.
    /// - Parameter valuesJson: the new values.
    @Callable
    func updateScreen(schemaJson: String, valuesJson: String) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                model?.update(schema: ScreenSchema(json: schemaJson), values: ScreenSchema.values(json: valuesJson))
            }
        }
    }

    /// One value changed on the Godot side (for example Reset All Settings): updates the control without sending
    /// anything back.
    ///
    /// - Parameter key: the value's key.
    /// - Parameter valueJson: the new value as JSON.
    @Callable
    func updateValue(key: String, valueJson: String) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                if let value = ScreenSchema.values(json: "{\"v\":\(valueJson)}")["v"] {
                    model?.apply(key, value)
                }
            }
        }
    }

    /// Closes the open screen (for example before showing a Godot dialog). `sheetClosed` is emitted.
    @Callable
    func closeScreen() {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { presenter?.dismiss(notify: true) }
        }
    }

    /// Low Power Mode and the device's heat level, so Godot's PowerManager can lower its frame rate.
    ///
    /// - Returns: "critical", "thermal" (hot), "low_power" or "normal".
    @Callable
    func powerState() -> String {
        let info = ProcessInfo.processInfo
        switch info.thermalState {
        case .critical: return "critical"
        case .serious: return "thermal"
        default: return info.isLowPowerModeEnabled ? "low_power" : "normal"
        }
    }

    /// Whether the app's window can be seen (macOS): false while the display sleeps, the screen is locked, or the
    /// window is minimized or fully covered. PowerManager stops drawing meanwhile; a Metal driver that keeps
    /// rendering to a display that is off eventually times out and crashes.
    ///
    /// - Returns: true if drawing is worthwhile; always true on iOS.
    @Callable
    func windowIsShown() -> Bool {
        #if os(macOS)
        return DisplayWatch.shared.windowIsShown()
        #else
        return true
        #endif
    }

    /// Shows the native button bar, or updates it if it is already shown.
    ///
    /// - Parameter buttonsJson: the buttons, a JSON array of {id, title, symbol, selected, menu} (see
    /// NativeToolbar.swift).
    @Callable
    func showToolbar(buttonsJson: String) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                if let toolbarModel {
                    toolbarModel.update(json: buttonsJson)
                    return
                }
                let model = ToolbarModel()
                model.onTap = { [weak self] id in self?.toolbarTapped.emit(id) }
                model.update(json: buttonsJson)
                let bar = ToolbarPresenter()
                bar.onHeight = { [weak self] pixels in self?.toolbarHeightChanged.emit(pixels) }
                toolbarModel = model
                toolbarPresenter = bar
                bar.show(model: model)
            }
        }
    }

    /// Sends a new button list to the bar (a toggle changed, for example).
    ///
    /// - Parameter buttonsJson: the buttons as JSON.
    @Callable
    func updateToolbar(buttonsJson: String) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { toolbarModel?.update(json: buttonsJson) }
        }
    }

    /// Takes the bar off the window (used if it did not come up, so Godot's own bar is used).
    @Callable
    func hideToolbar() {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                toolbarPresenter?.hide()
                toolbarPresenter = nil
                toolbarModel = nil
            }
        }
    }

    /// Development aid: makes the same edit a tap in the screen would (it goes through the model, so `valueChanged`
    /// is emitted), to test the Swift to Godot path without clicking.
    ///
    /// - Parameter key: the value's key.
    /// - Parameter valueJson: the new value as JSON.
    @Callable
    func debugEdit(key: String, valueJson: String) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                if let value = ScreenSchema.values(json: "{\"v\":\(valueJson)}")["v"] {
                    model?.set(key, value)
                }
            }
        }
    }

    /// Development aid (macOS): saves a picture of the screen's window, so it can be looked at without capturing the
    /// whole desktop.
    ///
    /// - Parameter path: where to save the PNG.
    @Callable
    func debugSnapshot(path: String) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { presenter?.snapshot(to: path) }
        }
    }
}

// The name below must match entry_symbol in the .gdextension file.
#initSwiftExtension(cdecl: "flatland_native_ui_entry", types: [
    FlatlandNativeUI.self,
])
