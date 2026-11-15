class_name Solar
extends RefCounted
## Solar position and sunrise/sunset math (NOAA algorithm), the counterpart of Flatland's
## Astronomy/Solar.swift. All times are Unix seconds (UTC).

## Converts a Unix time to a Julian day number (days since noon, 1 January 4713 BC), the time scale the astronomy
## formulas use.
##
## [param unix]: Unix time in seconds (UTC).
## Returns: the Julian day, with a fraction for the time of day.
## Used by [method _centuries] and by [method Lunar.position].
static func julian_day(unix: float) -> float:
	return unix / 86400.0 + 2440587.5

## Converts a Unix time to Julian centuries since the J2000.0 epoch (noon, 1 January 2000), the "T" of the NOAA
## formulas.
##
## [param unix]: Unix time in seconds (UTC).
## Returns: centuries since J2000.0 (negative before 2000).
static func _centuries(unix: float) -> float:
	return (julian_day(unix) - 2451545.0) / 36525.0

## Seconds added to the system clock by [method now]. Set by [method set_clock] (the debugger and the `--time=`
## development flag) to show another moment; 0 means real time.
static var time_offset: float = 0.0
## How fast the clock runs relative to real time (1.0 = real time, 60.0 = a minute passes every second). Set by
## [method set_clock].
static var time_scale: float = 1.0
## The real (system) time at which the current [member time_scale] and [member time_offset] were set. Time after this
## moment is stretched by the scale; see [method now].
static var _scale_anchor: float = 0.0

## The app's current time. Everything that draws the Sun, Moon, day/night boundary or clocks uses this rather than the
## system clock, so the debugger can show other moments or speed time up.
##
## Returns: Unix time in seconds (UTC), the system time plus [member time_offset] and any speed-up from [member   time_scale].
## See also [method set_clock] and [method reset_clock].
static func now() -> float:
	var sys := Time.get_unix_time_from_system()
	return sys + time_offset + (sys - _scale_anchor) * (time_scale - 1.0)

## Shows an arbitrary moment, optionally running time faster than normal. Used by the debugger dialog and the
## `--time=` development flag.
##
## [param unix]: the Unix time (UTC) that should be "now" from this instant.
## [param scale]: how fast time runs from then on (1.0 = real time).
## See also [method reset_clock].
static func set_clock(unix: float, scale: float = 1.0) -> void:
	var sys := Time.get_unix_time_from_system()
	_scale_anchor = sys
	time_scale = scale
	time_offset = unix - sys

## Puts the clock back to real time: no offset and no speed-up. Used by the debugger's reset button. See [method set_clock].
static func reset_clock() -> void:
	time_offset = 0.0
	time_scale = 1.0
	_scale_anchor = 0.0

## The Sun's declination: the latitude of the sub-solar point, which gives the seasons (about +23.4 degrees at the
## June solstice, -23.4 at the December one). NOAA low-precision algorithm.
##
## [param unix]: Unix time in seconds (UTC).
## Returns: declination in degrees, -23.5 to +23.5.
## Used to tilt the Earth in the 3D views and by [method is_daylight] and [method sunrise_sunset].
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

## The Sun's right ascension: its position along the celestial equator. The star field and the Moon use it to turn the
## sky to match the date (see GlobeView `_update_time` and [method Lunar.position]).
##
## [param unix]: Unix time in seconds (UTC).
## Returns: right ascension in degrees, 0 up to 360.
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

## The equation of time: how far the real (apparent) Sun runs ahead of or behind a perfectly regular clock Sun, up to
## about +-16 minutes through the year.
##
## [param unix]: Unix time in seconds (UTC).
## Returns: the difference in minutes (positive when the Sun is ahead).
## Used by [method subsolar_longitude] and [method sunrise_sunset].
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

## The longitude of the sub-solar point, where the Sun is straight overhead. It moves west 15 degrees an hour; the 3D
## views use it to turn the Earth.
##
## [param unix]: Unix time in seconds (UTC).
## Returns: longitude in degrees, -180 to 180 (east positive).
static func subsolar_longitude(unix: float) -> float:
	var utc_minutes := fposmod(unix, 86400.0) / 60.0
	var lon := -(utc_minutes + equation_of_time(unix) - 720.0) / 4.0
	return wrapf(lon, -180.0, 180.0)

## How far through the UTC day a moment is.
##
## [param unix]: Unix time in seconds (UTC).
## Returns: 0.0 at UTC midnight up to just under 1.0 (0.5 is UTC noon).
static func day_fraction(unix: float) -> float:
	return fposmod(unix, 86400.0) / 86400.0

## Sunrise, solar noon and sunset at a place on the UTC date that contains [param unix].
##
## [param lat]: latitude in degrees (north positive).
## [param lon]: longitude in degrees (east positive).
## [param unix]: any Unix time (UTC) on the wanted date.
## Returns: a Dictionary: {"status": "ok" | "polar_day" | "polar_night", "noon": unix}, and for "ok" also "sunrise":
##   unix and "sunset": unix. In "polar_day" the Sun does not set; in "polar_night" it does not rise.
## Shown by the Today's Times dialog and the What's Here popup in `main.gd`.
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

## Whether the Sun is above the horizon at a place (allowing for the Sun's size and refraction, -0.833 degrees).
##
## [param lat]: latitude in degrees.
## [param lon]: longitude in degrees.
## [param unix]: Unix time in seconds (UTC).
## Returns: true in daylight, false at night. Used to choose the day or night look of cities and labels.
static func is_daylight(lat: float, lon: float, unix: float) -> bool:
	var decl := deg_to_rad(declination(unix))
	var ha := deg_to_rad(lon - subsolar_longitude(unix))
	var latr := deg_to_rad(lat)
	var alt := asin(sin(latr) * sin(decl) + cos(latr) * cos(decl) * cos(ha))
	return alt > deg_to_rad(-0.833)
