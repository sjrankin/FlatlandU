extends RefCounted
## A value that wanders at random between two limits, changing slowly and smoothly: it eases from one random
## target to the next over `period` seconds (a different length each time), starting and ending each leg at rest, so
## it never jerks. Used by the camera flight for the yaw and pitch offsets, the turning, the speed and the altitude.

var _from: float
var _to: float
var _elapsed := 0.0
var _duration := 30.0
var _low: float
var _high: float
var _min_period: float
var _max_period: float
var _rng: RandomNumberGenerator

func _init(rng: RandomNumberGenerator, low: float, high: float, min_period: float, max_period: float, start: float) -> void:
	_rng = rng
	_low = low
	_high = high
	_min_period = min_period
	_max_period = max_period
	_from = start
	_to = _rng.randf_range(low, high)
	_duration = _rng.randf_range(min_period, max_period)

## Moves on by `delta` seconds and returns the current value.
func step(delta: float) -> float:
	_elapsed += delta
	while _elapsed >= _duration:
		_elapsed -= _duration
		_from = _to
		_to = _rng.randf_range(_low, _high)
		_duration = _rng.randf_range(_min_period, _max_period)
	var t := _elapsed / _duration
	var eased := t * t * t * (t * (t * 6.0 - 15.0) + 10.0)      # smootherstep: zero speed and acceleration at both ends
	return lerpf(_from, _to, eased)
