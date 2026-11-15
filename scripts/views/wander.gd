extends RefCounted
## A value that wanders at random between two limits, changing slowly and smoothly: it eases from one random
## target to the next over `period` seconds (a different length each time), starting and ending each leg at rest, so
## it never jerks. Used by the camera flight for the yaw and pitch offsets, the turning, the speed and the altitude.

## The value at the start of the current leg.
var _from: float
## The random target the current leg is heading for.
var _to: float
## Seconds into the current leg.
var _elapsed := 0.0
## Length of the current leg in seconds (random between the two periods).
var _duration := 30.0
## Smallest value a target may take.
var _low: float
## Largest value a target may take.
var _high: float
## Shortest leg, in seconds.
var _min_period: float
## Longest leg, in seconds.
var _max_period: float
## The random number generator used to pick targets and leg lengths (shared with the flight).
var _rng: RandomNumberGenerator

## Creates the wandering value and picks its first target.
##
## [param rng]: the random number generator to use.
## [param low]: smallest value a target may take.
## [param high]: largest value a target may take.
## [param min_period]: shortest time, in seconds, to move to a new target.
## [param max_period]: longest time to move to a new target.
## [param start]: the starting value (it moves to the first target from here).
func _init(rng: RandomNumberGenerator, low: float, high: float, min_period: float, max_period: float, start: float) -> void:
	_rng = rng
	_low = low
	_high = high
	_min_period = min_period
	_max_period = max_period
	_from = start
	_to = _rng.randf_range(low, high)
	_duration = _rng.randf_range(min_period, max_period)

## Moves on in time and returns the current value. At the end of a leg a new target and a new length are chosen. The
## value eases with a "smootherstep" curve, so it starts and ends each leg with no speed or acceleration, and never
## jerks.
##
## [param delta]: seconds since the last call.
## Returns: the current value.
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
