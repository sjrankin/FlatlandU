extends PanelContainer
## The status bar along the bottom of the main view (Flatland's StatusBar2D): a dark
## rounded bar with a navy border that shows transient messages such as new earthquakes.

var _label: Label
var _queue: Array = []
var _timer: Timer

func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.border_color = Color("#1f3a7a")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
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

## Replace whatever is showing (used for the live mouse coordinates).
func show_persistent(text: String) -> void:
	if _timer.is_stopped():
		_label.text = text

func _next() -> void:
	if _queue.is_empty():
		_label.text = ""
		return
	var item: Array = _queue.pop_front()
	_label.text = item[0]
	_timer.start(item[1])
