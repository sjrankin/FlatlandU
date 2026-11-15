// Day/night Earth: evenly lit day side, dark night side, a sharp terminator, and it receives the
// sun's shadows (hour labels, cities, ...). Only the (white) sun light contributes to the day side;
// the cyan moon light is emulated by the night term.

shader_type spatial;
render_mode depth_prepass_alpha, cull_back, specular_disabled;

// The map picture (an equirectangular texture for the sphere, a face picture for the cube), in sRGB with mipmaps
// and anisotropic filtering so it stays sharp at a slant.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// True once a map texture has been set (GlobeView `_set_tex`); until then the surface is just [albedo_color].
uniform bool use_tex = false;
// A color multiplied into the map (white shows the map as it is; the sea sphere uses a pale blue with no
// texture).
uniform vec4 albedo_color : source_color = vec4(1.0);
// Direction of the Sun, a unit vector. In this scene the Sun is fixed at +Z (the Earth turns beneath it), set by
// GlobeView `_update_time`.
uniform vec3 sun_dir = vec3(0.0, 0.0, 1.0);
// How much of the surface color shows as a faint glow on the night side (0.04 normally, 0.14 with the moon light
// setting).
uniform float night_level = 0.06;
// The color of that night glow (a pale blue, as moonlight).
uniform vec3 night_tint = vec3(0.55, 0.75, 1.0);
// Half the width of the soft edge between day and night, as a cosine of the angle to the Sun (0.012 is a sharp
// terminator).
uniform float terminator_width = 0.012;

// The surface normal in world space, set in vertex() and used to find the angle to the Sun.
varying vec3 wnormal;

// vertex(): turns the model's normal into world space for [wnormal]. Runs once per vertex.
void vertex() {
	wnormal = normalize((MODEL_NORMAL_MATRIX * NORMAL));
}

// day_amount(): how much day there is at this point, from 0 (night) to 1 (day), a smooth step across the
// terminator. Returns: that value. Used by fragment() and light().
float day_amount() {
	float ndl = dot(normalize(wnormal), normalize(sun_dir));
	return smoothstep(-terminator_width, terminator_width, ndl);
}

// fragment(): the surface itself. Takes the map color (times albedo_color), is fully rough, glows faintly on the
// night side (the "night" term emulates the cyan moon light) and keeps the map's transparency (maps with
// transparent seas sit over a sea sphere). Runs once per pixel.
void fragment() {
	vec4 t = use_tex ? texture(albedo_tex, UV) : vec4(1.0);
	vec3 base = t.rgb * albedo_color.rgb;
	ALBEDO = base;
	ROUGHNESS = 1.0;
	EMISSION = base * night_level * night_tint * (1.0 - day_amount());
	ALPHA = use_tex ? t.a * albedo_color.a : albedo_color.a;
}

// light(): adds the Sun's light: only the white Sun light counts (the cyan moon light is ignored, being emulated
// by the night term in fragment()), scaled by day_amount(), a little brighter facing the Sun, and darkened where
// the Sun's shadow falls (ATTENUATION). Runs once per light per pixel.
void light() {
	float ndl = dot(normalize(wnormal), normalize(sun_dir));
	float sun = step(0.5, LIGHT_COLOR.r);
	float shade = 0.6 * mix(0.8, 1.0, clamp(ndl, 0.0, 1.0));
	DIFFUSE_LIGHT += sun * day_amount() * shade * mix(0.3, 1.0, ATTENUATION);
}
