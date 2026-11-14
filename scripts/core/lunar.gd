class_name Lunar
extends RefCounted
## The Moon's position, from the low-precision series of the Astronomical Almanac (good to about a third of a degree
## and a few hundred kilometers, plenty for drawing it). All times are Unix seconds (UTC).

const RADIUS_KM := 1737.4
const MEAN_DISTANCE_KM := 384400.0
## Moon's diameter as a fraction of the Earth's (3474.8 / 12742).
const SIZE_RATIO := 0.2727

## Where the Moon is at `unix`. Returns
##   {"ra": degrees (0...360), "dec": degrees, "distance_km": from the Earth's center,
##    "lat": sub-lunar latitude, "lon": sub-lunar longitude (-180...180)}.
## The sub-lunar point is where the Moon is straight overhead.
static func position(unix: float) -> Dictionary:
	var t := (Solar.julian_day(unix) - 2451545.0) / 36525.0
	var lon_ecl := 218.32 + 481267.881 * t \
		+ 6.29 * _sin_deg(135.0 + 477198.87 * t) - 1.27 * _sin_deg(259.3 - 413335.36 * t) \
		+ 0.66 * _sin_deg(235.7 + 890534.22 * t) + 0.21 * _sin_deg(269.9 + 954397.74 * t) \
		- 0.19 * _sin_deg(357.5 + 35999.05 * t) - 0.11 * _sin_deg(186.5 + 966404.03 * t)
	var lat_ecl := 5.13 * _sin_deg(93.3 + 483202.02 * t) + 0.28 * _sin_deg(228.2 + 960400.89 * t) \
		- 0.28 * _sin_deg(318.3 + 6003.15 * t) - 0.17 * _sin_deg(217.6 - 407332.21 * t)
	var parallax := 0.9508 + 0.0518 * _cos_deg(135.0 + 477198.87 * t) + 0.0095 * _cos_deg(259.3 - 413335.36 * t) \
		+ 0.0078 * _cos_deg(235.7 + 890534.22 * t) + 0.0028 * _cos_deg(269.9 + 954397.74 * t)
	var distance := 6378.14 / sin(deg_to_rad(parallax))
	# Ecliptic to equatorial direction cosines (obliquity 23.44 degrees: cos 0.9175, sin 0.3978).
	var cb := _cos_deg(lat_ecl)
	var l := cb * _cos_deg(lon_ecl)
	var m := 0.9175 * cb * _sin_deg(lon_ecl) - 0.3978 * _sin_deg(lat_ecl)
	var n := 0.3978 * cb * _sin_deg(lon_ecl) + 0.9175 * _sin_deg(lat_ecl)
	var ra := fposmod(rad_to_deg(atan2(m, l)), 360.0)
	var dec := rad_to_deg(asin(clampf(n, -1.0, 1.0)))
	# A body's longitude is its right ascension less the Greenwich sidereal time; the sub-solar point gives
	# the same for the Sun, so the Moon is east of it by the difference in right ascension.
	var lon := wrapf(Solar.subsolar_longitude(unix) + ra - Solar.right_ascension(unix), -180.0, 180.0)
	return {"ra": ra, "dec": dec, "distance_km": distance, "lat": dec, "lon": lon}

## The direction to the Moon in the same equatorial frame the star field uses (see GlobeView).
static func equatorial_direction(pos: Dictionary) -> Vector3:
	var ra := deg_to_rad(float(pos["ra"]))
	var dec := deg_to_rad(float(pos["dec"]))
	return Vector3(cos(dec) * sin(ra), sin(dec), cos(dec) * cos(ra))

## The Moon's north pole, taken as the ecliptic pole (its axis is only 1.5 degrees off), in the same frame.
static func pole_direction() -> Vector3:
	return Vector3(-0.3978, 0.9175, 0.0)

static func _sin_deg(d: float) -> float:
	return sin(deg_to_rad(d))

static func _cos_deg(d: float) -> float:
	return cos(deg_to_rad(d))
