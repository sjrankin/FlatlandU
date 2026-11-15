package com.flatland.nativeui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.LockOpen
import androidx.compose.material.icons.outlined.MonitorHeart
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.RestartAlt
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.SettingsInputAntenna
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.material.icons.filled.StopCircle
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import org.json.JSONArray

// The button bar (the counterpart of NativeToolbar.swift). Godot sends the buttons as JSON:
// [{id, title, symbol, selected, menu: [{id, title}]}]. `symbol` is an SF Symbol name (iOS); the table below
// gives the Material icon used for it here. A button with a `menu` opens a pop-up menu of entries instead of
// sending its own id. The bar lays itself out in as many equal rows as the width needs, so every button is
// visible, and reports its height (in pixels, without the navigation bar) so Godot can leave room for it.

data class ToolbarEntry(val id: String, val title: String)

data class ToolbarButton(val id: String, val title: String, val symbol: String, val selected: Boolean, val menu: List<ToolbarEntry>)

class ToolbarModel {
    var buttons by mutableStateOf(listOf<ToolbarButton>())
        private set
    var onTap: (String) -> Unit = {}

    fun update(json: String) {
        val list = try { JSONArray(json) } catch (e: Exception) { return }
        buttons = (0 until list.length()).mapNotNull { i ->
            val d = list.getJSONObject(i)
            val id = d.optString("id").ifEmpty { return@mapNotNull null }
            val menu = d.optJSONArray("menu")
            ToolbarButton(
                id, d.optString("title", id), d.optString("symbol"), d.optBoolean("selected"),
                if (menu == null) emptyList() else (0 until menu.length()).map {
                    val m = menu.getJSONObject(it)
                    ToolbarEntry(m.optString("id"), m.optString("title"))
                },
            )
        }
    }
}

private fun iconFor(symbol: String): ImageVector = when (symbol) {
    "info.circle" -> Icons.Outlined.Info
    "ladybug" -> Icons.Outlined.BugReport
    "antenna.radiowaves.left.and.right" -> Icons.Outlined.SettingsInputAntenna
    "gearshape" -> Icons.Outlined.Settings
    "lock.fill" -> Icons.Outlined.Lock
    "lock.open" -> Icons.Outlined.LockOpen
    "arrow.counterclockwise" -> Icons.Outlined.RestartAlt
    "camera" -> Icons.Outlined.PhotoCamera
    "video" -> Icons.Outlined.Videocam
    "stop.circle.fill" -> Icons.Filled.StopCircle
    "waveform.path.ecg" -> Icons.Outlined.MonitorHeart
    "globe" -> Icons.Outlined.Public
    "ellipsis.circle" -> Icons.Outlined.MoreHoriz
    else -> Icons.Outlined.Circle
}

private val RowHeight = 56.dp
private val MinimumCell = 72.dp

@Composable
fun ToolbarContent(model: ToolbarModel, onHeight: (Int) -> Unit) {
    Surface(color = MaterialTheme.colorScheme.surfaceContainer, tonalElevation = 3.dp) {
        BoxWithConstraints(Modifier.fillMaxWidth().navigationBarsPadding()) {
            val count = model.buttons.size
            val fit = maxOf(1, minOf(maxOf(count, 1), (maxWidth / MinimumCell).toInt()))
            val rows = if (count == 0) 0 else (count + fit - 1) / fit
            val columns = if (rows == 0) 1 else (count + rows - 1) / rows   // equal rows
            Column(Modifier.onSizeChanged { onHeight(it.height) }) {
                HorizontalDivider()
                for (row in model.buttons.chunked(columns)) {
                    Row(Modifier.fillMaxWidth().height(RowHeight)) {
                        for (button in row) ToolbarCell(button, model.onTap)
                        repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun RowScope.ToolbarCell(button: ToolbarButton, onTap: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val tint = if (button.selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
    Column(
        Modifier.weight(1f).height(RowHeight).clickable {
            if (button.menu.isEmpty()) onTap(button.id) else open = true
        },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(iconFor(button.symbol), contentDescription = button.title, tint = tint, modifier = Modifier.size(26.dp))
        Text(button.title, color = tint, style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for (entry in button.menu) {
                DropdownMenuItem(text = { Text(entry.title) }, onClick = { open = false; onTap(entry.id) })
            }
        }
    }
}
