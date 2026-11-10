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

## Font used for labels; empty setting means the default UI font.
static func label_font(weight: int = 800) -> Font:
	var n := Settings.get_string("label_font")
	if n == "":
		n = "Avenir"
	var f := SystemFont.new()
	f.font_names = PackedStringArray([n, "Helvetica Neue", "Arial"])
	f.font_weight = weight
	return f

## Heavier face for earthquake magnitudes (Flatland uses Avenir-Black).
static func quake_font() -> Font:
	var v := FontVariation.new()
	v.base_font = label_font(900)
	v.variation_embolden = 0.4
	return v
