extends PanelContainer
## The status bar along the bottom of the main view (Flatland's StatusBar2D): a dark
## rounded bar with a navy border that shows transient messages such as new earthquakes.

## The Label that shows the current message.
var _label: Label
## Messages waiting their turn, each [text, seconds]; filled by [method post].
var _queue: Array = []
## One-shot timer that ends the current message and calls [method _next].
var _timer: Timer
## The pushed (standing) message set by [method push], shown whenever nothing else is.
var _pushed := ""
## `Time.get_ticks_msec()` when the pushed message expires.
var _pushed_until_msec := 0

## Builds the bar: a dark rounded panel with a navy border and one label (two wrapped lines on phones, one clipped
## line on a desktop), the message timer, and visibility that follows the `show_status_bar` setting.
func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.7)
	sb.border_color = Color("#1f3a7a")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", Layout.font(22, 0.85))
	_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	if Layout.is_phone():
		# Phones get two lines of larger text, wrapped on word boundaries.
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.max_lines_visible = 2
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	else:
		_label.clip_text = true
	add_child(_label)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_next)
	add_child(_timer)
	visible = Settings.get_bool("show_status_bar")
	Settings.changed.connect(func(k: String, v: Variant) -> void:
		if k == "show_status_bar":
			visible = bool(v))

## Shows a message for a while, queuing behind any message already showing.
##
## [param text]: the message.
## [param seconds]: how long to show it (default 6).
func post(text: String, seconds: float = 6.0) -> void:
	_queue.append([text, seconds])
	if _timer.is_stopped():
		_next()

## Replaces the message that is showing right now (for a message that reports progress, such as a download), leaving the
## queued messages alone, except that a queued copy of [param replaces] is dropped (so an old "downloading" message that
## never got its turn does not appear after the final one). If nothing is showing, it simply shows this message.
##
## [param text]: the new message.
## [param seconds]: how long to show it.
## [param replaces]: text of a queued message to remove, or "" for none.
func update_current(text: String, seconds: float = 6.0, replaces := "") -> void:
	if replaces != "":
		_queue = _queue.filter(func(item: Array) -> bool: return item[0] != replaces)
	_label.text = text
	_timer.start(seconds)

## Sets a standing message (Flatland's "pushed" message) that appears whenever no posted message is showing, until it
## expires.
##
## [param text]: the message.
## [param seconds]: how long it stays eligible.
func push(text: String, seconds: float) -> void:
	_pushed = text
	_pushed_until_msec = Time.get_ticks_msec() + int(seconds * 1000.0)
	if _timer.is_stopped():
		_next()

## Whether the pushed message is set and not yet expired.
##
## Returns: true if it should be shown.
func _pushed_active() -> bool:
	return _pushed != "" and Time.get_ticks_msec() < _pushed_until_msec

## Replaces what is showing with live text (used for the mouse coordinates). Ignored while a posted or pushed message
## is showing.
##
## [param text]: the text.
func show_persistent(text: String) -> void:
	if _timer.is_stopped() and not _pushed_active():
		_label.text = text

## Moves on after a message: shows the next queued message (and starts the timer for it), or the pushed message if it
## is still active, or clears the bar.
func _next() -> void:
	if _queue.is_empty():
		_label.text = _pushed if _pushed_active() else ""
		if _pushed_active():
			_timer.start(maxf(0.1, (_pushed_until_msec - Time.get_ticks_msec()) / 1000.0))
		return
	var item: Array = _queue.pop_front()
	_label.text = item[0]
	_timer.start(item[1])
