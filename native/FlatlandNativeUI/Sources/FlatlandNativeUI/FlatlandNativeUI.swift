import SwiftGodotRuntime
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The class Godot sees. GDScript instantiates it by name (ClassDB.instantiate("FlatlandNativeUI")),
/// calls the @Callable methods, and connects to the signals to hear back:
///
///   showScreen(schemaJson, valuesJson)     open a native screen described by JSON (see Schema.swift)
///   updateScreen(schemaJson, valuesJson)   replace its content (data changed); navigation stays put
///   updateValue(key, valueJson)            one value changed on the Godot side
///   closeScreen()                          close it (for example before showing a Godot dialog)
///
///   value_changed(key, value_json)         the user edited a control
///   action_triggered(id)                   the user tapped a button or row
///   sheet_closed()                         the screen went away
///
/// The button bar (NativeToolbar.swift):
///   showToolbar(buttonsJson) / updateToolbar(buttonsJson) / hideToolbar()
///   toolbar_tapped(id)                     a button, or an entry of a button's menu, was tapped
///   toolbar_height_changed(pixels)         the bar's height (without the bottom safe area), in pixels
///
/// Power (see PowerManager in Godot):
///   powerState() -> String                 "normal", "low_power", "thermal" (hot) or "critical"
@Godot
final class FlatlandNativeUI: RefCounted, @unchecked Sendable {
    @Signal var valueChanged: SignalWithArguments<String, String>
    @Signal var actionTriggered: SignalWithArguments<String>
    @Signal var sheetClosed: SimpleSignal
    @Signal var toolbarTapped: SignalWithArguments<String>
    @Signal var toolbarHeightChanged: SignalWithArguments<Int>

    // Only touched on the main thread, where Godot runs and where UI must be built.
    nonisolated(unsafe) private var model: ScreenModel?
    nonisolated(unsafe) private var presenter: SheetPresenter?
    nonisolated(unsafe) private var toolbarModel: ToolbarModel?
    nonisolated(unsafe) private var toolbarPresenter: ToolbarPresenter?

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

    @Callable
    func updateScreen(schemaJson: String, valuesJson: String) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                model?.update(schema: ScreenSchema(json: schemaJson), values: ScreenSchema.values(json: valuesJson))
            }
        }
    }

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

    @Callable
    func closeScreen() {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { presenter?.dismiss(notify: true) }
        }
    }

    /// Low Power Mode and the device's heat level, so Godot can lower its frame rate.
    @Callable
    func powerState() -> String {
        let info = ProcessInfo.processInfo
        switch info.thermalState {
        case .critical: return "critical"
        case .serious: return "thermal"
        default: return info.isLowPowerModeEnabled ? "low_power" : "normal"
        }
    }

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

    @Callable
    func updateToolbar(buttonsJson: String) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { toolbarModel?.update(json: buttonsJson) }
        }
    }

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

    /// Development aid (macOS): save a picture of the button bar's window to `path`.
    @Callable
    func debugToolbarSnapshot(path: String) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { toolbarPresenter?.snapshot(to: path) }
        }
    }

    /// Development aid: make the same edit a tap in the screen would (goes through the model, so
    /// value_changed is emitted), to test the Swift -> Godot path without clicking.
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

    /// Development aid (macOS): save a picture of the screen's window to `path`, so it can be looked at
    /// without capturing the whole desktop.
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
