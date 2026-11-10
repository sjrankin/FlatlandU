class_name Solar
extends RefCounted
## Solar position and sunrise/sunset math (NOAA algorithm), the counterpart of Flatland's
## Astronomy/Solar.swift. All times are Unix seconds (UTC).

static func julian_day(unix: float) -> float:
	return unix / 86400.0 + 2440587.5

static func _centuries(unix: float) -> float:
	return (julian_day(unix) - 2451545.0) / 36525.0

## Offset (seconds) added to the system clock; lets the app and tests view other times.
static var time_offset: float = 0.0
static var time_scale: float = 1.0
static var _scale_anchor: float = 0.0

static func now() -> float:
	var sys := Time.get_unix_time_from_system()
	return sys + time_offset + (sys - _scale_anchor) * (time_scale - 1.0)

## Show an arbitrary moment (and optionally run time faster) - used by the debugger.
static func set_clock(unix: float, scale: float = 1.0) -> void:
	var sys := Time.get_unix_time_from_system()
	_scale_anchor = sys
	time_scale = scale
	time_offset = unix - sys

static func reset_clock() -> void:
	time_offset = 0.0
	time_scale = 1.0
	_scale_anchor = 0.0

## Declination of the sun in degrees.
static func declination(unix: float) -> float:
	var t := _centuries(unix)
	var l0 := fposmod(280.46646 + t * (36000.76983 + t * 0.0003032), 360.0)
	var m := 357.52911 + t * (35999.05029 - 0.0001537 * t)
	var mr := deg_to_rad(m)
	var c := sin(mr) * (1.914602 - t * (0.004817 + 0.000014 * t)) \
		+ sin(2.0 * mr) * (0.019993 - 0.000101 * t) + sin(3.0 * mr) * 0.000289
	var true_long := l0 + c
	var omega := 125.04 - 1934.136 * t
	var app_long := true_long - 0.00569 - 0.00478 * sin(deg_to_rad(omega))
	var eps0 := 23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0
	var eps := eps0 + 0.00256 * cos(deg_to_rad(omega))
	return rad_to_deg(asin(sin(deg_to_rad(eps)) * sin(deg_to_rad(app_long))))

## Right ascension of the sun in degrees (0...360).
static func right_ascension(unix: float) -> float:
	var t := _centuries(unix)
	var l0 := fposmod(280.46646 + t * (36000.76983 + t * 0.0003032), 360.0)
	var m := 357.52911 + t * (35999.05029 - 0.0001537 * t)
	var mr := deg_to_rad(m)
	var c := sin(mr) * (1.914602 - t * (0.004817 + 0.000014 * t)) \
		+ sin(2.0 * mr) * (0.019993 - 0.000101 * t) + sin(3.0 * mr) * 0.000289
	var omega := 125.04 - 1934.136 * t
	var app_long := l0 + c - 0.00569 - 0.00478 * sin(deg_to_rad(omega))
	var eps0 := 23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0
	var eps := eps0 + 0.00256 * cos(deg_to_rad(omega))
	var ra := atan2(cos(deg_to_rad(eps)) * sin(deg_to_rad(app_long)), cos(deg_to_rad(app_long)))
	return fposmod(rad_to_deg(ra), 360.0)

## Equation of time in minutes.
static func equation_of_time(unix: float) -> float:
	var t := _centuries(unix)
	var l0 := fposmod(280.46646 + t * (36000.76983 + t * 0.0003032), 360.0)
	var m := 357.52911 + t * (35999.05029 - 0.0001537 * t)
	var e := 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
	var omega := 125.04 - 1934.136 * t
	var eps0 := 23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0
	var eps := eps0 + 0.00256 * cos(deg_to_rad(omega))
	var y := tan(deg_to_rad(eps) / 2.0)
	y *= y
	var l0r := deg_to_rad(l0)
	var mr := deg_to_rad(m)
	var eot := y * sin(2.0 * l0r) - 2.0 * e * sin(mr) + 4.0 * e * y * sin(mr) * cos(2.0 * l0r) \
		- 0.5 * y * y * sin(4.0 * l0r) - 1.25 * e * e * sin(2.0 * mr)
	return rad_to_deg(eot) * 4.0

## Longitude (degrees, -180...180) of the sub-solar point.
static func subsolar_longitude(unix: float) -> float:
	var utc_minutes := fposmod(unix, 86400.0) / 60.0
	var lon := -(utc_minutes + equation_of_time(unix) - 720.0) / 4.0
	return wrapf(lon, -180.0, 180.0)

## Fraction of the UTC day elapsed (0...1).
static func day_fraction(unix: float) -> float:
	return fposmod(unix, 86400.0) / 86400.0

## Sunrise/sunset for a place on the date containing `unix`.
## Returns {"status": "ok"|"polar_day"|"polar_night", "sunrise": unix, "sunset": unix, "noon": unix}.
static func sunrise_sunset(lat: float, lon: float, unix: float) -> Dictionary:
	var day_start := floorf(unix / 86400.0) * 86400.0
	var noon_guess := day_start + 43200.0 - lon * 240.0
	var decl := deg_to_rad(declination(noon_guess))
	var eot := equation_of_time(noon_guess)
	var latr := deg_to_rad(lat)
	var cos_h := (cos(deg_to_rad(90.833)) / (cos(latr) * cos(decl))) - tan(latr) * tan(decl)
	var solar_noon := day_start + (720.0 - 4.0 * lon - eot) * 60.0
	if cos_h > 1.0:
		return {"status": "polar_night", "noon": solar_noon}
	if cos_h < -1.0:
		return {"status": "polar_day", "noon": solar_noon}
	var ha := rad_to_deg(acos(cos_h))
	return {"status": "ok", "noon": solar_noon,
		"sunrise": solar_noon - ha * 240.0, "sunset": solar_noon + ha * 240.0}

static func is_daylight(lat: float, lon: float, unix: float) -> bool:
	var decl := deg_to_rad(declination(unix))
	var ha := deg_to_rad(lon - subsolar_longitude(unix))
	var latr := deg_to_rad(lat)
	var alt := asin(sin(latr) * sin(decl) + cos(latr) * cos(decl) * cos(ha))
	return alt > deg_to_rad(-0.833)
