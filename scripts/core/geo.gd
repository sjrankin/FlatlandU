class_name Geo
extends RefCounted
## Geographic helpers shared by the globe and flat views.

## Radius of the 3D globe in scene units. Everything on or around the globe is sized from this (the hour labels are at
## 1.15 times it).
const GLOBE_RADIUS := 10.0
## The Earth's mean radius in kilometers; scales real distances (satellite altitudes, the Moon) to scene units and is
## used in [method great_circle_km].
const EARTH_KM := 6371.0

## Converts a latitude and longitude to a point on a sphere centered on the origin. Longitude 0 faces +Z and east is
## +X, which matches an equirectangular texture whose left edge is -180 degrees.
##
## [param lat]: latitude in degrees (north positive).
## [param lon]: longitude in degrees (east positive).
## [param radius]: the sphere's radius (default [constant GLOBE_RADIUS]).
## Returns: the position as a Vector3. The reverse is [method vec3_to_latlon].
static func to_vec3(lat: float, lon: float, radius: float = GLOBE_RADIUS) -> Vector3:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	return Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo)) * radius

## A coordinate frame sitting on the globe's surface at a place, for standing things upright there: X points east, Y
## north and Z away from the globe.
##
## [param lat]: latitude in degrees.
## [param lon]: longitude in degrees.
## Returns: the Basis. At the poles, where "east" is undefined, X is world right.
static func surface_basis(lat: float, lon: float) -> Basis:
	var n := to_vec3(lat, lon, 1.0)
	var east := Vector3.UP.cross(n)
	if east.length() < 0.0001:
		east = Vector3.RIGHT
	east = east.normalized()
	var north := n.cross(east).normalized()
	return Basis(east, north, n)

## Converts a point or direction (from the globe's center) back to a latitude and longitude. The reverse of [method to_vec3].
##
## [param v]: any non-zero vector; its length does not matter.
## Returns: a Vector2 with x = latitude and y = longitude, in degrees.
static func vec3_to_latlon(v: Vector3) -> Vector2:
	var n := v.normalized()
	return Vector2(rad_to_deg(asin(clampf(n.y, -1.0, 1.0))), rad_to_deg(atan2(n.x, n.z)))

## The shortest distance over the Earth's surface between two places (haversine formula).
##
## [param a]: first place as Vector2(latitude, longitude) in degrees.
## [param b]: second place, same form.
## Returns: the distance in kilometers.
static func great_circle_km(a: Vector2, b: Vector2) -> float:
	var la1 := deg_to_rad(a.x)
	var la2 := deg_to_rad(b.x)
	var dlat := la2 - la1
	var dlon := deg_to_rad(b.y - a.y)
	var h := sin(dlat / 2.0) * sin(dlat / 2.0) + cos(la1) * cos(la2) * sin(dlon / 2.0) * sin(dlon / 2.0)
	return 2.0 * EARTH_KM * asin(minf(1.0, sqrt(h)))

## Formats a place for display, like "35.123° N, 100.456° W".
##
## [param lat]: latitude in degrees.
## [param lon]: longitude in degrees.
## [param precision]: digits after the decimal point (default 3).
## Returns: the text.
static func pretty_coordinates(lat: float, lon: float, precision: int = 3) -> String:
	var ns := "N" if lat >= 0.0 else "S"
	var ew := "E" if lon >= 0.0 else "W"
	return "%s° %s, %s° %s" % [String.num(absf(lat), precision), ns, String.num(absf(lon), precision), ew]

## The color to draw a city in: the capital color for capitals, otherwise the color for its continent (all
## user-settable in Preferences).
##
## [param city]: a city record from [CityDB] (reads "IsCapital" and "Continent").
## Returns: the Color; white for a continent without a setting.
static func city_color(city: Dictionary) -> Color:
	if int(city.get("IsCapital", 0)) == 1:
		return Settings.get_color("color_city_capital")
	match str(city.get("Continent", "")):
		"Africa": return Settings.get_color("color_city_africa")
		"Asia": return Settings.get_color("color_city_asia")
		"Europe": return Settings.get_color("color_city_europe")
		"NorthAmerica": return Settings.get_color("color_city_north_america")
		"SouthAmerica": return Settings.get_color("color_city_south_america")
	return Color.WHITE

## The Noto Sans font bundled with the app, in the face closest to a weight. Noto Sans is licensed under the SIL Open
## Font License (see Assets/Fonts/NotoSans-OFL.txt). It is the fallback wherever a system font is missing.
##
## [param weight]: a CSS-style weight (400 regular, 700 bold, 900 black); 850 and above gives Black, 600 and above
##   Bold.
## Returns: the loaded Font.
static func noto(weight: int = 800) -> Font:
	var file := "NotoSans-Regular"
	if weight >= 850:
		file = "NotoSans-Black"
	elif weight >= 600:
		file = "NotoSans-Bold"
	return load("res://Assets/Fonts/" + file + ".ttf") as Font

## Cache of the system's installed font names, filled on first use by [method _installed] (listing them is slow).
static var _installed_fonts: PackedStringArray = []

## Whether a font is installed on this system. The list of installed fonts is fetched once and cached in [member _installed_fonts].
##
## [param font_name]: the font family name to look for (exact match).
## Returns: true if installed.
static func _installed(font_name: String) -> bool:
	if _installed_fonts.is_empty():
		_installed_fonts = OS.get_system_fonts()
	return _installed_fonts.has(font_name)

## Chooses a font for 3D text: the first installed system font from a list, with Noto Sans as the fallback for missing
## glyphs, or Noto Sans alone. On iOS only Noto Sans is used, because the system fonts there produced broken letters
## in 3D text.
##
## [param names]: font family names in order of preference.
## [param weight]: the CSS-style weight wanted.
## Returns: the Font. Used by [method label_font] and [method heavy_font].
static func _system_or_noto(names: PackedStringArray, weight: int) -> Font:
	if OS.get_name() != "iOS":
		for n in names:
			if _installed(n):
				var f := SystemFont.new()
				f.font_names = PackedStringArray([n])
				f.font_weight = weight
				f.fallbacks = [noto(weight)]
				return f
	return noto(weight)

## A font for ordinary 2D text: the first installed font from a list (compared ignoring case), or Noto Sans. Unlike
## the 3D fonts, system fonts are used on iOS too.
##
## [param names]: font family names in order of preference.
## [param weight]: the CSS-style weight wanted.
## Returns: the Font.
static func ui_font(names: PackedStringArray, weight: int) -> Font:
	var wanted: Array = []
	for n in names:
		wanted.append(n.to_lower())
	for installed in OS.get_system_fonts():
		if wanted.has(installed.to_lower()):
			var f := SystemFont.new()
			f.font_names = names
			f.font_weight = weight
			return f
	return noto(weight)

## The font for labels on the globe and maps. The "label_font" setting names it; empty means Avenir (then Helvetica
## Neue, Arial, then Noto Sans).
##
## [param weight]: the CSS-style weight wanted (default 800).
## Returns: the Font. See [method _system_or_noto].
static func label_font(weight: int = 800) -> Font:
	var n := Settings.get_string("label_font")
	if n == "":
		n = "Avenir"
	return _system_or_noto(PackedStringArray([n, "Helvetica Neue", "Arial"]), weight)

## A heavy face (Arial Black, else Noto Sans Black) for the welcome text and earthquake magnitudes. A genuinely heavy
## face is needed, because making a font bold artificially makes glyph outlines cross themselves and breaks the
## letters in 3D text.
##
## Returns: the Font.
static func heavy_font() -> Font:
	return _system_or_noto(PackedStringArray(["Arial Black"]), 900)

## The font for earthquake magnitude labels (Flatland uses Avenir Black); currently the same as [method heavy_font].
##
## Returns: the Font.
static func quake_font() -> Font:
	return heavy_font()
