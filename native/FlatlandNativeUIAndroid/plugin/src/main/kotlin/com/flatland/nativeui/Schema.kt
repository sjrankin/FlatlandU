package com.flatland.nativeui

import org.json.JSONArray
import org.json.JSONObject

// What Godot sends: a screen described as JSON (title, pages, items) plus the current values. This file turns
// the JSON into plain Kotlin values; ScreenViews.kt draws them with Jetpack Compose. It reads the same JSON as
// the iOS version (Schema.swift), so one description from Godot serves both.

/** A setting's value as it travels over JSON: a String, a Double or a Boolean. */
fun JSONObject.valueOrNull(name: String): Any? {
    if (!has(name) || isNull(name)) return null
    return when (val v = get(name)) {
        is Boolean, is String -> v
        is Number -> v.toDouble()
        else -> null
    }
}

fun valueText(v: Any?): String = when (v) {
    is Double -> if (v == Math.rint(v)) v.toLong().toString() else v.toString()
    is Boolean -> v.toString()
    else -> v?.toString() ?: ""
}

fun valueDouble(v: Any?): Double = when (v) {
    is Double -> v
    is Boolean -> if (v) 1.0 else 0.0
    is String -> v.toDoubleOrNull() ?: 0.0
    else -> 0.0
}

fun valueBool(v: Any?): Boolean = if (v is Boolean) v else valueDouble(v) != 0.0

/** The JSON text of a value, a bare scalar (what Godot's JSON parser expects). */
fun valueJson(v: Any?): String = when (v) {
    is String -> JSONObject.quote(v)
    is Double -> if (v == Math.rint(v) && Math.abs(v) < 1e15) v.toLong().toString() else v.toString()
    is Boolean -> v.toString()
    else -> "null"
}

enum class ItemKind { Section, Toggle, Choice, Number, Color, Text, Action, Info, Paragraph, Row;
    companion object {
        fun parse(name: String): ItemKind? = when (name) {
            "section" -> Section
            "toggle" -> Toggle
            "choice" -> Choice
            "number" -> Number
            "color" -> Color
            "text" -> Text
            "action" -> Action
            "info" -> Info
            "paragraph" -> Paragraph
            "row" -> Row
            else -> null
        }
    }
}

data class ScreenOption(val label: String, val value: Any, val group: String)

data class ScreenItem(
    /** Stable across updates, so Compose keeps scroll position and focus when Godot sends fresh content. */
    val id: String,
    val kind: ItemKind,
    val key: String = "",
    val title: String = "",
    val options: List<ScreenOption> = emptyList(),
    val minimum: Double = 0.0,
    val maximum: Double = 1.0,
    val step: Double = 1.0,
    val suffix: String = "",
    val actionId: String = "",
    val detail: String = "",
    val subtitle: String = "",
    val accent: String = "",
    val leading: String = "",
    val checkKey: String = "",
    val style: String = "",
    val selected: Boolean = false,
    val dimmed: Boolean = false,
    val confirm: String = "",
)

data class ScreenPage(val title: String, val items: List<ScreenItem>)

data class ScreenSchema(
    val title: String = "",
    val pages: List<ScreenPage> = emptyList(),
    val doneTitle: String = "Done",
    val rootItems: List<ScreenItem> = emptyList(),
) {
    companion object {
        fun parse(json: String): ScreenSchema = try {
            val root = JSONObject(json)
            val pages = root.optJSONArray("pages") ?: JSONArray()
            ScreenSchema(
                title = root.optString("title"),
                doneTitle = root.optString("done_title", "Done"),
                pages = (0 until pages.length()).map { i ->
                    val p = pages.getJSONObject(i)
                    ScreenPage(p.optString("title"), items(p.optJSONArray("items")))
                },
                rootItems = items(root.optJSONArray("root_items")),
            )
        } catch (e: Exception) {
            ScreenSchema()
        }

        private fun items(list: JSONArray?): List<ScreenItem> {
            val out = ArrayList<ScreenItem>()
            if (list == null) return out
            for (index in 0 until list.length()) {
                val d = list.getJSONObject(index)
                val kind = ItemKind.parse(d.optString("type")) ?: continue
                val key = d.optString("key")
                val actionId = d.optString("id")
                val stable = if (kind == ItemKind.Row && actionId.isNotEmpty()) "row-$actionId"
                else "$index-${kind.name}-$key-$actionId"
                val options = ArrayList<ScreenOption>()
                val raw = d.optJSONArray("options")
                if (raw != null) for (n in 0 until raw.length()) {
                    val o = raw.getJSONObject(n)
                    val v = o.valueOrNull("value") ?: continue
                    options.add(ScreenOption(o.optString("label", valueText(v)), v, o.optString("group")))
                }
                out.add(ScreenItem(
                    id = stable, kind = kind, key = key, title = d.optString("title"), options = options,
                    minimum = d.optDouble("min", 0.0), maximum = d.optDouble("max", 1.0), step = d.optDouble("step", 1.0),
                    suffix = d.optString("suffix"), actionId = actionId, detail = d.optString("detail"),
                    subtitle = d.optString("subtitle"), accent = d.optString("accent"), leading = d.optString("leading"),
                    checkKey = d.optString("check_key"), style = d.optString("style"),
                    selected = d.optBoolean("selected"), dimmed = d.optBoolean("dimmed"), confirm = d.optString("confirm"),
                ))
            }
            return out
        }

        fun values(json: String): Map<String, Any> = try {
            val root = JSONObject(json)
            val out = HashMap<String, Any>()
            for (k in root.keys()) root.valueOrNull(k)?.let { out[k] = it }
            out
        } catch (e: Exception) {
            emptyMap()
        }
    }
}
