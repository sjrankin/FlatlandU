shader_type canvas_item;
// Weather-satellite compositor: merges the full-disk pictures of GOES-West, GOES-East, Meteosat (MTG) and Himawari (each already
// laid out as a whole-world equirectangular image, black outside the satellite's view) into one whole-world picture.
// Drawn once into a 4096 by 2048 SubViewport by weather_composer.gd; the result is read back as an Image.
//
// Method: each satellite gets a weight per pixel that is 1 well inside its footprint and fades to 0 at its edge, where
// the view is stretched and noisy. Where footprints overlap the pictures are averaged by those weights, so there is no
// seam. Where no satellite sees (the poles, and a few small gaps between disks), the result is the base picture (blend
// mode) or black (weather-only mode).

// The four satellite pictures, each whole-world equirectangular. Linear filtering; no mipmaps (drawn 1:1).
uniform sampler2D goes_west : filter_linear, repeat_disable;
uniform sampler2D goes_east : filter_linear, repeat_disable;
uniform sampler2D mtg : filter_linear, repeat_disable;
uniform sampler2D himawari : filter_linear, repeat_disable;
// Himawari's infrared picture (colour-coded by cloud-top temperature), used on its night side where the visible picture
// is black.
uniform sampler2D himawari_ir : filter_linear, repeat_disable;
// The base picture (the NOAA-21 map) used behind the weather pictures in blend mode.
uniform sampler2D base_map : filter_linear, repeat_disable;
// Which of the pictures are present. A missing picture is simply skipped (its area becomes base or black).
uniform bool have_west = false;
uniform bool have_east = false;
uniform bool have_mtg = false;
uniform bool have_himawari = false;
uniform bool have_himawari_ir = false;
uniform bool have_base = false;
// true: fade into the base picture; false: show only the weather pictures, black where there are none.
uniform bool blend_with_base = true;

// Longitude (degrees) of the point each satellite hangs over.
const float LON_WEST = -137.0;      // GOES-West
const float LON_EAST = -75.2;       // GOES-East
const float LON_MTG = 0.0;          // Meteosat Third Generation (MTG-I1)
const float LON_HIMAWARI = 140.7;   // Himawari
// Half-size of a satellite's rounded-square footprint, in degrees from its sub-point (the usable part of the disk),
// measured from the downloaded pictures: GOES shows about 76 degrees, MTG and Himawari about 80.
const float RADIUS_GOES = 76.0;
const float RADIUS_MTG = 80.0;
const float RADIUS_HIMAWARI = 80.0;
// The weight is 1 up to this fraction of the radius and fades to 0 at EDGE_END (the limb is stretched and noisy).
const float EDGE_START = 0.80;
const float EDGE_END = 0.95;
// Himawari's visible picture is black on its night side. Pixels this dark count as night: the weight of the visible
// picture ramps from 0 at NIGHT_LOW to 1 at NIGHT_HIGH (brightest channel, 0..1), and the infrared picture fills in the
// rest (or, without it, the night side is "no data").
const float NIGHT_LOW = 0.02;
const float NIGHT_HIGH = 0.08;
// The look of the infrared night view, imitating the GeoColor night side of the other satellites: clouds in pale blue
// white over a dark blue-black background.
const vec3 NIGHT_BACKGROUND = vec3(0.02, 0.03, 0.07);
const vec3 NIGHT_CLOUD = vec3(0.85, 0.9, 1.0);
// Cloudiness (0..1, brightness plus 2 x colour saturation) below CLOUD_LOW is ground or sea, above CLOUD_HIGH is cloud.
const float CLOUD_LOW = 0.55;
const float CLOUD_HIGH = 0.95;

// Weight of one satellite at a place: 1 inside the footprint, fading to 0 across its edge.
//
// lon, lat: the place in degrees.
// lon0: the satellite's sub-point longitude.
// radius: the half-size of its footprint in degrees.
// Returns: the weight, 0 to 1. The footprint is a rounded square (a superellipse of exponent 5) like the pictures.
float footprint(float lon, float lat, float lon0, float radius) {
	float dlon = abs(mod(lon - lon0 + 540.0, 360.0) - 180.0);
	float s = pow(pow(dlon / radius, 5.0) + pow(abs(lat) / radius, 5.0), 0.2);
	return 1.0 - smoothstep(EDGE_START, EDGE_END, s);
}

// Turns a pixel of the colour-coded Himawari infrared picture into the night look: bright (cold) and strongly coloured
// (very cold) pixels are cloud, the rest is dark background.
//
// ir: the infrared picture's colour.
// Returns: the night colour.
vec3 night_view(vec3 ir) {
	float sat = max(ir.r, max(ir.g, ir.b)) - min(ir.r, min(ir.g, ir.b));
	float lum = dot(ir, vec3(0.299, 0.587, 0.114));
	float cloud = smoothstep(CLOUD_LOW, CLOUD_HIGH, lum + 2.0 * sat);
	return mix(NIGHT_BACKGROUND, NIGHT_CLOUD, cloud);
}

// Computes one output pixel: the weighted average of the satellite pictures, mixed over the base picture by how well
// the pixel is covered.
void fragment() {
	float lon = UV.x * 360.0 - 180.0;
	float lat = 90.0 - UV.y * 180.0;
	float w_west = have_west ? footprint(lon, lat, LON_WEST, RADIUS_GOES) : 0.0;
	float w_east = have_east ? footprint(lon, lat, LON_EAST, RADIUS_GOES) : 0.0;
	float w_mtg = have_mtg ? footprint(lon, lat, LON_MTG, RADIUS_MTG) : 0.0;
	bool him_any = have_himawari || have_himawari_ir;
	float w_him = him_any ? footprint(lon, lat, LON_HIMAWARI, RADIUS_HIMAWARI) : 0.0;
	vec3 c_west = texture(goes_west, UV).rgb;
	vec3 c_east = texture(goes_east, UV).rgb;
	vec3 c_mtg = texture(mtg, UV).rgb;
	vec3 c_vis = texture(himawari, UV).rgb;
	vec3 c_ir = texture(himawari_ir, UV).rgb;
	// Daylight on Himawari's view: 1 where the visible picture has light in it.
	float day = have_himawari ? smoothstep(NIGHT_LOW, NIGHT_HIGH, max(c_vis.r, max(c_vis.g, c_vis.b))) : 0.0;
	vec3 c_him = mix(have_himawari_ir ? night_view(c_ir) : vec3(0.0), c_vis, day);
	if (!have_himawari_ir) {
		w_him *= day;  // no infrared picture: the night side is "no data"
	}
	float total = w_west + w_east + w_mtg + w_him;
	vec3 weather = (w_west * c_west + w_east * c_east + w_mtg * c_mtg + w_him * c_him) / max(total, 0.0001);
	float coverage = min(total, 1.0);
	vec3 base = (blend_with_base && have_base) ? texture(base_map, UV).rgb : vec3(0.0);
	COLOR = vec4(mix(base, weather, coverage), 1.0);
}
