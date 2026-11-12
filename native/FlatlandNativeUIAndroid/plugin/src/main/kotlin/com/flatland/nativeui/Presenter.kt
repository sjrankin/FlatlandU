package com.flatland.nativeui

import android.app.Activity
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.tween
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy

// Puts Compose views on screen over Godot's view. Both are added to the activity's content, above the
// game surface, so Android's own touch handling reaches them first.

private fun Activity.overlay(params: FrameLayout.LayoutParams, content: @androidx.compose.runtime.Composable () -> Unit): ComposeView {
    val view = ComposeView(this)
    view.setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindow)
    view.setContent(content)
    addContentView(view, params)
    return view
}

private fun ComposeView.detach() {
    (parent as? ViewGroup)?.removeView(this)
}

/** A full-screen sheet that slides up (and back down when it is dismissed). */
class SheetPresenter {
    var onClosed: () -> Unit = {}
    private var view: ComposeView? = null
    private var notify = true
    private val visible = MutableTransitionState(false)

    fun present(activity: Activity, model: ScreenModel) {
        visible.targetState = false
        val params = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        view = activity.overlay(params) {
            NativeTheme {
                AnimatedVisibility(
                    visibleState = visible,
                    enter = slideInVertically(tween(260)) { it },
                    exit = slideOutVertically(tween(220)) { it },
                ) {
                    Surface(Modifier.fillMaxSize()) { ScreenRoot(model) }
                }
                // Once the slide-out has finished, remove the view and say so.
                LaunchedEffect(visible.currentState, visible.isIdle) {
                    if (!visible.currentState && visible.isIdle) finish()
                }
            }
        }
        visible.targetState = true
    }

    fun dismiss(notify: Boolean, animated: Boolean = true) {
        val v = view ?: return
        this.notify = notify
        if (animated) {
            visible.targetState = false
        } else {
            view = null
            v.detach()
        }
    }

    private fun finish() {
        val v = view ?: return
        view = null
        v.detach()
        if (notify) onClosed()
    }
}

/** The button bar along the bottom edge. */
class ToolbarPresenter {
    var onHeight: (Int) -> Unit = {}
    private var view: ComposeView? = null

    fun show(activity: Activity, model: ToolbarModel) {
        if (view != null) return
        val params = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM)
        view = activity.overlay(params) { NativeTheme { ToolbarContent(model) { onHeight(it) } } }
    }

    fun hide() {
        view?.detach()
        view = null
        onHeight(0)
    }
}
