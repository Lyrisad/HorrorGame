shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
// Écran de surveillance : image en niveaux de gris verdâtres, lignes de balayage,
// neige numérique, coupure de signal.

uniform sampler2D feed : source_color, filter_linear;
uniform bool has_feed = true;
uniform float brightness = 1.25;
uniform float noise_amount = 0.10;
uniform float static_mix = 0.0;
uniform float power = 1.0;
uniform vec3 tint : source_color = vec3(0.82, 1.0, 0.86);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = UV;
	float frame = floor(TIME * 24.0);
	// léger décalage de ligne occasionnel
	float band = floor(uv.y * 40.0);
	if (hash12(vec2(band, frame)) > 0.985) {
		uv.x += 0.02;
	}
	vec3 c = has_feed ? texture(feed, uv).rgb : vec3(0.0);
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 col = vec3(pow(l, 0.85)) * tint * brightness;
	float n = hash12(floor(uv * vec2(320.0, 240.0)) + frame * 1.3);
	col += (n - 0.5) * noise_amount;
	col *= 0.86 + 0.14 * sin(uv.y * 720.0);
	col = mix(col, vec3(n * 0.14), static_mix);
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 1.2;
	ALBEDO = clamp(col, 0.0, 1.0) * power;
}
