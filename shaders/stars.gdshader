// Stars as small round points on the sky sphere. Each star is a quad built from its direction
// (VERTEX, a unit vector in the star frame); UV is the corner (-1..1) and COLOR carries the star's
// colour (rgb) and UV2.x the size in pixels (vertex colours are 8-bit, so they cannot carry it).

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float pixel_angle = 0.0002;   // radians per screen pixel
uniform float sky_radius = 200.0;

varying vec2 corner;
varying vec3 star_color;

void vertex() {
	vec3 d = normalize(VERTEX);
	vec3 t1 = normalize(cross(d, abs(d.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0)));
	vec3 t2 = cross(d, t1);
	float half_size = UV2.x * pixel_angle;
	VERTEX = d + (t1 * UV.x + t2 * UV.y) * half_size;
	corner = UV;
	star_color = COLOR.rgb;
}

void fragment() {
	float r = length(corner);
	// A solid bright core with a soft edge, so even small stars read clearly.
	float a = 1.0 - smoothstep(0.35, 1.0, r);
	// Keep the star's colour (no clipping to white) with only a small white-hot centre.
	vec3 c = mix(star_color, vec3(1.0), 0.35 * (1.0 - smoothstep(0.0, 0.3, r)));
	ALBEDO = c * a * 1.15;
}
