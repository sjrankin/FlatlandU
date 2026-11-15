// Stars as small round points on the sky sphere. Each star is a quad built from its direction
// (VERTEX, a unit vector in the star frame); UV is the corner (-1..1) and COLOR carries the star's
// colour (rgb) and UV2.x the size in pixels (vertex colours are 8-bit, so they cannot carry it).

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// The angle in radians that one screen pixel covers at the current field of view (set by GlobeView
// `_apply_camera`), so stars are the same size in pixels at any zoom.
uniform float pixel_angle = 0.0002;
// Radius of the sky sphere the stars are drawn on (set from the camera's far plane; not used by the shader code
// itself).
uniform float sky_radius = 200.0;

// Which corner of the star's square this pixel is near (-1 to 1 each way); the distance from the center gives the
// round shape.
varying vec2 corner;
// The star's color, passed from vertex().
varying vec3 star_color;

// vertex(): builds a small square facing the viewer from the star's direction (VERTEX is a unit vector in the
// star frame). Its size in pixels comes from UV2.x times [pixel_angle] (vertex colors are 8-bit, so they cannot
// carry the size), and COLOR carries the star's color.
void vertex() {
	vec3 d = normalize(VERTEX);
	vec3 t1 = normalize(cross(d, abs(d.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0)));
	vec3 t2 = cross(d, t1);
	float half_size = UV2.x * pixel_angle;
	VERTEX = d + (t1 * UV.x + t2 * UV.y) * half_size;
	corner = UV;
	star_color = COLOR.rgb;
}

// fragment(): draws the star as a round point: a solid bright core with a soft edge, in the star's own color with
// only a small white-hot center, added to the sky (additive blending).
void fragment() {
	float r = length(corner);
	// A solid bright core with a soft edge, so even small stars read clearly.
	float a = 1.0 - smoothstep(0.35, 1.0, r);
	// Keep the star's colour (no clipping to white) with only a small white-hot centre.
	vec3 c = mix(star_color, vec3(1.0), 0.35 * (1.0 - smoothstep(0.0, 0.3, r)));
	ALBEDO = c * a * 1.15;
}
