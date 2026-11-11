// Cubic world (same as earth.gdshader, but the day/night terminator follows each point's direction from
// the cube's centre, as if the cube were a sphere). Day/night Earth: evenly lit day side, dark night side, a sharp terminator, and it receives the
// sun's shadows (hour labels, cities, ...). Only the (white) sun light contributes to the day side;
// the cyan moon light is emulated by the night term.

shader_type spatial;
render_mode depth_prepass_alpha, cull_back, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool use_tex = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
uniform float night_level = 0.06;
uniform vec3 night_tint = vec3(0.55, 0.75, 1.0);
uniform float terminator_width = 0.012;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float day_amount() {
	float ndl = dot(normalize(wpos), normalize(sun_dir));
	return smoothstep(-terminator_width, terminator_width, ndl);
}

void fragment() {
	vec4 t = use_tex ? texture(albedo_tex, UV) : vec4(1.0);
	vec3 base = t.rgb * albedo_color.rgb;
	ALBEDO = base;
	ROUGHNESS = 1.0;
	EMISSION = base * night_level * night_tint * (1.0 - day_amount());
	ALPHA = use_tex ? t.a * albedo_color.a : albedo_color.a;
}

void light() {
	float ndl = dot(normalize(wpos), normalize(sun_dir));
	float sun = step(0.5, LIGHT_COLOR.r);
	float shade = 0.6 * mix(0.8, 1.0, clamp(ndl, 0.0, 1.0));
	DIFFUSE_LIGHT += sun * day_amount() * shade * mix(0.3, 1.0, ATTENUATION);
}
