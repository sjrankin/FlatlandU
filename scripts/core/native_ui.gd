class_name NativeUI
extends RefCounted
## Bridge to the native user interface: real SwiftUI screens (iOS, a Swift extension in native/FlatlandNativeUI)
## or Jetpack Compose screens (Android, a plugin in native/FlatlandNativeUIAndroid) instead of Godot-drawn
## dialogs. iOS, macOS and Android use it for the dialogs below and for the button bar along the bottom of the window.
##
## A dialog that has a native version provides two methods:
##   native_screen() -> Dictionary   {"screen": {title, pages: [{title, items: [...]}], ...}, "values": {key: value}}
##   native_event(kind: String, key: String, value: Variant) -> void
##       kind "value":  the user edited the control `key` (value is the new value)
##       kind "action": the user tapped the button or row whose id is `key`
##       kind "closed": the screen went away
## `main.gd` calls present() instead of popping up the Godot dialog. The dialogs tell NativeUI when their data
## changed (refresh), and it sends the new screen description over only if it is different.
##
## Godot -> native: JSON text through the extension's showScreen / updateScreen / updateValue / closeScreen.
## Native -> Godot: its signals value_changed(key, json), action_triggered(id), sheet_closed().
## Both platforms have the same calls and signals. Where the native code is missing (a desktop build, or a build
## without the plugin, or Windows and Linux) available() is false and the Godot dialog is used.

## Name of the native extension class (a Swift GDExtension on iOS and macOS, a Kotlin plugin singleton on Android).
const CLASS_NAME := "FlatlandNativeUI"

## The native extension object, created by [method _connect] on first use; null until then.
static var _bridge: Object = null
## True while a native dialog is on screen.
static var _open := false
## The Godot dialog (an Object with native_screen and native_event) whose native screen is showing.
static var _owner: Object = null
## The last screen description sent, so [method refresh] sends only real changes.
static var _last_json := ""
## The object (main.gd) that supplies the native button bar's buttons and gets its taps.
static var _toolbar_owner: Object = null
## The last button list sent to the native bar, so [method refresh_toolbar] sends only changes.
static var _toolbar_json := ""
## Height of the native bar in pixels as last reported by the native code; 0 until it is up. Read with
## [method toolbar_height].
static var _toolbar_px := 0

## Whether native screens should be used on this platform: on phones and macOS when the extension is present. Not when
## the app runs embedded in the editor's Game tab (see [method _embedded]): that process has no Cocoa event loop of
## its own, so a native window it opens would hang (a beach ball) and the native bar could not be seen. There the
## Godot dialogs and toolbar are used.
##
## Returns: true to use native dialogs.
static func wanted() -> bool:
	return (Layout.is_phone() or OS.get_name() == "macOS") and available() and not _embedded()

## Whether the app is running embedded in the Godot editor's Game tab.
##
## Returns: true if embedded (by the engine's own report or the `--embedded` argument).
static func _embedded() -> bool:
	return Engine.is_embedded_in_editor() or "--embedded" in OS.get_cmdline_args()

## Whether the button bar should be native: [method wanted], unless the bar failed to come up
## ([method give_up_toolbar]) or the `--no-native-toolbar` development flag was given (for trying the fallback).
##
## Returns: true to use the native bar.
static func toolbar_wanted() -> bool:
	return wanted() and not _toolbar_given_up \
			and not "--no-native-toolbar" in OS.get_cmdline_user_args()      # (the flag is for trying the fallback)

## Set by [method give_up_toolbar] when the native bar did not appear; [method toolbar_wanted] then answers false for
## the rest of the run.
static var _toolbar_given_up := false

## The native bar did not come up (its window could not be found): hides it, and from now on [method toolbar_wanted]
## is false so main.gd builds Godot's own bar.
static func give_up_toolbar() -> void:
	_toolbar_given_up = true
	if _bridge != null:
		_call("hide_toolbar")
	_toolbar_px = 0
	_toolbar_owner = null

## Shows the native button bar for an owner. The owner must have `native_toolbar() -> Array` returning buttons ({id,
## title, symbol, selected, menu}); it then gets `native_toolbar_event(id)` for taps and, if it has it,
## `native_toolbar_resized()` when the bar's height changes.
##
## [param owner]: the object that supplies the buttons (main.gd).
## Returns: false if the extension is missing or the owner lacks `native_toolbar`.
## See also [method refresh_toolbar].
static func show_toolbar(owner: Object) -> bool:
	if not available() or not owner.has_method("native_toolbar"):
		return false
	_connect()
	_toolbar_owner = owner
	_toolbar_json = JSON.stringify(owner.call("native_toolbar"))
	_call("show_toolbar", _toolbar_json)
	return true

## Call when a button's state changed (a toggle, the recording state...). Re-reads the owner's `native_toolbar()` and
## sends the list to the native bar if it is different.
static func refresh_toolbar() -> void:
	if _toolbar_owner == null or not is_instance_valid(_toolbar_owner):
		return
	var json := JSON.stringify(_toolbar_owner.call("native_toolbar"))
	if json == _toolbar_json:
		return
	_toolbar_json = json
	_call("update_toolbar", json)

## Height of the native bar.
##
## Returns: pixels, without the bottom safe area; 0 until the bar is up.
static func toolbar_height() -> int:
	return _toolbar_px

## The native bar reports a button tap: forwards it to the owner's `native_toolbar_event`.
##
## [param id]: the tapped button's id.
static func _on_toolbar_tapped(id: String) -> void:
	if _toolbar_owner != null and is_instance_valid(_toolbar_owner):
		_toolbar_owner.call("native_toolbar_event", id)

## The native bar reports its height: stores it and tells the owner (`native_toolbar_resized`) so the views can make
## room.
##
## [param pixels]: the bar's height in pixels.
static func _on_toolbar_height(pixels: int) -> void:
	_toolbar_px = pixels
	if _toolbar_owner != null and is_instance_valid(_toolbar_owner) and _toolbar_owner.has_method("native_toolbar_resized"):
		_toolbar_owner.call("native_toolbar_resized")

## Whether the native extension is loaded: the Kotlin singleton on Android, the Swift class elsewhere.
##
## Returns: true if the native code is there.
static func available() -> bool:
	if OS.get_name() == "Android":
		return Engine.has_singleton(CLASS_NAME)   # the Kotlin plugin registers itself as a singleton
	return ClassDB.class_exists(CLASS_NAME)

## The device's power state from the native code, read by PowerManager.
##
## Returns: "normal", "low_power" (Low Power Mode or Battery Saver), "thermal" (hot) or "critical"; "normal" where
##   there is no native code.
static func power_state() -> String:
	if not available():
		return "normal"
	_connect()
	var method := "power_state" if _bridge.has_method("power_state") else "powerState"
	return str(_bridge.call(method))

## Whether a native dialog is on screen.
##
## Returns: true while one is open.
static func is_open() -> bool:
	return _open

## Whether a particular dialog's native screen is the one on display.
##
## [param owner]: the Godot dialog object.
## Returns: true if it is showing.
static func is_showing(owner: Object) -> bool:
	return _open and _owner == owner

## Shows the native screen for a dialog. The dialog must have `native_screen() -> Dictionary` ({"screen": ...,
## "values": ...}). If a native screen is already open its content is replaced so the sheet stays up. While a dialog
## is open drawing is stopped with [method PowerManager.set_covered].
##
## [param owner]: the Godot dialog object.
## Returns: false if the extension is missing or the dialog has no `native_screen` (the caller then shows the Godot
##   dialog).
## See also [method refresh], [method close].
static func present(owner: Object) -> bool:
	if not available() or not owner.has_method("native_screen"):
		return false
	_connect()
	_owner = owner
	var data: Dictionary = owner.call("native_screen")
	_last_json = JSON.stringify(data)
	if _open:
		_call("update_screen", JSON.stringify(data["screen"]), JSON.stringify(data["values"]))
	else:
		_open = true
		# Nothing is drawn under a full-screen sheet on a phone. On a desktop the dialog is a window of its own that shares the
		# main thread with Godot, and a Godot window half hidden behind it makes Godot wait up to a second for each frame
		# (in nextDrawable), which froze the dialog (a beach ball), so drawing stops there too while a dialog is open.
		PowerManager.set_covered(true)
		_call("show_screen", JSON.stringify(data["screen"]), JSON.stringify(data["values"]))
	return true

## The dialog's data changed: sends the new screen only if it differs from the last one sent.
##
## [param owner]: the dialog; ignored unless its screen is the one showing.
static func refresh(owner: Object) -> void:
	if not is_showing(owner):
		return
	var data: Dictionary = owner.call("native_screen")
	var json := JSON.stringify(data)
	if json == _last_json:
		return
	_last_json = json
	_call("update_screen", JSON.stringify(data["screen"]), JSON.stringify(data["values"]))

## Asks the native code to close the open screen. The close is confirmed by [method _on_closed].
static func close() -> void:
	if _bridge != null and _open:
		_call("close_screen")

## Creates the native bridge object on first use and connects its signals (value_changed, action_triggered,
## sheet_closed, toolbar_tapped, toolbar_height_changed), and starts watching settings for
## [method _on_setting_changed].
static func _connect() -> void:
	if _bridge != null:
		return
	_bridge = Engine.get_singleton(CLASS_NAME) if OS.get_name() == "Android" else ClassDB.instantiate(CLASS_NAME)
	_bridge.connect("value_changed", _on_value_changed)
	_bridge.connect("action_triggered", _on_action_triggered)
	_bridge.connect("sheet_closed", _on_closed)
	_bridge.connect("toolbar_tapped", _on_toolbar_tapped)
	_bridge.connect("toolbar_height_changed", _on_toolbar_height)
	Settings.changed.connect(_on_setting_changed)

## Calls a method on the native bridge. SwiftGodot exposes a Swift method under its camelCase name, so the snake_case
## name is tried first and then the camelCase one.
##
## [param snake_name]: the method name, like "show_screen".
## [param a]: first argument, or null for none.
## [param b]: second argument, or null for none.
static func _call(snake_name: String, a: Variant = null, b: Variant = null) -> void:
	var camel := snake_name.to_camel_case()
	var method := snake_name if _bridge.has_method(snake_name) else camel
	if a == null:
		_bridge.call(method)
	elif b == null:
		_bridge.call(method, a)
	else:
		_bridge.call(method, a, b)

## The user edited a control in the native screen: parses the JSON and passes it to the dialog as
## `native_event("value", key, value)`.
##
## [param key]: the control's key.
## [param value_json]: the new value as JSON text.
static func _on_value_changed(key: String, value_json: String) -> void:
	if _owner != null:
		_owner.call("native_event", "value", key, JSON.parse_string(value_json))

## The user tapped a button or row in the native screen: calls the dialog's `native_event("action", id, null)`.
##
## [param id]: the button's or row's id.
static func _on_action_triggered(id: String) -> void:
	if _owner != null:
		_owner.call("native_event", "action", id, null)

## The native screen went away: clears the open state, lets drawing resume and calls the dialog's
## `native_event("closed", "", null)`.
static func _on_closed() -> void:
	_open = false
	PowerManager.set_covered(false)
	var owner := _owner
	_owner = null
	_last_json = ""
	if owner != null and is_instance_valid(owner):
		owner.call("native_event", "closed", "", null)

## A setting changed somewhere else (Reset All Settings, for example): if a native screen is open, updates the
## matching control in it.
##
## [param key]: the setting's key.
## [param value]: its new value.
static func _on_setting_changed(key: String, value: Variant) -> void:
	if _open and _bridge != null:
		_call("update_value", key, JSON.stringify(value))

## Stores a value that came from a native control into Settings, converted to the type the setting already has (native
## code sends JSON, where an int may arrive as a float).
##
## [param key]: the setting's key.
## [param value]: the value from the native control.
static func store_setting(key: String, value: Variant) -> void:
	var current: Variant = Settings.get_value(key)
	if current is bool:
		value = bool(value)
	elif current is int:
		value = int(value)
	elif current is float:
		value = float(value)
	elif current is String:
		value = str(value)
	Settings.set_value(key, value)
