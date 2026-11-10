class_name Geo
extends RefCounted
## Geographic helpers shared by the globe and flat views.

const GLOBE_RADIUS := 10.0
const EARTH_KM := 6371.0

## Latitude/longitude (degrees) to a point on a sphere. Longitude 0 faces +Z, east is +X,
## which matches an equirectangular texture whose left edge is -180°.
static func to_vec3(lat: float, lon: float, radius: float = GLOBE_RADIUS) -> Vector3:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	return Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo)) * radius

## Basis whose Z points away from the globe and whose X/Y are east/north.
static func surface_basis(lat: float, lon: float) -> Basis:
	var n := to_vec3(lat, lon, 1.0)
	var east := Vector3.UP.cross(n)
	if east.length() < 0.0001:
		east = Vector3.RIGHT
	east = east.normalized()
	var north := n.cross(east).normalized()
	return Basis(east, north, n)

static func vec3_to_latlon(v: Vector3) -> Vector2:
	var n := v.normalized()
	return Vector2(rad_to_deg(asin(clampf(n.y, -1.0, 1.0))), rad_to_deg(atan2(n.x, n.z)))

static func great_circle_km(a: Vector2, b: Vector2) -> float:
	var la1 := deg_to_rad(a.x)
	var la2 := deg_to_rad(b.x)
	var dlat := la2 - la1
	var dlon := deg_to_rad(b.y - a.y)
	var h := sin(dlat / 2.0) * sin(dlat / 2.0) + cos(la1) * cos(la2) * sin(dlon / 2.0) * sin(dlon / 2.0)
	return 2.0 * EARTH_KM * asin(minf(1.0, sqrt(h)))

static func pretty_coordinates(lat: float, lon: float, precision: int = 3) -> String:
	var ns := "N" if lat >= 0.0 else "S"
	var ew := "E" if lon >= 0.0 else "W"
	return "%s° %s, %s° %s" % [String.num(absf(lat), precision), ns, String.num(absf(lon), precision), ew]

## City colors by continent (user-configurable; Flatland's defaults).
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

## Noto Sans (SIL Open Font License, see Assets/Fonts/NotoSans-OFL.txt) is bundled with the app and is the
## fallback for 3D text wherever the preferred system font is missing. Regular, bold or black by weight.
static func noto(weight: int = 800) -> Font:
	var file := "NotoSans-Regular"
	if weight >= 850:
		file = "NotoSans-Black"
	elif weight >= 600:
		file = "NotoSans-Bold"
	return load("res://Assets/Fonts/" + file + ".ttf") as Font

static var _installed_fonts: PackedStringArray = []

static func _installed(font_name: String) -> bool:
	if _installed_fonts.is_empty():
		_installed_fonts = OS.get_system_fonts()
	return _installed_fonts.has(font_name)

## A system font if one of `names` is installed (with Noto Sans as the glyph fallback); otherwise Noto Sans.
## On iOS Noto Sans is always used: the system fonts there produced broken letters in 3D text.
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

## A 2D (flat text) font: the first installed font in `names`, or Noto Sans if none of them is installed.
## Unlike the 3D text fonts, system fonts are used on iOS too.
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

## Font used for labels; empty setting means the default (Avenir, Helvetica Neue or Arial, else Noto Sans).
static func label_font(weight: int = 800) -> Font:
	var n := Settings.get_string("label_font")
	if n == "":
		n = "Avenir"
	return _system_or_noto(PackedStringArray([n, "Helvetica Neue", "Arial"]), weight)

## Heavy face for the welcome text and earthquake magnitudes. A genuinely heavy face is used because
## synthetic emboldening makes glyph outlines self-intersect, which breaks letters in 3D text meshes.
static func heavy_font() -> Font:
	return _system_or_noto(PackedStringArray(["Arial Black"]), 900)

## Heavier face for earthquake magnitudes (Flatland uses Avenir-Black).
static func quake_font() -> Font:
	return heavy_font()
