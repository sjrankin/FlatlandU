extends Node
## Records the window to a QuickTime movie (autoload-free: main.gd creates one). It grabs the picture about 30 times a
## second, turns each into a JPEG and hands it to the movie file as it goes, so nothing builds up in memory. A frame that
## cannot be finished in time is skipped rather than slowing the app down.

signal recording_changed(recording: bool)
signal finished(path: String, frames: int, seconds: float)
signal failed(reason: String)

const Writer := preload("res://scripts/core/quicktime_writer.gd")
const FPS := 30.0
const JPEG_QUALITY := 0.85
const MAX_EDGE := 1920               # larger windows are scaled down so the movie stays a sensible size

var _writer: RefCounted
var _path := ""
var _size := Vector2i.ZERO
var _started_ms := 0
var _since_frame := 0.0
var _busy := false
var _recording := false

func is_recording() -> bool:
	return _recording

## Starts a movie at `path`. Returns false (and emits `failed`) if the file cannot be made.
func start(path: String) -> bool:
	if _recording:
		return false
	var vp_size := Vector2i(get_viewport().get_visible_rect().size)
	_size = _fit(vp_size)
	_writer = Writer.new()
	var err: int = _writer.open(path, _size.x, _size.y)
	if err != OK:
		_writer = null
		failed.emit("Could not create the file (error %d)." % err)
		return false
	_path = path
	_started_ms = Time.get_ticks_msec()
	_since_frame = 1.0 / FPS            # the first picture is taken at once
	_recording = true
	set_process(true)
	recording_changed.emit(true)
	return true

## Ends the movie and writes its index.
func stop() -> void:
	if not _recording:
		return
	_recording = false
	set_process(false)
	while _busy:                         # let a picture that is being taken finish
		await get_tree().process_frame
	var elapsed := Time.get_ticks_msec() - _started_ms
	var frames: int = _writer.frame_count()
	var ok: bool = _writer.finish(elapsed)
	_writer = null
	recording_changed.emit(false)
	if ok:
		finished.emit(_path, frames, elapsed / 1000.0)
	else:
		failed.emit("Nothing was recorded.")

func _ready() -> void:
	set_process(false)
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if not _recording or _busy:
		return
	_since_frame += delta
	if _since_frame < 1.0 / FPS:
		return
	_since_frame = 0.0
	_grab()

func _grab() -> void:
	_busy = true
	await RenderingServer.frame_post_draw          # the picture is complete only after the frame is drawn
	if _recording:
		var img := get_viewport().get_texture().get_image()
		if img != null and not img.is_empty():
			if img.get_size() != _size:
				img.resize(_size.x, _size.y, Image.INTERPOLATE_BILINEAR)    # the window was resized mid-recording
			img.convert(Image.FORMAT_RGB8)
			var jpeg := img.save_jpg_to_buffer(JPEG_QUALITY)
			_writer.add_frame(jpeg, Time.get_ticks_msec() - _started_ms)
		if not _writer.has_room():
			stop()
	_busy = false

## The movie's size: the window's, scaled down if it is very large, and never odd.
func _fit(s: Vector2i) -> Vector2i:
	var scale := minf(1.0, float(MAX_EDGE) / float(maxi(s.x, s.y)))
	return Vector2i(maxi(2, int(s.x * scale) & ~1), maxi(2, int(s.y * scale) & ~1))
