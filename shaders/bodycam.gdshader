shader_type canvas_item;
// Rendu "caméra-piéton" appliqué sur toute l'image :
// objectif grand-angle (barillet), aberration chromatique, accentuation numérique,
// bruit de capteur (plus fort dans le noir), vignettage, désaturation,
// obturateur roulant, artefacts de compression (glitch), perte de signal.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

uniform float distortion = 0.30;
uniform float aberration = 0.035;
uniform float grain = 0.075;
uniform float gain = 0.0;
uniform float vignette = 0.85;
uniform float glitch = 0.0;
uniform float shutter = 0.0;
uniform float saturation = 0.8;
uniform float flash = 0.0;
uniform float exposure = 1.0;
uniform float blackout = 0.0;
uniform float sharpen = 0.45;
uniform float shake_x = 0.0;
uniform vec3 tint : source_color = vec3(1.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 distort(vec2 uv, float k, float aspect) {
	vec2 c = uv - 0.5;
	vec2 cc = vec2(c.x * aspect, c.y);
	float r2 = dot(cc, cc);
	float norm = 1.0 + k * 0.25 * aspect * aspect;
	return 0.5 + c * (1.0 + k * r2) / norm;
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float aspect = res.x / res.y;
	vec2 uv = SCREEN_UV;
	float frame = floor(TIME * 30.0);

	// --- perte de signal / compression ---
	if (glitch > 0.001) {
		float band = floor(uv.y * 28.0);
		float n = hash12(vec2(band, frame));
		if (n < glitch * 0.55) {
			uv.x += (hash12(vec2(band, frame + 3.0)) - 0.5) * 0.18 * glitch;
		}
		vec2 grid = vec2(48.0, 27.0);
		vec2 blk = floor(uv * grid);
		if (hash12(blk + frame * 1.7) < glitch * 0.16) {
			uv = (blk + 0.5) / grid;
		}
	}

	// --- obturateur roulant + micro-tremblement horizontal ---
	uv.x += shutter * (uv.y - 0.5) + shake_x;

	// --- objectif grand-angle + aberration chromatique ---
	float ab = aberration * (1.0 + glitch * 5.0);
	vec2 uvG = distort(uv, distortion, aspect);
	vec2 uvR = distort(uv, distortion + ab, aspect);
	vec2 uvB = distort(uv, distortion - ab, aspect);
	vec3 col;
	col.r = texture(screen_tex, uvR).r;
	col.g = texture(screen_tex, uvG).g;
	col.b = texture(screen_tex, uvB).b;

	// accentuation "traitement vidéo" (masque flou)
	vec2 px = SCREEN_PIXEL_SIZE * 1.5;
	vec3 blur = texture(screen_tex, uvG + vec2(px.x, 0.0)).rgb
		+ texture(screen_tex, uvG - vec2(px.x, 0.0)).rgb
		+ texture(screen_tex, uvG + vec2(0.0, px.y)).rgb
		+ texture(screen_tex, uvG - vec2(0.0, px.y)).rgb;
	blur *= 0.25;
	col += (col - blur) * sharpen;

	vec2 edge = smoothstep(vec2(0.0), vec2(0.01), uvG) * smoothstep(vec2(0.0), vec2(0.01), 1.0 - uvG);
	float mask = edge.x * edge.y;

	// --- exposition, gain du capteur ---
	col = max(col, vec3(0.0)) * exposure * (1.0 + gain * 0.8);

	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation) * tint;

	// --- bruit de capteur (cadencé à 30 i/s comme une vraie vidéo) ---
	float g = hash13(vec3(FRAGCOORD.xy, frame * 7.0)) - 0.5;
	float gc = hash13(vec3(FRAGCOORD.xy * 1.37, frame * 3.0 + 11.0)) - 0.5;
	float dark = 1.0 - smoothstep(0.0, 0.5, l);
	float amp = grain * (0.35 + dark * 1.1) * (1.0 + gain * 2.2);
	col += g * amp;
	col.r += gc * amp * 0.5 * dark;
	col.b -= gc * amp * 0.5 * dark;

	// noirs légèrement relevés, typiques des petits capteurs
	col = col * 0.965 + 0.012;

	// --- vignettage ---
	vec2 vc = SCREEN_UV - 0.5;
	vc.x *= aspect * 0.72;
	float vig = smoothstep(0.82, 0.22, length(vc));
	col *= mix(1.0, vig, vignette);
	col *= mask;

	// --- lignes parasites ---
	if (glitch > 0.001) {
		float line = step(1.0 - glitch * 0.09, hash12(vec2(floor(SCREEN_UV.y * 140.0), frame)));
		vec3 junk = vec3(hash12(vec2(frame, SCREEN_UV.y)), hash12(vec2(SCREEN_UV.y * 3.0, frame)), 0.8);
		col = mix(col, junk, line * 0.55);
	}

	col = mix(col, vec3(1.0), flash);
	// écran noir de perte de signal (avec un peu de neige)
	vec3 snow = vec3(hash13(vec3(FRAGCOORD.xy * 0.5, frame)) * 0.08);
	col = mix(col, snow, blackout);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
