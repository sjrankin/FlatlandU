extends RefCounted
## Writes a QuickTime movie (.mov) of JPEG pictures (Motion-JPEG, the "Photo JPEG" codec). QuickTime Player, Finder, iMovie,
## VLC and ffmpeg all open these. The pictures are written as they arrive, and the index that describes them (the "moov"
## atom) is added when the movie is finished. Each frame carries its own time, so a slow moment is not played back fast.
##
## Usage: open(path, width, height), add_frame(jpeg_bytes, time_ms) for each picture, then finish().

const MAX_BYTES := 3_800_000_000      # the file's offsets are 32 bits; stop before they run out
const TIMESCALE := 1000               # time units a second (milliseconds)

var _file: FileAccess
var _width := 0
var _height := 0
var _sizes := PackedInt32Array()
var _offsets := PackedInt32Array()
var _times := PackedInt64Array()       # when each frame is shown, in milliseconds from the first
var _mdat_start := 20

## Returns OK, or the error that stopped the file being created.
func open(path: String, width: int, height: int) -> int:
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		return FileAccess.get_open_error()
	_file.big_endian = true
	_width = width
	_height = height
	_atom_header(20, "ftyp")
	_file.store_buffer("qt  ".to_ascii_buffer())
	_file.store_32(0)
	_file.store_buffer("qt  ".to_ascii_buffer())
	_atom_header(8, "mdat")            # the size is filled in when the movie is finished
	return OK

func frame_count() -> int:
	return _sizes.size()

## False once the file is as big as it may get.
func has_room() -> bool:
	return _file != null and _file.get_position() < MAX_BYTES

func add_frame(jpeg: PackedByteArray, time_ms: int) -> void:
	if _file == null:
		return
	_offsets.append(_file.get_position())
	_sizes.append(jpeg.size())
	_times.append(time_ms)
	_file.store_buffer(jpeg)

## Writes the index and closes the file. Returns true if the movie has at least one frame.
func finish(end_time_ms: int) -> bool:
	if _file == null:
		return false
	var ok := _sizes.size() > 0
	var data_end := _file.get_position()
	_file.seek(_mdat_start)
	_file.store_32(data_end - _mdat_start)
	_file.seek(data_end)
	if ok:
		_file.store_buffer(_moov(end_time_ms))
	_file.close()
	_file = null
	return ok

# MARK: - Atoms

func _atom_header(size: int, kind: String) -> void:
	_file.store_32(size)
	_file.store_buffer(kind.to_ascii_buffer())

## An atom as bytes: size, name, then the pieces.
func _atom(kind: String, body: PackedByteArray) -> PackedByteArray:
	var out := _be(body.size() + 8, 4)
	out.append_array(kind.to_ascii_buffer())
	out.append_array(body)
	return out

func _be(value: int, bytes: int) -> PackedByteArray:
	var out := PackedByteArray()
	for i in range(bytes - 1, -1, -1):
		out.append((value >> (8 * i)) & 0xFF)
	return out

func _zeros(n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n)
	return out

func _join(parts: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for p in parts:
		out.append_array(p)
	return out

func _matrix() -> PackedByteArray:
	return _join([_be(0x00010000, 4), _zeros(12), _be(0x00010000, 4), _zeros(12), _be(0x40000000, 4)])    # nine 32-bit values

func _moov(end_time_ms: int) -> PackedByteArray:
	var n := _sizes.size()
	var duration := maxi(1, end_time_ms)
	# How long each frame is shown: until the next one (the last one for as long as the one before it).
	var durations := PackedInt64Array()
	for i in range(n):
		if i + 1 < n:
			durations.append(maxi(1, _times[i + 1] - _times[i]))
		else:
			durations.append(maxi(1, durations[i - 1] if i > 0 else 33))
	var total := 0
	for d in durations:
		total += d
	duration = total
	var now := int(Time.get_unix_time_from_system()) + 2082844800      # QuickTime counts from 1904
	var mvhd := _atom("mvhd", _join([_be(0, 4), _be(now, 4), _be(now, 4), _be(TIMESCALE, 4), _be(duration, 4),
		_be(0x00010000, 4), _be(0x0100, 2), _zeros(10), _matrix(), _zeros(24), _be(2, 4)]))
	var tkhd := _atom("tkhd", _join([_be(7, 4), _be(now, 4), _be(now, 4), _be(1, 4), _zeros(4), _be(duration, 4), _zeros(8),
		_be(0, 2), _be(0, 2), _be(0, 2), _zeros(2), _matrix(), _be(_width << 16, 4), _be(_height << 16, 4)]))
	var mdhd := _atom("mdhd", _join([_be(0, 4), _be(now, 4), _be(now, 4), _be(TIMESCALE, 4), _be(duration, 4), _be(0x55C4, 2), _be(0, 2)]))
	var name := "VideoHandler".to_ascii_buffer()
	var hdlr := _atom("hdlr", _join([_be(0, 4), "mhlr".to_ascii_buffer(), "vide".to_ascii_buffer(), _zeros(4), _zeros(4), _zeros(4),
		_be(name.size(), 1), name]))
	var vmhd := _atom("vmhd", _join([_be(1, 4), _be(0, 2), _zeros(6)]))
	var dref := _atom("dref", _join([_be(0, 4), _be(1, 4), _atom("url ", _be(1, 4))]))
	var dinf := _atom("dinf", dref)
	var compressor := _zeros(32)
	var cname := "Photo - JPEG".to_ascii_buffer()
	compressor[0] = cname.size()
	for i in range(cname.size()):
		compressor[i + 1] = cname[i]
	var entry := _atom("jpeg", _join([_zeros(6), _be(1, 2), _be(0, 2), _be(0, 2), _zeros(4), _be(512, 4), _be(512, 4),
		_be(_width, 2), _be(_height, 2), _be(0x00480000, 4), _be(0x00480000, 4), _zeros(4), _be(1, 2), compressor, _be(24, 2), _be(0xFFFF, 2)]))
	var stsd := _atom("stsd", _join([_be(0, 4), _be(1, 4), entry]))
	# Runs of frames that are shown for the same time share one entry.
	var runs := PackedInt64Array()
	for d in durations:
		if runs.size() >= 2 and runs[runs.size() - 1] == d:
			runs[runs.size() - 2] += 1
		else:
			runs.append(1)
			runs.append(d)
	var stts_body := _join([_be(0, 4), _be(runs.size() / 2, 4)])
	for i in range(0, runs.size(), 2):
		stts_body.append_array(_be(runs[i], 4))
		stts_body.append_array(_be(runs[i + 1], 4))
	var stts := _atom("stts", stts_body)
	var stsc := _atom("stsc", _join([_be(0, 4), _be(1, 4), _be(1, 4), _be(1, 4), _be(1, 4)]))
	var stsz_body := _join([_be(0, 4), _be(0, 4), _be(n, 4)])
	var stco_body := _join([_be(0, 4), _be(n, 4)])
	for i in range(n):
		stsz_body.append_array(_be(_sizes[i], 4))
		stco_body.append_array(_be(_offsets[i], 4))
	var stbl := _atom("stbl", _join([stsd, stts, stsc, _atom("stsz", stsz_body), _atom("stco", stco_body)]))
	var minf := _atom("minf", _join([vmhd, dinf, stbl]))
	var mdia := _atom("mdia", _join([mdhd, hdlr, minf]))
	var trak := _atom("trak", _join([tkhd, mdia]))
	return _atom("moov", _join([mvhd, trak]))
