class_name NativeUI
extends RefCounted
## Bridge to the native user interface: real SwiftUI screens (iOS, a Swift extension in native/FlatlandNativeUI)
## or Jetpack Compose screens (Android, a plugin in native/FlatlandNativeUIAndroid) instead of Godot-drawn
## dialogs. Phones use it for the dialogs below; macOS can with `-- --native-ui`.
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
## without the plugin) available() is false and the Godot dialog is used.

const CLASS_NAME := "FlatlandNativeUI"

static var _bridge: Object = null
static var _open := false
static var _owner: Object = null
static var _last_json := ""
static var _forced := -1
static var _toolbar_owner: Object = null
static var _toolbar_json := ""
static var _toolbar_px := 0

## Should native screens be used on this platform?
static func wanted() -> bool:
	return (Layout.is_phone() or _forced_on()) and available()

static func _forced_on() -> bool:
	if _forced < 0:
		_forced = 1 if "--native-ui" in OS.get_cmdline_user_args() else 0
	return _forced == 1

## Is the button bar native? On iOS it replaces the Godot one; on macOS with `--native-ui` it is an extra window.
static func toolbar_wanted() -> bool:
	return wanted()

## Show the owner's button bar: owner.native_toolbar() -> Array of {id, title, symbol, selected, menu}.
## The owner gets native_toolbar_event(id) for taps and native_toolbar_resized() when the bar's height changes.
static func show_toolbar(owner: Object) -> bool:
	if not available() or not owner.has_method("native_toolbar"):
		return false
	_connect()
	_toolbar_owner = owner
	_toolbar_json = JSON.stringify(owner.call("native_toolbar"))
	_call("show_toolbar", _toolbar_json)
	return true

## The buttons changed (a toggle, say): send the new list if it is different.
static func refresh_toolbar() -> void:
	if _toolbar_owner == null or not is_instance_valid(_toolbar_owner):
		return
	var json := JSON.stringify(_toolbar_owner.call("native_toolbar"))
	if json == _toolbar_json:
		return
	_toolbar_json = json
	_call("update_toolbar", json)

## Height of the native bar in pixels, without the bottom safe area (0 until it is up).
static func toolbar_height() -> int:
	return _toolbar_px

static func _on_toolbar_tapped(id: String) -> void:
	if _toolbar_owner != null and is_instance_valid(_toolbar_owner):
		_toolbar_owner.call("native_toolbar_event", id)

static func _on_toolbar_height(pixels: int) -> void:
	_toolbar_px = pixels
	if _toolbar_owner != null and is_instance_valid(_toolbar_owner) and _toolbar_owner.has_method("native_toolbar_resized"):
		_toolbar_owner.call("native_toolbar_resized")

## True when the Swift extension is loaded.
static func available() -> bool:
	if OS.get_name() == "Android":
		return Engine.has_singleton(CLASS_NAME)   # the Kotlin plugin registers itself as a singleton
	return ClassDB.class_exists(CLASS_NAME)

## The device's power state from the native code: "normal", "low_power" (Low Power Mode / Battery Saver),
## "thermal" (hot) or "critical". "normal" where there is no native code.
static func power_state() -> String:
	if not available():
		return "normal"
	_connect()
	var method := "power_state" if _bridge.has_method("power_state") else "powerState"
	return str(_bridge.call(method))

static func is_open() -> bool:
	return _open

## Is the native screen of `owner` the one on display?
static func is_showing(owner: Object) -> bool:
	return _open and _owner == owner

## Show the native screen for `owner` (a dialog with native_screen / native_event). If a native screen is
## already open its content is replaced, so the sheet stays up. Returns false if the extension is not there.
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
		if Layout.is_phone():
			PowerManager.set_covered(true)   # nothing to draw under a full-screen sheet
		_call("show_screen", JSON.stringify(data["screen"]), JSON.stringify(data["values"]))
	return true

## The owner's data changed: send the new screen if it is not the same as the last one sent.
static func refresh(owner: Object) -> void:
	if not is_showing(owner):
		return
	var data: Dictionary = owner.call("native_screen")
	var json := JSON.stringify(data)
	if json == _last_json:
		return
	_last_json = json
	_call("update_screen", JSON.stringify(data["screen"]), JSON.stringify(data["values"]))

static func close() -> void:
	if _bridge != null and _open:
		_call("close_screen")

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

## SwiftGodot exposes a Swift method under its Swift (camelCase) name; accept snake_case too.
static func _call(snake_name: String, a: Variant = null, b: Variant = null) -> void:
	var camel := snake_name.to_camel_case()
	var method := snake_name if _bridge.has_method(snake_name) else camel
	if a == null:
		_bridge.call(method)
	elif b == null:
		_bridge.call(method, a)
	else:
		_bridge.call(method, a, b)

static func _on_value_changed(key: String, value_json: String) -> void:
	if _owner != null:
		_owner.call("native_event", "value", key, JSON.parse_string(value_json))

static func _on_action_triggered(id: String) -> void:
	if _owner != null:
		_owner.call("native_event", "action", id, null)

static func _on_closed() -> void:
	_open = false
	PowerManager.set_covered(false)
	var owner := _owner
	_owner = null
	_last_json = ""
	if owner != null and is_instance_valid(owner):
		owner.call("native_event", "closed", "", null)

## A setting changed from somewhere else (Reset All Settings, for example): show it in the native screen.
static func _on_setting_changed(key: String, value: Variant) -> void:
	if _open and _bridge != null:
		_call("update_value", key, JSON.stringify(value))

## Store a value that came from a native control into Settings, as the type Settings already holds.
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
