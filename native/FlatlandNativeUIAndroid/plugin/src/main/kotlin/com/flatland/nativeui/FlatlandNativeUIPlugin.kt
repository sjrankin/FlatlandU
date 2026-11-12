package com.flatland.nativeui

import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * The Android counterpart of the Swift FlatlandNativeUI class. GDScript gets it as the engine singleton
 * "FlatlandNativeUI", calls the methods below, and connects to the signals to hear back. The calls and
 * signals are the same as on iOS (see FlatlandNativeUI.swift):
 *
 *   showScreen(schemaJson, valuesJson)    open a native screen described by JSON
 *   updateScreen(schemaJson, valuesJson)  replace its content (data changed); navigation stays put
 *   updateValue(key, valueJson)           one value changed on the Godot side
 *   closeScreen()                         close it
 *   showToolbar / updateToolbar(buttonsJson), hideToolbar()   the button bar
 *
 *   value_changed(key, value_json), action_triggered(id), sheet_closed(),
 *   toolbar_tapped(id), toolbar_height_changed(pixels)
 */
class FlatlandNativeUIPlugin(private val host: Godot) : GodotPlugin(host) {
    private val valueChanged = SignalInfo("value_changed", String::class.java, String::class.java)
    private val actionTriggered = SignalInfo("action_triggered", String::class.java)
    private val sheetClosed = SignalInfo("sheet_closed")
    private val toolbarTapped = SignalInfo("toolbar_tapped", String::class.java)
    private val toolbarHeightChanged = SignalInfo("toolbar_height_changed", Integer::class.java)

    // Only touched on the UI thread.
    private var model: ScreenModel? = null
    private var sheet: SheetPresenter? = null
    private var toolbarModel: ToolbarModel? = null
    private var toolbar: ToolbarPresenter? = null

    override fun getPluginName() = "FlatlandNativeUI"

    override fun getPluginSignals() = setOf(valueChanged, actionTriggered, sheetClosed, toolbarTapped, toolbarHeightChanged)

    private fun emit(signal: SignalInfo, vararg args: Any) = emitSignal(host, pluginName, signal, *args)

    private fun ui(block: () -> Unit) {
        activity?.runOnUiThread(block)
    }

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

    @UsedByGodot
    fun updateScreen(schemaJson: String, valuesJson: String) = ui {
        model?.update(ScreenSchema.parse(schemaJson), ScreenSchema.values(valuesJson))
    }

    @UsedByGodot
    fun updateValue(key: String, valueJson: String) = ui {
        ScreenSchema.values("{\"v\":$valueJson}")["v"]?.let { model?.apply(key, it) }
    }

    @UsedByGodot
    fun closeScreen() = ui { sheet?.dismiss(notify = true) }

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

    @UsedByGodot
    fun updateToolbar(buttonsJson: String) = ui { toolbarModel?.update(buttonsJson) }

    @UsedByGodot
    fun hideToolbar() = ui {
        toolbar?.hide()
        toolbar = null
        toolbarModel = null
    }
}
