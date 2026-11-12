package com.flatland.nativeui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp

// Pick-lists, numbers and colours. Colours travel as "#rrggbb" text, the form Godot's Settings keeps.


fun parseHex(hex: String): Color {
    val s = hex.trim().removePrefix("#")
    val v = s.toLongOrNull(16) ?: 0L
    return Color(((v shr 16) and 0xFF).toInt(), ((v shr 8) and 0xFF).toInt(), (v and 0xFF).toInt())
}

fun hexOf(r: Float, g: Float, b: Float): String =
    "#%02x%02x%02x".format((r * 255).toInt().coerceIn(0, 255), (g * 255).toInt().coerceIn(0, 255), (b * 255).toInt().coerceIn(0, 255))

/** A choice: a pop-up menu for a few options, a separate list (with group headings) for many. */
@Composable
fun ChoiceRow(model: ScreenModel, item: ScreenItem, navigate: (Route) -> Unit) {
    val current = model.value(item.key)
    val label = item.options.firstOrNull { it.value == current }?.label ?: valueText(current)
    if (item.options.size > 12) {
        ListItem(
            headlineContent = { Text(item.title) },
            trailingContent = { Text(label, color = MaterialTheme.colorScheme.primary) },
            colors = clearColors(),
            modifier = Modifier.clickableRow { navigate(Route.Choice(item.key)) },
        )
        return
    }
    var open by remember { mutableStateOf(false) }
    Box {
        ListItem(
            headlineContent = { Text(item.title) },
            trailingContent = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(label, color = MaterialTheme.colorScheme.primary)
                    Icon(Icons.Filled.ArrowDropDown, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                }
            },
            colors = clearColors(),
            modifier = Modifier.clickableRow { open = true },
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for (option in item.options) {
                DropdownMenuItem(
                    text = { Text(option.label) },
                    trailingIcon = { if (option.value == current) Icon(Icons.Filled.Check, contentDescription = null) },
                    onClick = { model.set(item.key, option.value); open = false },
                )
            }
        }
    }
}

@Composable
fun ChoiceList(model: ScreenModel, item: ScreenItem) {
    val current = model.value(item.key)
    LazyColumn {
        var lastGroup: String? = null
        for ((index, option) in item.options.withIndex()) {
            val header = if (option.group != lastGroup && option.group.isNotEmpty()) option.group else null
            lastGroup = option.group
            if (header != null) item(key = "group-$index") {
                Text(header, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(start = 16.dp, top = 20.dp, bottom = 4.dp))
            }
            item(key = "option-$index") {
                ListItem(
                    headlineContent = { Text(option.label) },
                    trailingContent = { if (option.value == current) Icon(Icons.Filled.Check, contentDescription = "Selected", tint = MaterialTheme.colorScheme.primary) },
                    colors = clearColors(),
                    modifier = Modifier.clickableRow { model.set(item.key, option.value) },
                )
            }
        }
    }
}

private fun formatNumber(v: Double): String = valueText(Math.round(v * 10000) / 10000.0)

/** A number: type it in, or use the - and + buttons. */
@Composable
fun NumberRow(model: ScreenModel, item: ScreenItem) {
    val current = valueDouble(model.value(item.key))
    var text by remember(item.key) { mutableStateOf(formatNumber(current)) }
    // Godot changed the value (a preset, say): show it, unless the field already says the same number.
    LaunchedEffect(current) { if (text.toDoubleOrNull() != current) text = formatNumber(current) }
    val step = { delta: Double ->
        val next = (Math.round((current + delta) * 10000) / 10000.0).coerceIn(item.minimum, item.maximum)
        model.set(item.key, next)
        text = formatNumber(next)
    }
    ListItem(
        headlineContent = { Text(item.title) },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { step(-item.step) }) { Icon(Icons.Filled.Remove, contentDescription = "Decrease") }
                OutlinedTextField(
                    value = text,
                    onValueChange = { entered ->
                        text = entered
                        entered.toDoubleOrNull()?.let { model.set(item.key, it.coerceIn(item.minimum, item.maximum)) }
                    },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    suffix = if (item.suffix.isEmpty()) null else { { Text(item.suffix) } },
                    modifier = Modifier.width(112.dp),
                )
                IconButton(onClick = { step(item.step) }) { Icon(Icons.Filled.Add, contentDescription = "Increase") }
            }
        },
        colors = clearColors(),
    )
}

/** A colour: a swatch that opens a dialog with a hex field and red, green and blue sliders. */
@Composable
fun ColorRow(model: ScreenModel, item: ScreenItem) {
    val hex = valueText(model.value(item.key)).ifEmpty { "#000000" }
    var editing by remember { mutableStateOf(false) }
    ListItem(
        headlineContent = { Text(item.title) },
        trailingContent = {
            Surface(
                shape = RoundedCornerShape(8.dp), color = parseHex(hex), modifier = Modifier.size(36.dp),
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
            ) {}
        },
        colors = clearColors(),
        modifier = Modifier.clickableRow { editing = true },
    )
    if (editing) ColorDialog(item.title, hex, onPick = { model.set(item.key, it) }, onClose = { editing = false })
}

@Composable
private fun ColorDialog(title: String, start: String, onPick: (String) -> Unit, onClose: () -> Unit) {
    var color by remember { mutableStateOf(parseHex(start)) }
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.size(width = 280.dp, height = 48.dp).background(color, RoundedCornerShape(8.dp)))
                var hexText by remember(color) { mutableStateOf(hexOf(color.red, color.green, color.blue)) }
                OutlinedTextField(
                    value = hexText,
                    onValueChange = { hexText = it; if (Regex("#?[0-9a-fA-F]{6}").matches(it)) color = parseHex(it) },
                    singleLine = true, label = { Text("Hex") },
                )
                Slider(color.red, { color = Color(it, color.green, color.blue) })
                Slider(color.green, { color = Color(color.red, it, color.blue) })
                Slider(color.blue, { color = Color(color.red, color.green, it) })
            }
        },
        confirmButton = { TextButton(onClick = { onPick(hexOf(color.red, color.green, color.blue)); onClose() }) { Text("OK") } },
        dismissButton = { TextButton(onClick = onClose) { Text("Cancel") } },
    )
}
