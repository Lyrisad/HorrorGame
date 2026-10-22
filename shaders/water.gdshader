shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Eau stagnante des égouts : sombre, très réfléchissante, petites ondulations.

uniform vec3 color : source_color = vec3(0.035, 0.04, 0.03);
uniform sampler2D ripple : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.35;
uniform float speed = 0.02;

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = wp.xz * scale;
	vec3 n1 = texture(ripple, uv + vec2(TIME * speed, TIME * speed * 0.6)).rgb;
	vec3 n2 = texture(ripple, uv * 1.9 - vec2(TIME * speed * 0.8, -TIME * speed * 0.4)).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 0.35;
	ALBEDO = color;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
