package com.flatland.nativeui

import org.json.JSONArray
import org.json.JSONObject

// What Godot sends: a screen described as JSON (title, pages, items) plus the current values. This file turns
// the JSON into plain Kotlin values; ScreenViews.kt draws them with Jetpack Compose. It reads the same JSON as
// the iOS version (Schema.swift), so one description from Godot serves both.

/**
 * Reads a value from a JSON object as it travels between Godot and the native screen.
 *
 * @receiver the JSON object.
 * @param name the field's name.
 * @return a String, a Boolean or a Double (all JSON numbers become Double), or null if the field is missing, null or
 *   another type.
 */
fun JSONObject.valueOrNull(name: String): Any? {
    if (!has(name) || isNull(name)) return null
    return when (val v = get(name)) {
        is Boolean, is String -> v
        is Number -> v.toDouble()
        else -> null
    }
}

/**
 * A value as text: a Double with no fraction is written without a decimal point.
 *
 * @param v a String, Double or Boolean (or null).
 * @return the text; "" for null.
 */
fun valueText(v: Any?): String = when (v) {
    is Double -> if (v == Math.rint(v)) v.toLong().toString() else v.toString()
    is Boolean -> v.toString()
    else -> v?.toString() ?: ""
}

/**
 * A value as a number: a String is parsed (0 if it is not a number) and a Boolean is 1 or 0.
 *
 * @param v a String, Double or Boolean (or null).
 * @return the number.
 */
fun valueDouble(v: Any?): Double = when (v) {
    is Double -> v
    is Boolean -> if (v) 1.0 else 0.0
    is String -> v.toDoubleOrNull() ?: 0.0
    else -> 0.0
}

/**
 * A value as a Boolean: a Boolean as itself, anything else true when it is not zero.
 *
 * @param v a String, Double or Boolean (or null).
 * @return the Boolean.
 */
fun valueBool(v: Any?): Boolean = if (v is Boolean) v else valueDouble(v) != 0.0

/**
 * The JSON text of a value, a bare scalar (what Godot's JSON parser expects).
 *
 * @param v a String, Double or Boolean (or null).
 * @return the JSON text; "null" for anything else.
 */
fun valueJson(v: Any?): String = when (v) {
    is String -> JSONObject.quote(v)
    is Double -> if (v == Math.rint(v) && Math.abs(v) < 1e15) v.toLong().toString() else v.toString()
    is Boolean -> v.toString()
    else -> "null"
}

/**
 * The kinds of item a screen can contain; the same as the JSON "type" field (see Schema.swift for the iOS version).
 * The iOS and macOS screens also support "image" and "link" items; the Android plug-in does not yet, so it ignores
 * them (see [parse]).
 */
enum class ItemKind { Section, Toggle, Choice, Number, Color, Text, Action, Info, Paragraph, Row;
    /**
     * Holds [parse].
     */
    companion object {
        /**
         * The kind for a JSON "type" name.
         *
         * @param name the "type" text ("section", "toggle", "choice", "number", "color", "text", "action", "info",
         *   "paragraph" or "row").
         * @return the kind, or null for a name the Android screen does not know (including the "image" and "link"
         *   kinds the iOS and macOS screens have).
         */
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

/**
 * One choice of a "choice" item.
 *
 * @property label the text shown.
 * @property value the value stored when it is chosen.
 * @property group the heading it is listed under in a long list ("" for none).
 */
data class ScreenOption(val label: String, val value: Any, val group: String)

/**
 * One item on a screen, described by the JSON Godot sent. Only the fields that apply to its [kind] are used.
 *
 * @property id stable across updates (position, kind, key and action id; for rows, the action id), so Compose keeps
 *   scroll position and focus when Godot sends fresh content.
 * @property kind what kind of item this is.
 * @property key the key of the value this item edits.
 * @property title the main text.
 * @property options the choices of a "choice" item.
 * @property minimum smallest value of a "number" item.
 * @property maximum largest value of a "number" item.
 * @property step step of a "number" item's buttons.
 * @property suffix text after a number, such as " s".
 * @property actionId the id sent to Godot when an action or row is tapped.
 * @property detail info: the value shown; row: the text on the right.
 * @property subtitle row: the second line.
 * @property accent row: "#rrggbb" for the leading text.
 * @property leading row: short text before the title (a magnitude, say).
 * @property badge row: short text shown in a small red capsule after the title (such as "NEW").
 * @property dot row: "#rrggbb" for a filled dot drawn before the leading text; the leading text is then drawn in the
 * normal text color instead of [accent].
 * @property checkKey row: the key of a Boolean shown as a check box.
 * @property style paragraph: "title", "headline", "caption" or "mono"; action: "destructive" or "prominent".
 * @property selected row: highlighted as the current choice.
 * @property dimmed row: drawn faded.
 * @property confirm action: if not empty, this question is asked before the id is sent.
 */
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
    val dot: String = "",
    val badge: String = "",
    val checkKey: String = "",
    val style: String = "",
    val selected: Boolean = false,
    val dimmed: Boolean = false,
    val confirm: String = "",
)

/**
 * One page of a screen.
 *
 * @property title the page's title (shown in the list of pages).
 * @property items its items, in order.
 */
data class ScreenPage(val title: String, val items: List<ScreenItem>)

/**
 * The description of a whole screen, turned from the JSON Godot sends into plain Kotlin values; ScreenViews.kt draws
 * it.
 *
 * @property title the screen's title.
 * @property pages the pages (one page is shown directly; several are listed).
 * @property doneTitle the title of the Done button.
 * @property rootItems items shown under the list of pages.
 */
data class ScreenSchema(
    val title: String = "",
    val pages: List<ScreenPage> = emptyList(),
    val doneTitle: String = "Done",
    val rootItems: List<ScreenItem> = emptyList(),
) {
    /**
     * Holds the JSON readers [parse], [items] and [values].
     */
    companion object {
        /**
         * Reads a screen description.
         *
         * @param json the JSON text from Godot ("title", "done_title", "pages", "root_items").
         * @return the schema; an empty one if the JSON cannot be read.
         */
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

        /**
         * Reads a list of item descriptions. Items with an unknown type are skipped; rows are identified by their
         * action id, everything else by position, kind, key and action id.
         *
         * @param list the JSON array, or null.
         * @return the items.
         */
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
                    subtitle = d.optString("subtitle"), accent = d.optString("accent"), leading = d.optString("leading"), dot = d.optString("dot"), badge = d.optString("badge"),
                    checkKey = d.optString("check_key"), style = d.optString("style"),
                    selected = d.optBoolean("selected"), dimmed = d.optBoolean("dimmed"), confirm = d.optString("confirm"),
                ))
            }
            return out
        }

        /**
         * Reads the current values of a screen.
         *
         * @param json a JSON object text mapping keys to values.
         * @return the values by key (those that are not text, number or Boolean are dropped); empty if the JSON
         *   cannot be read.
         */
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
