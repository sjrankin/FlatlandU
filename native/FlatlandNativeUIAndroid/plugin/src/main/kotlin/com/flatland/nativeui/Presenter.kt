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

/**
 * Adds a Compose view over Godot's view: it is added to the activity's content, above the game surface, so Android's
 * own touch handling reaches it first. It is disposed when it leaves the window.
 *
 * @receiver the activity.
 * @param params the layout parameters (size and gravity).
 * @param content the Compose content.
 * @return the view.
 */
private fun Activity.overlay(params: FrameLayout.LayoutParams, content: @androidx.compose.runtime.Composable () -> Unit): ComposeView {
    val view = ComposeView(this)
    view.setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindow)
    view.setContent(content)
    addContentView(view, params)
    return view
}

/**
 * Removes a Compose view from its parent.
 *
 * @receiver the view.
 */
private fun ComposeView.detach() {
    (parent as? ViewGroup)?.removeView(this)
}

/**
 * A full-screen sheet that slides up (and back down when it is dismissed), showing the Compose screen ([ScreenRoot])
 * over Godot's view.
 */
class SheetPresenter {
    /**
     * Called when the sheet has finished leaving and been removed (unless the dismissal was silent).
     */
    var onClosed: () -> Unit = {}
    /**
     * The Compose view of the sheet; null when none.
     */
    private var view: ComposeView? = null
    /**
     * Whether [onClosed] should be called when the sheet has gone (false when Godot asked for the close).
     */
    private var notify = true
    /**
     * The sheet's slide state; setting its target to true slides it in, false slides it out.
     */
    private val visible = MutableTransitionState(false)

    /**
     * Shows the sheet, sliding up over 260 ms.
     *
     * @param activity the activity to add the view to.
     * @param model the screen's model.
     */
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

    /**
     * Closes the sheet.
     *
     * @param notify true to call [onClosed] afterwards; false when Godot asked for the close or is replacing the
     *   screen.
     * @param animated true to slide it out (220 ms); false to remove it at once.
     */
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

    /**
     * Called when the slide-out has ended: removes the view and calls [onClosed] if wanted.
     */
    private fun finish() {
        val v = view ?: return
        view = null
        v.detach()
        if (notify) onClosed()
    }
}

/**
 * The button bar along the bottom edge of the screen, drawn by [ToolbarContent].
 */
class ToolbarPresenter {
    /**
     * Called with the bar's height in pixels when it changes (0 when hidden).
     */
    var onHeight: (Int) -> Unit = {}
    /**
     * The Compose view of the bar; null when hidden.
     */
    private var view: ComposeView? = null

    /**
     * Shows the bar, if it is not already showing.
     *
     * @param activity the activity to add the view to.
     * @param model the bar's model.
     */
    fun show(activity: Activity, model: ToolbarModel) {
        if (view != null) return
        val params = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM)
        view = activity.overlay(params) { NativeTheme { ToolbarContent(model) { onHeight(it) } } }
    }

    /**
     * Takes the bar off the screen and reports a height of 0.
     */
    fun hide() {
        view?.detach()
        view = null
        onHeight(0)
    }
}
