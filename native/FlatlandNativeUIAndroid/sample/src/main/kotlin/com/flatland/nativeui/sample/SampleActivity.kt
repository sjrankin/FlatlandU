package com.flatland.nativeui.sample

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.flatland.nativeui.NativeTheme
import com.flatland.nativeui.ScreenModel
import com.flatland.nativeui.ScreenRoot
import com.flatland.nativeui.ScreenSchema
import com.flatland.nativeui.valueText

/**
 * Shows a hard-coded screen (one of every kind of item) and logs what the user does, with the log tag
 * "NativeUISample". It is for trying the Android native screens without Godot.
 */
class SampleActivity : ComponentActivity() {
    /**
     * Builds the sample screen's JSON (a switch, two choices, a number, a color, a text field, buttons, info and list
     * rows, a monospaced paragraph), makes a [ScreenModel] that logs each edit and action, and shows it with
     * [ScreenRoot]. Done closes the activity.
     *
     * @param savedInstanceState the saved state (unused).
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val options = (1..20).joinToString(",") { """{"label":"Option $it","value":"o$it","group":"${if (it <= 10) "First" else "Second"}"}""" }
        val schema = """{"title":"Sample","pages":[
          {"title":"General","items":[
            {"type":"paragraph","title":"Every kind of item.","style":"caption"},
            {"type":"section","title":"Controls"},
            {"type":"toggle","key":"t","title":"A switch"},
            {"type":"choice","key":"c","title":"Few options","options":[{"label":"Alpha","value":"a"},{"label":"Beta","value":"b"}]},
            {"type":"choice","key":"m","title":"Many options","options":[$options]},
            {"type":"number","key":"n","title":"Opacity","min":0,"max":1,"step":0.1,"suffix":"x"},
            {"type":"color","key":"k","title":"Color"},
            {"type":"text","key":"s","title":"Name"},
            {"type":"action","id":"go","title":"Prominent","style":"prominent"},
            {"type":"action","id":"del","title":"Reset all","style":"destructive","confirm":"Reset everything?"}]},
          {"title":"Data","items":[
            {"type":"info","title":"Version","detail":"1.0"},
            {"type":"info","title":"URL","detail":"https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_hour.geojson"},
            {"type":"row","id":"r1","leading":"6.1","accent":"#ff4040","title":"Offshore Chile","subtitle":"10 km deep","detail":"2 h ago"},
            {"type":"row","id":"r2","title":"Checked row","check_key":"chk"},
            {"type":"paragraph","title":"Mono text\nline two","style":"mono"}]}
        ],"root_items":[{"type":"action","id":"reset","title":"Reset All Settings","style":"destructive"}]}"""
        val values = """{"t":true,"c":"b","m":"o12","n":0.7,"k":"#3366cc","s":"Stuart","chk":true}"""
        val model = ScreenModel(ScreenSchema.parse(schema), ScreenSchema.values(values))
        model.onChange = { key, value -> Log.i("NativeUISample", "value $key = ${valueText(value)}") }
        model.onAction = { Log.i("NativeUISample", "action $it") }
        model.onDone = { finish() }
        setContent { NativeTheme { ScreenRoot(model) } }
    }
}
