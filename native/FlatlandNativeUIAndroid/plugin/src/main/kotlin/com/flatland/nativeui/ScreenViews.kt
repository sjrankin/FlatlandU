package com.flatland.nativeui

import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext

// The Android counterpart of ScreenViews.swift: a screen described by Godot, drawn with Material 3.

@Composable
fun NativeTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val context = LocalContext.current
    val scheme = when {
        Build.VERSION.SDK_INT >= 31 -> if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        dark -> darkColorScheme()
        else -> lightColorScheme()
    }
    MaterialTheme(colorScheme = scheme, content = content)
}

/** Where the user is inside the screen: the list of pages, one page, or the list of options of a choice. */
sealed interface Route {
    data class Page(val title: String) : Route
    data class Choice(val key: String) : Route
}

/**
 * The top level. A screen with several pages shows a list of them (as the system Settings does); a screen with
 * one page shows that page directly. Back goes up one level, and out of the screen from the top.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScreenRoot(model: ScreenModel) {
    var stack by remember { mutableStateOf(listOf<Route>()) }
    val schema = model.schema
    val route = stack.lastOrNull()
    val goBack = { if (stack.isEmpty()) model.onDone() else stack = stack.dropLast(1) }
    BackHandler(onBack = goBack)

    val allItems = schema.pages.flatMap { it.items } + schema.rootItems
    val title = when (route) {
        is Route.Page -> route.title
        is Route.Choice -> allItems.firstOrNull { it.kind == ItemKind.Choice && it.key == route.key }?.title ?: ""
        null -> schema.title
    }
    Scaffold(topBar = {
        TopAppBar(
            title = { Text(title) },
            navigationIcon = {
                if (stack.isNotEmpty()) {
                    IconButton(onClick = goBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                }
            },
            actions = { TextButton(onClick = model.onDone) { Text(schema.doneTitle) } },
        )
    }) { padding ->
        Box(Modifier.padding(padding)) {
            val navigate = { next: Route -> stack = stack + next }
            when (route) {
                is Route.Page -> ItemList(model, schema.pages.firstOrNull { it.title == route.title }?.items ?: emptyList(), navigate)
                is Route.Choice -> allItems.firstOrNull { it.kind == ItemKind.Choice && it.key == route.key }
                    ?.let { ChoiceList(model, it) }
                null -> if (schema.pages.size == 1) {
                    ItemList(model, schema.pages[0].items, navigate)
                } else {
                    PageList(model, navigate)
                }
            }
        }
    }
}

@Composable
private fun PageList(model: ScreenModel, navigate: (Route) -> Unit) {
    LazyColumn {
        items(model.schema.pages, key = { it.title }) { page ->
            ListItem(
                headlineContent = { Text(page.title) },
                trailingContent = { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null) },
                colors = clearColors(),
                modifier = Modifier.clickableRow { navigate(Route.Page(page.title)) },
            )
            HorizontalDivider()
        }
        items(model.schema.rootItems, key = { it.id }) { item -> ItemRow(model, item, navigate) }
    }
}

/** The items of one page; a section item is a heading for the ones after it. */
@Composable
fun ItemList(model: ScreenModel, items: List<ScreenItem>, navigate: (Route) -> Unit) {
    LazyColumn {
        items(items, key = { it.id }) { item -> ItemRow(model, item, navigate) }
    }
}
