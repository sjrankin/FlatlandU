class_name PhoneSheet
extends RefCounted
## Turns a desktop dialog (a Window) into a full-screen sheet on phones (iOS and Android).
## The dialogs are laid out as Window > PanelContainer > VBoxContainer; on a phone this removes the
## title bar (so there is no x button) and the minimum size, and rebuilds that VBoxContainer as:
##   title / the dialog's content (scrolling) / a footer.
## The footer keeps the dialog's own bottom row of buttons on the left and puts one Close button on the
## right. Sheets slide up from the toolbar at the bottom of the screen and slide back down when closed.
## On desktop none of this applies.

const SLIDE_IN := 0.28
const SLIDE_OUT := 0.22

static func wrap(w: Window) -> void:
	if not Layout.is_phone():
		return
	w.set_meta("phone_sheet", true)
	w.borderless = true
	w.min_size = Vector2i.ZERO
	# The Close / Back button, the x button and Android's back gesture all slide the sheet down.
	if w.close_requested.is_connected(w.hide):
		w.close_requested.disconnect(w.hide)
	w.close_requested.connect(func() -> void: dismiss(w))
	var boxes := w.find_children("*", "VBoxContainer", true, false)
	if boxes.is_empty():
		return
	var vb := boxes[0] as VBoxContainer
	_pad(vb)
	var rest: Array[Node] = []
	for c in vb.get_children():
		rest.append(c)
	# The dialog's own Close / Done buttons are replaced by the footer's single Close button.
	for b in w.find_children("*", "Button", true, false):
		if (b as Button).text == "Close" or (b as Button).text == "Done":
			(b as Button).visible = false
	# Its bottom row of other buttons moves to the footer, on the left.
	var bar: Control = null
	if not rest.is_empty() and (rest.back() is BoxContainer or rest.back() is FlowContainer):
		bar = rest.back() as Control
		rest.erase(bar)
		vb.remove_child(bar)
	# Status text in that row (a Label) would be squeezed beside the buttons: show it above the footer.
	var status: Array[Label] = []
	if bar != null:
		for c in bar.get_children():
			if c is Label:
				status.append(c as Label)
		for l in status:
			bar.remove_child(l)
			l.size_flags_horizontal = Control.SIZE_FILL
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Title (no x button on a phone).
	var heading := Label.new()
	heading.text = w.title
	heading.clip_text = true
	heading.add_theme_font_size_override("font_size", int(round(PhoneTheme.text_px() * 1.3)))
	vb.add_child(heading)
	vb.move_child(heading, 0)
	if not w.has_meta("sheet_no_scroll"):
		# A scroll area does not pass a too-wide child's minimum width up to the window, so one long
		# label can no longer push the sheet off the right edge of the screen.
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		for c in rest:
			vb.remove_child(c)
			body.add_child(c)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.add_child(body)
		vb.add_child(scroll)
	for l in status:
		vb.add_child(l)
	vb.add_child(_footer(w, bar))

static func _footer(w: Window, bar: Control) -> Control:
	var footer := HBoxContainer.new()
	if bar != null:
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(bar)
	else:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(spacer)
	var close := Button.new()
	close.text = "Close"
	close.size_flags_vertical = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void: dismiss(w))
	footer.add_child(close)
	return footer

## Slide the sheet up from the bottom edge to `rect` and show it.
static func present(w: Window, rect: Rect2i, from_y: int) -> void:
	if w.has_meta("sheet_tween"):
		var old: Tween = w.get_meta("sheet_tween")
		if old != null and old.is_valid():
			old.kill()
	w.popup(Rect2i(Vector2i(rect.position.x, from_y), rect.size))
	var tw := w.create_tween()
	w.set_meta("sheet_tween", tw)
	tw.tween_property(w, "position:y", rect.position.y, SLIDE_IN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Slide the sheet back down to the bottom edge, then hide it.
static func dismiss(w: Window) -> void:
	if not w.visible:
		return
	if w.has_meta("sheet_tween"):
		var old: Tween = w.get_meta("sheet_tween")
		if old != null and old.is_valid():
			old.kill()
	var bottom := int(w.get_parent().get_viewport_rect().size.y)
	var tw := w.create_tween()
	w.set_meta("sheet_tween", tw)
	tw.tween_property(w, "position:y", bottom, SLIDE_OUT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(w.hide)

## A row of buttons: wraps onto more lines on a phone instead of running off the screen.
static func button_bar() -> Container:
	return HFlowContainer.new() if Layout.is_phone() else HBoxContainer.new()

## Breathing room around the sheet's content: space at the edges and between the title, the content
## and the footer, so nothing touches the screen edge.
static func _pad(vb: VBoxContainer) -> void:
	var fs := PhoneTheme.text_px()
	var side := int(round(fs * 0.9))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", side)
	margin.add_theme_constant_override("margin_right", side)
	margin.add_theme_constant_override("margin_top", int(round(fs * 0.7)))
	margin.add_theme_constant_override("margin_bottom", int(round(fs * 0.7)))
	var parent := vb.get_parent()
	var index := vb.get_index()
	parent.remove_child(vb)
	margin.add_child(vb)
	parent.add_child(margin)
	parent.move_child(margin, index)
	if not (parent is Container):
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # the parent is the Window itself (About)
	vb.add_theme_constant_override("separation", int(round(fs * 0.7)))
