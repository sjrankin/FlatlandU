package com.flatland.nativeui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

// One control per kind of item (the counterpart of ScreenRow in ScreenViews.swift). Pick-lists, numbers and
// colours are in Controls.kt.

@Composable
fun clearColors() = ListItemDefaults.colors(containerColor = Color.Transparent)

fun Modifier.clickableRow(onClick: () -> Unit): Modifier = this.clickable(onClick = onClick)


@Composable
fun ItemRow(model: ScreenModel, item: ScreenItem, navigate: (Route) -> Unit) {
    when (item.kind) {
        ItemKind.Section -> Text(
            item.title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 4.dp),
        )
        ItemKind.Toggle -> {
            val on = valueBool(model.value(item.key))
            ListItem(
                headlineContent = { Text(item.title) },
                trailingContent = { Switch(checked = on, onCheckedChange = { model.set(item.key, it) }) },
                colors = clearColors(),
                modifier = Modifier.clickableRow { model.set(item.key, !on) },
            )
        }
        ItemKind.Choice -> ChoiceRow(model, item, navigate)
        ItemKind.Number -> NumberRow(model, item)
        ItemKind.Color -> ColorRow(model, item)
        ItemKind.Text -> OutlinedTextField(
            value = valueText(model.value(item.key)),
            onValueChange = { model.set(item.key, it) },
            label = { Text(item.title) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
        )
        ItemKind.Action -> ActionButton(model, item)
        ItemKind.Info -> InfoRow(item)
        ItemKind.Paragraph -> ParagraphText(item)
        ItemKind.Row -> ListRow(model, item)
    }
    if (item.kind != ItemKind.Section && item.kind != ItemKind.Paragraph) HorizontalDivider()
}

@Composable
private fun InfoRow(item: ScreenItem) {
    if (item.detail.length > 28) {   // long values (a URL, a status) wrap under their heading
        ListItem(
            headlineContent = { Text(item.title, color = MaterialTheme.colorScheme.primary) },
            supportingContent = { SelectionContainer { Text(item.detail) } },
            colors = clearColors(),
        )
    } else {
        ListItem(
            headlineContent = { Text(item.title) },
            trailingContent = { SelectionContainer { Text(item.detail, textAlign = TextAlign.End) } },
            colors = clearColors(),
        )
    }
}

@Composable
private fun ParagraphText(item: ScreenItem) {
    val pad = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
    when (item.style) {
        "title" -> Text(item.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center, modifier = pad)
        "headline" -> Text(item.title, style = MaterialTheme.typography.titleMedium, modifier = pad)
        "caption" -> Text(item.title, style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = pad)
        "mono" -> SelectionContainer {
            Text(item.title, style = MaterialTheme.typography.bodySmall, fontFamily = FontFamily.Monospace, modifier = pad)
        }
        else -> Text(item.title, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = pad)
    }
}

@Composable
private fun ActionButton(model: ScreenModel, item: ScreenItem) {
    var confirming by remember { mutableStateOf(false) }
    val send = { model.onAction(item.actionId) }
    val modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)
    val click = { if (item.confirm.isEmpty()) send() else confirming = true }
    when (item.style) {
        "prominent" -> Button(onClick = click, modifier = modifier) { Text(item.title) }
        "destructive" -> Button(
            onClick = click, modifier = modifier,
            colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error,
                contentColor = MaterialTheme.colorScheme.onError),
        ) { Text(item.title) }
        else -> FilledTonalButton(onClick = click, modifier = modifier) { Text(item.title) }
    }
    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text(item.confirm) },
            confirmButton = { TextButton(onClick = { confirming = false; send() }) { Text(item.title) } },
            dismissButton = { TextButton(onClick = { confirming = false }) { Text("Cancel") } },
        )
    }
}

/** A list row: optional leading text (a magnitude), title and subtitle, detail on the right, and either a
 *  check box bound to a key or a tap that sends the row's id. */
@Composable
private fun ListRow(model: ScreenModel, item: ScreenItem) {
    val accent = if (item.accent.isEmpty()) MaterialTheme.colorScheme.onSurface else parseHex(item.accent)
    val checked = if (item.checkKey.isNotEmpty()) valueBool(model.value(item.checkKey)) else null
    val tap: () -> Unit = when {
        checked != null -> { { model.set(item.checkKey, !checked) } }
        item.actionId.isNotEmpty() -> { { model.onAction(item.actionId) } }
        else -> { {} }
    }
    ListItem(
        leadingContent = if (item.leading.isEmpty()) null else {
            { Text(item.leading, color = accent, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium) }
        },
        headlineContent = { Text(item.title) },
        supportingContent = if (item.subtitle.isEmpty()) null else { { Text(item.subtitle) } },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (item.detail.isNotEmpty()) Text(item.detail, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (item.selected) Icon(Icons.Filled.Check, contentDescription = "Selected", tint = MaterialTheme.colorScheme.primary)
                if (checked != null) Checkbox(checked = checked, onCheckedChange = { model.set(item.checkKey, it) })
            }
        },
        colors = clearColors(),
        modifier = Modifier.alpha(if (item.dimmed) 0.5f else 1f).clickableRow(tap),
    )
}
