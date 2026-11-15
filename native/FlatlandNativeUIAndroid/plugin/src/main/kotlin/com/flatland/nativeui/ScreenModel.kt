package com.flatland.nativeui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.runtime.mutableStateMapOf

/**
 * The screen being shown. Godot owns the real data; this holds a copy of the description and the values, sends every
 * edit back ([onChange]) and every tap ([onAction]), and accepts new descriptions and values from Godot ([update],
 * [apply]), which never send anything back. Compose observes it and redraws when it changes.
 *
 * @param schema the starting screen description.
 * @param values the starting values.
 */
class ScreenModel(schema: ScreenSchema, values: Map<String, Any>) {
    /**
     * The current screen description (pages and items).
     */
    var schema by mutableStateOf(schema)
        private set
    /**
     * The current value of every control, by key; Compose redraws what reads it.
     */
    val values: SnapshotStateMap<String, Any> = mutableStateMapOf<String, Any>().also { it.putAll(values) }

    /**
     * Called with the key and new value when the user edits a control; sent to Godot as `value_changed`.
     */
    var onChange: (String, Any) -> Unit = { _, _ -> }
    /**
     * Called with the id when the user taps an action or a row; sent to Godot as `action_triggered`.
     */
    var onAction: (String) -> Unit = {}
    /**
     * Called when the user taps Done (or goes back from the top); closes the sheet.
     */
    var onDone: () -> Unit = {}

    /**
     * The value for a key.
     *
     * @param key the control's key.
     * @return the value, or null if there is none.
     */
    fun value(key: String): Any? = values[key]

    /**
     * The user changed something: stores the value and reports it through [onChange]. Does nothing if it is
     * unchanged.
     *
     * @param key the control's key.
     * @param value the new value.
     */
    fun set(key: String, value: Any) {
        if (values[key] == value) return
        values[key] = value
        onChange(key, value)
    }

    /**
     * Godot changed one value: stores it without reporting anything back.
     *
     * @param key the control's key.
     * @param value the new value.
     */
    fun apply(key: String, value: Any) {
        values[key] = value
    }

    /**
     * Godot sent a new description and values. Navigation stays where it is.
     *
     * @param schema the new description.
     * @param values the new values.
     */
    fun update(schema: ScreenSchema, values: Map<String, Any>) {
        this.schema = schema
        this.values.clear()
        this.values.putAll(values)
    }
}
