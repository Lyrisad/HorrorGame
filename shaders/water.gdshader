shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Eau stagnante des égouts : sombre, très réfléchissante, petites ondulations,
// et des ronds qui s'élargissent là où quelque chose la touche (pas, gouttes, créature, bouteille).

uniform vec3 color : source_color = vec3(0.035, 0.04, 0.03);
uniform sampler2D ripple : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.35;
uniform float speed = 0.02;
// ronds : x, z (monde), instant d'apparition, force ; ring_now = horloge du jeu
uniform vec4 rings[24];
uniform float ring_now = 0.0;

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = wp.xz * scale;
	vec3 n1 = texture(ripple, uv + vec2(TIME * speed, TIME * speed * 0.6)).rgb;
	vec3 n2 = texture(ripple, uv * 1.9 - vec2(TIME * speed * 0.8, -TIME * speed * 0.4)).rgb;
	vec3 nm = normalize(mix(n1, n2, 0.5)) * 2.0 - 1.0;
	// ondes circulaires : un front qui s'élargit (≈ 0,45 m/s) suivi de deux plus petits
	vec2 slope = vec2(0.0);
	for (int i = 0; i < 24; i++) {
		vec4 r = rings[i];
		if (r.w <= 0.0) {
			continue;
		}
		float age = ring_now - r.z;
		if (age < 0.0 || age > 2.2) {
			continue;
		}
		vec2 dv = wp.xz - r.xy;
		float d = length(dv);
		float fade = pow(1.0 - age / 2.2, 2.0) * r.w;
		for (int k = 0; k < 3; k++) {
			float rad = 0.03 + (age - float(k) * 0.16) * 0.45;
			if (rad <= 0.0) {
				continue;
			}
			float x = (d - rad) / 0.035;
			// dérivée d'une petite vague (gaussienne × sinus) : penche la normale vers l'extérieur
			float w = exp(-x * x) * cos(x * 2.4) * fade * (1.0 - float(k) * 0.3) / (1.0 + rad * 3.0);
			slope += (dv / max(d, 0.001)) * w;
		}
	}
	nm.xy += slope * 1.6;
	NORMAL_MAP = normalize(nm) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.35 + min(length(slope), 1.0) * 0.6;
	ALBEDO = color;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
