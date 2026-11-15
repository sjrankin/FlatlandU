extends Node
## Records the window to a QuickTime movie (autoload-free: main.gd creates one). It grabs the picture about 30 times a
## second, turns each into a JPEG and hands it to the movie file as it goes, so nothing builds up in memory. A frame that
## cannot be finished in time is skipped rather than slowing the app down.

## Emitted when recording starts or stops, so the Record button can change its look (see `_update_video_button` in
## main.gd).
##
## [param recording]: true when a recording began, false when it ended.
signal recording_changed(recording: bool)
## Emitted after a movie was written successfully.
##
## [param path]: the movie's file path.
## [param frames]: how many frames it holds.
## [param seconds]: its length in seconds.
signal finished(path: String, frames: int, seconds: float)
## Emitted when the movie could not be made (file error, or nothing recorded).
##
## [param reason]: a short description to show the user.
signal failed(reason: String)

## The QuickTime file writer class (see quicktime_writer.gd), loaded by path.
const Writer := preload("res://scripts/core/quicktime_writer.gd")
## How many pictures a second are recorded.
const FPS := 30.0
## JPEG quality of each frame (0 to 1); higher means bigger files.
const JPEG_QUALITY := 0.85
## Windows larger than this on the long edge (in pixels) are scaled down so the movie stays a sensible size; see
## [method _fit].
const MAX_EDGE := 1920

## The QuickTime writer for the current recording; null when not recording.
var _writer: RefCounted
## The file being written, reported by [signal finished].
var _path := ""
## The movie's frame size in pixels, fixed when recording starts (later frames are resized to it).
var _size := Vector2i.ZERO
## `Time.get_ticks_msec()` when recording began; frame times are measured from it.
var _started_ms := 0
## Seconds since the last picture was taken; a new one is taken when it reaches 1 / [constant FPS].
var _since_frame := 0.0
## True while a picture is being taken and encoded, so frames that cannot be finished in time are skipped rather than
## queued.
var _busy := false
## True between [method start] and [method stop].
var _recording := false

## Whether a recording is in progress.
##
## Returns: true while recording.
func is_recording() -> bool:
	return _recording

## Starts a movie. The movie's size is the window's, scaled down if very large ([method _fit]).
##
## [param path]: the .mov file to create.
## Returns: false (and emits [signal failed]) if already recording or the file cannot be created; true otherwise, with
##   [signal recording_changed] emitted.
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

## Ends the recording: waits for a picture in progress, writes the movie's index, and emits [signal recording_changed]
## and then [signal finished] (or [signal failed] if no frame was recorded). It is a coroutine, so `await` it to be
## sure the file is complete.
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

## Keeps the recorder running even while the tree is paused, and starts with per-frame processing off (it is only
## needed while recording).
func _ready() -> void:
	set_process(false)
	process_mode = Node.PROCESS_MODE_ALWAYS

## Counts time and, once a frame interval has passed and no picture is already being taken, takes the next one with
## [method _grab].
##
## [param delta]: seconds since the last frame.
func _process(delta: float) -> void:
	if not _recording or _busy:
		return
	_since_frame += delta
	if _since_frame < 1.0 / FPS:
		return
	_since_frame = 0.0
	_grab()

## Takes one picture: waits until the frame has been drawn, copies the window's image, resizes it if the window
## changed size, converts it to JPEG and adds it to the movie. Stops the recording if the file is full
## ([method QuickTimeWriter.has_room]). A coroutine; [member _busy] is set meanwhile.
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

## The movie size for a window size: scaled down if the long edge is over [constant MAX_EDGE], and each side made even
## (video needs that).
##
## [param s]: the window size in pixels.
## Returns: the movie size in pixels (at least 2 by 2).
func _fit(s: Vector2i) -> Vector2i:
	var scale := minf(1.0, float(MAX_EDGE) / float(maxi(s.x, s.y)))
	return Vector2i(maxi(2, int(s.x * scale) & ~1), maxi(2, int(s.y * scale) & ~1))
