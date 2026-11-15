shader_type canvas_item;
// Weather-satellite compositor: merges the full-disk pictures of GOES-West, GOES-East and Himawari (each already
// laid out as a whole-world equirectangular image, black outside the satellite's view) into one whole-world picture.
// Drawn once into a 4096 by 2048 SubViewport by weather_composer.gd; the result is read back as an Image.
//
// Method: each satellite gets a weight per pixel that is 1 well inside its footprint and fades to 0 at its edge, where
// the view is stretched and noisy. Where footprints overlap the pictures are averaged by those weights, so there is no
// seam. Where no satellite sees (the gap over Europe, Africa and the Indian Ocean, and the poles), the result is the
// base picture (blend mode) or black (weather-only mode).

// The three satellite pictures, each whole-world equirectangular. Linear filtering; no mipmaps (drawn 1:1).
uniform sampler2D goes_west : filter_linear, repeat_disable;
uniform sampler2D goes_east : filter_linear, repeat_disable;
uniform sampler2D himawari : filter_linear, repeat_disable;
// The base picture (the NOAA-21 map) used behind the weather pictures in blend mode.
uniform sampler2D base_map : filter_linear, repeat_disable;
// Which of the pictures are present. A missing picture is simply skipped (its area becomes base or black).
uniform bool have_west = false;
uniform bool have_east = false;
uniform bool have_himawari = false;
uniform bool have_base = false;
// true: fade into the base picture; false: show only the weather pictures, black where there are none.
uniform bool blend_with_base = true;

// Longitude (degrees) of the point each satellite hangs over.
const float LON_WEST = -137.0;      // GOES-West
const float LON_EAST = -75.2;       // GOES-East
const float LON_HIMAWARI = 140.7;   // Himawari
// Half-size of a satellite's rounded-square footprint, in degrees from its sub-point (the usable part of the disk).
const float RADIUS = 76.0;
// The weight is 1 up to this fraction of RADIUS and fades to 0 at EDGE_END (the limb is stretched and noisy).
const float EDGE_START = 0.80;
const float EDGE_END = 0.95;
// Himawari's layer is the visible band only, so its night side is black; pixels this dark count as "no data".
// The weight ramps from 0 at NIGHT_LOW to 1 at NIGHT_HIGH (brightest channel, 0..1).
const float NIGHT_LOW = 0.02;
const float NIGHT_HIGH = 0.08;

// Weight of one satellite at a place: 1 inside the footprint, fading to 0 across its edge.
//
// lon, lat: the place in degrees.
// lon0: the satellite's sub-point longitude.
// Returns: the weight, 0 to 1. The footprint is a rounded square (a superellipse of exponent 5) like the pictures.
float footprint(float lon, float lat, float lon0) {
	float dlon = abs(mod(lon - lon0 + 540.0, 360.0) - 180.0);
	float s = pow(pow(dlon / RADIUS, 5.0) + pow(abs(lat) / RADIUS, 5.0), 0.2);
	return 1.0 - smoothstep(EDGE_START, EDGE_END, s);
}

// Computes one output pixel: the weighted average of the satellite pictures, mixed over the base picture by how well
// the pixel is covered.
void fragment() {
	float lon = UV.x * 360.0 - 180.0;
	float lat = 90.0 - UV.y * 180.0;
	float w_west = have_west ? footprint(lon, lat, LON_WEST) : 0.0;
	float w_east = have_east ? footprint(lon, lat, LON_EAST) : 0.0;
	float w_him = have_himawari ? footprint(lon, lat, LON_HIMAWARI) : 0.0;
	vec3 c_west = texture(goes_west, UV).rgb;
	vec3 c_east = texture(goes_east, UV).rgb;
	vec3 c_him = texture(himawari, UV).rgb;
	w_him *= smoothstep(NIGHT_LOW, NIGHT_HIGH, max(c_him.r, max(c_him.g, c_him.b)));
	float total = w_west + w_east + w_him;
	vec3 weather = (w_west * c_west + w_east * c_east + w_him * c_him) / max(total, 0.0001);
	float coverage = min(total, 1.0);
	vec3 base = (blend_with_base && have_base) ? texture(base_map, UV).rgb : vec3(0.0);
	COLOR = vec4(mix(base, weather, coverage), 1.0);
}
