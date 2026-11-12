package com.flatland.nativeui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.runtime.mutableStateMapOf

/**
 * The screen being shown. Godot owns the real data; this holds a copy of the description and the values,
 * sends every edit back (onChange) and every tap (onAction), and accepts new descriptions and values from
 * Godot (update, apply), which never send anything back.
 */
class ScreenModel(schema: ScreenSchema, values: Map<String, Any>) {
    var schema by mutableStateOf(schema)
        private set
    val values: SnapshotStateMap<String, Any> = mutableStateMapOf<String, Any>().also { it.putAll(values) }

    var onChange: (String, Any) -> Unit = { _, _ -> }
    var onAction: (String) -> Unit = {}
    var onDone: () -> Unit = {}

    fun value(key: String): Any? = values[key]

    /** The user changed something. */
    fun set(key: String, value: Any) {
        if (values[key] == value) return
        values[key] = value
        onChange(key, value)
    }

    /** Godot changed one value. */
    fun apply(key: String, value: Any) {
        values[key] = value
    }

    /** Godot sent a new description and values. Navigation stays where it is. */
    fun update(schema: ScreenSchema, values: Map<String, Any>) {
        this.schema = schema
        this.values.clear()
        this.values.putAll(values)
    }
}
