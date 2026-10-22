shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;
// Filet d'eau qui tombe d'une vieille conduite (traînées qui défilent vers le bas).

uniform float speed = 1.6;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float edge = smoothstep(0.0, 0.35, UV.x) * smoothstep(1.0, 0.65, UV.x);
	float n = vnoise(vec2(UV.x * 7.0, UV.y * 4.0 + TIME * speed * 3.0));
	float streaks = smoothstep(0.3, 0.85, n);
	ALBEDO = vec3(0.5, 0.55, 0.5);
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
	ALPHA = edge * (0.22 + 0.5 * streaks) * smoothstep(1.0, 0.85, UV.y);
}
