extends PanelContainer
## The status bar along the bottom of the main view (Flatland's StatusBar2D): a dark
## rounded bar with a navy border that shows transient messages such as new earthquakes.

var _label: Label
var _queue: Array = []
var _timer: Timer
var _pushed := ""
var _pushed_until_msec := 0

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

## Show `text` for `seconds`, queuing behind any message already showing.
func post(text: String, seconds: float = 6.0) -> void:
	_queue.append([text, seconds])
	if _timer.is_stopped():
		_next()

## Keep `text` for `seconds` and show it whenever no other message is showing (Flatland's pushed message).
func push(text: String, seconds: float) -> void:
	_pushed = text
	_pushed_until_msec = Time.get_ticks_msec() + int(seconds * 1000.0)
	if _timer.is_stopped():
		_next()

func _pushed_active() -> bool:
	return _pushed != "" and Time.get_ticks_msec() < _pushed_until_msec

## Replace whatever is showing (used for the live mouse coordinates).
func show_persistent(text: String) -> void:
	if _timer.is_stopped() and not _pushed_active():
		_label.text = text

func _next() -> void:
	if _queue.is_empty():
		_label.text = _pushed if _pushed_active() else ""
		if _pushed_active():
			_timer.start(maxf(0.1, (_pushed_until_msec - Time.get_ticks_msec()) / 1000.0))
		return
	var item: Array = _queue.pop_front()
	_label.text = item[0]
	_timer.start(item[1])
