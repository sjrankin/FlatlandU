package com.flatland.nativeui

import android.content.Context
import android.os.Build
import android.os.PowerManager
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * The Android counterpart of the Swift FlatlandNativeUI class. GDScript gets it as the engine singleton
 * "FlatlandNativeUI", calls the methods below and connects to the signals to hear back. The calls and signals are the
 * same as on iOS (see FlatlandNativeUI.swift): showScreen, updateScreen, updateValue, closeScreen, showToolbar,
 * updateToolbar, hideToolbar and powerState; the signals value_changed, action_triggered, sheet_closed,
 * toolbar_tapped and toolbar_height_changed. The GDScript side is NativeUI (scripts/core/native_ui.gd). All UI work
 * runs on the UI thread.
 *
 * @param host the Godot engine instance.
 */
class FlatlandNativeUIPlugin(private val host: Godot) : GodotPlugin(host) {
    /**
     * Signal `value_changed(key, value_json)`: the user edited a control.
     */
    private val valueChanged = SignalInfo("value_changed", String::class.java, String::class.java)
    /**
     * Signal `action_triggered(id)`: the user tapped a button or row.
     */
    private val actionTriggered = SignalInfo("action_triggered", String::class.java)
    /**
     * Signal `sheet_closed()`: the screen went away.
     */
    private val sheetClosed = SignalInfo("sheet_closed")
    /**
     * Signal `toolbar_tapped(id)`: a button, or an entry of a button's menu, was tapped.
     */
    private val toolbarTapped = SignalInfo("toolbar_tapped", String::class.java)
    /**
     * Signal `toolbar_height_changed(pixels)`: the bar's height in pixels (without the navigation bar).
     */
    private val toolbarHeightChanged = SignalInfo("toolbar_height_changed", Integer::class.java)

    // Only touched on the UI thread.
    /**
     * The model of the screen being shown (null when none). Only touched on the UI thread.
     */
    private var model: ScreenModel? = null
    /**
     * The presenter of the screen (null when none).
     */
    private var sheet: SheetPresenter? = null
    /**
     * The model of the button bar (null when not shown).
     */
    private var toolbarModel: ToolbarModel? = null
    /**
     * The presenter of the button bar (null when not shown).
     */
    private var toolbar: ToolbarPresenter? = null

    /**
     * The name Godot registers the singleton under.
     *
     * @return "FlatlandNativeUI".
     */
    override fun getPluginName() = "FlatlandNativeUI"

    /**
     * The signals Godot may connect to.
     *
     * @return the five signals.
     */
    override fun getPluginSignals() = setOf(valueChanged, actionTriggered, sheetClosed, toolbarTapped, toolbarHeightChanged)

    /**
     * Sends a signal to Godot.
     *
     * @param signal which signal.
     * @param args its arguments.
     */
    private fun emit(signal: SignalInfo, vararg args: Any) = emitSignal(host, pluginName, signal, *args)

    /**
     * Runs a block on the UI thread (all Compose and view work must happen there).
     *
     * @param block the work to do.
     */
    private fun ui(block: () -> Unit) {
        activity?.runOnUiThread(block)
    }

    /**
     * Opens a native screen described by JSON, replacing one that is already open without notifying Godot. Edits,
     * taps and closing come back through the signals.
     *
     * @param schemaJson the screen description (see [ScreenSchema]).
     * @param valuesJson the current values, a JSON object.
     */
    @UsedByGodot
    fun showScreen(schemaJson: String, valuesJson: String) = ui {
        val activity = activity ?: return@ui
        sheet?.dismiss(notify = false, animated = false)
        val m = ScreenModel(ScreenSchema.parse(schemaJson), ScreenSchema.values(valuesJson))
        m.onChange = { key, value -> emit(valueChanged, key, valueJson(value)) }
        m.onAction = { id -> emit(actionTriggered, id) }
        val s = SheetPresenter()
        s.onClosed = {
            sheet = null
            model = null
            emit(sheetClosed)
        }
        m.onDone = { s.dismiss(notify = true) }
        model = m
        sheet = s
        s.present(activity, m)
    }

    /**
     * Replaces the content of the open screen (the data changed); navigation stays put. Does nothing if none is open.
     *
     * @param schemaJson the new description.
     * @param valuesJson the new values.
     */
    @UsedByGodot
    fun updateScreen(schemaJson: String, valuesJson: String) = ui {
        model?.update(ScreenSchema.parse(schemaJson), ScreenSchema.values(valuesJson))
    }

    /**
     * One value changed on the Godot side: updates the control without sending anything back.
     *
     * @param key the value's key.
     * @param valueJson the new value as JSON.
     */
    @UsedByGodot
    fun updateValue(key: String, valueJson: String) = ui {
        ScreenSchema.values("{\"v\":$valueJson}")["v"]?.let { model?.apply(key, it) }
    }

    /**
     * Closes the open screen. `sheet_closed` is emitted.
     */
    @UsedByGodot
    fun closeScreen() = ui { sheet?.dismiss(notify = true) }

    /**
     * Battery Saver and the device's heat level, so Godot's PowerManager can lower its frame rate.
     *
     * @return "critical", "thermal" (hot), "low_power" (Battery Saver) or "normal".
     */
    @UsedByGodot
    fun powerState(): String {
        val power = activity?.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return "normal"
        if (Build.VERSION.SDK_INT >= 29) {
            when {
                power.currentThermalStatus >= PowerManager.THERMAL_STATUS_CRITICAL -> return "critical"
                power.currentThermalStatus >= PowerManager.THERMAL_STATUS_SEVERE -> return "thermal"
            }
        }
        return if (power.isPowerSaveMode) "low_power" else "normal"
    }

    /**
     * Shows the native button bar, or updates it if it is already shown.
     *
     * @param buttonsJson the buttons, a JSON array of {id, title, symbol, selected, menu}.
     */
    @UsedByGodot
    fun showToolbar(buttonsJson: String) = ui {
        val existing = toolbarModel
        if (existing != null) {
            existing.update(buttonsJson)
            return@ui
        }
        val activity = activity ?: return@ui
        val m = ToolbarModel()
        m.onTap = { id -> emit(toolbarTapped, id) }
        m.update(buttonsJson)
        val bar = ToolbarPresenter()
        bar.onHeight = { pixels -> emit(toolbarHeightChanged, pixels) }
        toolbarModel = m
        toolbar = bar
        bar.show(activity, m)
    }

    /**
     * Sends a new button list to the bar.
     *
     * @param buttonsJson the buttons as JSON.
     */
    @UsedByGodot
    fun updateToolbar(buttonsJson: String) = ui { toolbarModel?.update(buttonsJson) }

    /**
     * Takes the bar off the screen (Godot's own bar is then used).
     */
    @UsedByGodot
    fun hideToolbar() = ui {
        toolbar?.hide()
        toolbar = null
        toolbarModel = null
    }
}
