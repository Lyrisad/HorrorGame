shader_type canvas_item;
// Rendu "caméra-piéton" appliqué sur toute l'image :
// objectif grand-angle (barillet), aberration chromatique, accentuation numérique,
// reflets de l'objectif sur les lampes (flare), bruit de capteur (plus fort dans le noir),
// macroblocs de compression dans les ombres, vignettage, désaturation, obturateur roulant,
// objectif fêlé, buée et gouttes d'eau sur la vitre, artefacts (glitch), perte de signal.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D crack_tex : filter_linear, repeat_disable;  // R : fissures, G : zone éclatée
uniform sampler2D drops_tex : filter_linear, repeat_disable;  // RG : réfraction, B : goutte

uniform float distortion = 0.30;
uniform float aberration = 0.012;
uniform float grain = 0.04;
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
uniform float compress = 1.0;    // macroblocs de compression dans les zones sombres
uniform float crack = 0.0;       // objectif fêlé (après l'agression)
uniform float lens_fog = 0.0;    // buée sur l'objectif (humidité)
uniform float lens_drops = 0.0;  // gouttes sur l'objectif (éclaboussure)
uniform float flare = 1.0;
// lampes visibles projetées à l'écran : xy = position (uv), z = intensité, w = taille
uniform vec4 flare_src[4];
uniform vec4 flare_col[4];

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

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec2 distort(vec2 uv, float k, float aspect) {
	vec2 c = uv - 0.5;
	vec2 cc = vec2(c.x * aspect, c.y);
	float r2 = dot(cc, cc);
	float norm = 1.0 + k * 0.25 * aspect * aspect;
	return 0.5 + c * (1.0 + k * r2) / norm;
}

// reflets d'une lampe dans les lentilles : halo, traînée horizontale, étoile, et « fantômes »
// alignés sur l'axe lampe → centre de l'image
vec3 flare_of(vec2 uv, vec4 src, vec3 tint_c, float aspect, float haze) {
	if (src.z <= 0.001) {
		return vec3(0.0);
	}
	vec2 asp = vec2(aspect, 1.0);
	vec2 d = (uv - src.xy) * asp;
	float r = length(d);
	float sz = src.w * (1.0 + haze * 2.5);
	vec3 acc = vec3(0.0);
	acc += tint_c * exp(-r * r / (sz * sz * 0.004)) * 0.9;
	acc += tint_c * exp(-r / (sz * 0.09)) * 0.25;
	// traînée horizontale fine (verre de protection de la caméra)
	acc += mix(tint_c, vec3(0.75, 0.85, 1.0), 0.5) * exp(-abs(d.y) * 260.0 / sz) * exp(-abs(d.x) * 5.0 / sz) * 0.35;
	// étoile à 6 branches (diaphragme)
	float ang = atan(d.y, d.x);
	float star = pow(abs(cos(ang * 3.0)), 60.0);
	acc += tint_c * star * exp(-r * 14.0 / sz) * 0.4;
	// fantômes : images de la lampe réfléchies, de l'autre côté du centre
	vec2 axis = src.xy - 0.5;
	for (int i = 0; i < 4; i++) {
		float s = -0.35 - 0.42 * float(i);
		if (i == 3) {
			s = 0.42;
		}
		vec2 gp = 0.5 + axis * s;
		float gr = (0.018 + 0.016 * float(i)) * sz;
		float gd = length((uv - gp) * asp);
		float ring = smoothstep(gr, gr * 0.55, gd) * (0.35 + 0.65 * smoothstep(gr * 0.3, gr, gd));
		vec3 gc = i == 0 ? vec3(0.45, 0.9, 0.6) : (i == 1 ? vec3(0.7, 0.45, 1.0) : (i == 2 ? vec3(1.0, 0.7, 0.35) : vec3(0.5, 0.7, 1.0)));
		acc += gc * tint_c * ring * 0.09;
	}
	return acc * src.z;
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

	// --- gouttes d'eau sur la vitre : petites lentilles qui retournent l'image ---
	float drop_mask = 0.0;
	if (lens_drops > 0.001) {
		vec4 dr = texture(drops_tex, SCREEN_UV);
		drop_mask = dr.b * smoothstep(0.0, 0.35, lens_drops);
		uv += (dr.rg * 2.0 - 1.0) * vec2(0.035, 0.035 * aspect) * drop_mask;
	}
	// --- fissures : le verre fendu décale un peu l'image de part et d'autre ---
	float crack_line = 0.0;
	float crack_haze = 0.0;
	if (crack > 0.001) {
		vec4 ck = texture(crack_tex, SCREEN_UV);
		crack_line = ck.r * crack;
		crack_haze = ck.g * crack;
		float gx = texture(crack_tex, SCREEN_UV + vec2(SCREEN_PIXEL_SIZE.x * 2.0, 0.0)).r - ck.r;
		float gy = texture(crack_tex, SCREEN_UV + vec2(0.0, SCREEN_PIXEL_SIZE.y * 2.0)).r - ck.r;
		uv += vec2(gx, gy) * 0.004 * crack + (vnoise(SCREEN_UV * 90.0) - 0.5) * 0.01 * crack_haze;
	}

	// --- objectif grand-angle + aberration chromatique (légère, surtout sur les bords) ---
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
	col += (col - blur) * sharpen * (1.0 - lens_fog);

	// --- buée : voile laiteux et flou, qui se dissipe d'abord au centre ---
	float fog_m = 0.0;
	if (lens_fog > 0.001) {
		vec2 vc0 = (SCREEN_UV - 0.5) * vec2(aspect, 1.0);
		float rr = length(vc0);
		float pattern = vnoise(SCREEN_UV * vec2(7.0 * aspect, 7.0)) * 0.6 + vnoise(SCREEN_UV * 23.0) * 0.4;
		fog_m = clamp((lens_fog * 1.5 - (0.55 - rr * 0.7)) + (pattern - 0.5) * 0.5, 0.0, 1.0) * smoothstep(0.0, 0.25, lens_fog);
		vec3 soft = vec3(0.0);
		float rad = 0.012 + 0.02 * fog_m;
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.785398;
			soft += texture(screen_tex, uvG + vec2(cos(a), sin(a) * aspect) * rad).rgb;
		}
		soft /= 8.0;
		col = mix(col, soft * 0.92 + vec3(0.035, 0.04, 0.038), fog_m * 0.85);
	}
	// gouttes : tout près de l'objectif, donc floues ; leur bord accroche la lumière
	if (drop_mask > 0.001) {
		vec3 dsoft = vec3(0.0);
		for (int i = 0; i < 6; i++) {
			float a = float(i) * 1.0472;
			dsoft += texture(screen_tex, uvG + vec2(cos(a), sin(a) * aspect) * 0.006).rgb;
		}
		dsoft /= 6.0;
		float dl = dot(dsoft, vec3(0.333));
		col = mix(col, dsoft * 1.15 + 0.02, drop_mask * 0.8);
		float ring = clamp(drop_mask * (1.0 - drop_mask) * 4.0, 0.0, 1.0);
		col += ring * (0.015 + dl * 0.25);
	}

	vec2 edge = smoothstep(vec2(0.0), vec2(0.01), uvG) * smoothstep(vec2(0.0), vec2(0.01), 1.0 - uvG);
	float mask = edge.x * edge.y;

	// --- reflets de l'objectif sur les lampes visibles ---
	vec3 fl = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		fl += flare_of(uvG, flare_src[i], flare_col[i].rgb, aspect, lens_fog);
	}
	col += fl * flare;

	// --- exposition, gain du capteur ---
	col = max(col, vec3(0.0)) * exposure * (1.0 + gain * 0.8);

	float l = dot(col, vec3(0.299, 0.587, 0.114));
	float dark = 1.0 - smoothstep(0.0, 0.5, l);

	// --- macroblocs de compression : dans les ombres, l'encodeur lisse par blocs de 8 px ---
	if (compress > 0.001) {
		vec2 bpx = floor(uvG * res / 8.0) * 8.0 + 4.0;
		vec3 bcol = texture(screen_tex, bpx / res).rgb * exposure * (1.0 + gain * 0.8);
		float moving = 0.5 + 0.5 * hash12(floor(uvG * res / 8.0) + floor(TIME * 6.0));
		col = mix(col, bcol, dark * dark * 0.22 * compress * moving);
	}

	col = mix(vec3(l), col, saturation) * tint;

	// --- bruit de capteur (cadencé à 30 i/s comme une vraie vidéo), adouci par la compression ---
	float gf = hash13(vec3(FRAGCOORD.xy, frame * 7.0)) - 0.5;
	float gco = hash13(vec3(floor(FRAGCOORD.xy / 2.0), frame * 5.0 + 3.0)) - 0.5;
	float g = mix(gf, gco, 0.55);
	float gc = hash13(vec3(floor(FRAGCOORD.xy / 2.0) * 1.37, frame * 3.0 + 11.0)) - 0.5;
	float amp = grain * (0.3 + dark * 0.9) * (1.0 + gain * 1.6);
	col += g * amp;
	col.r += gc * amp * 0.25 * dark;
	col.b -= gc * amp * 0.25 * dark;

	// noirs légèrement relevés, typiques des petits capteurs
	col = col * 0.965 + 0.012;

	// --- vignettage ---
	vec2 vc = SCREEN_UV - 0.5;
	vc.x *= aspect * 0.72;
	float vig = smoothstep(0.82, 0.22, length(vc));
	col *= mix(1.0, vig, vignette);

	// --- verre fendu : traits sombres qui accrochent la lumière, verre pilé laiteux à l'impact ---
	if (crack > 0.001) {
		float lum = dot(blur, vec3(0.333));
		col = mix(col, col * 0.35, crack_line * 0.75);
		col += vec3(0.9, 0.95, 1.0) * crack_line * (0.075 + lum * 0.6) * crack;
		col = mix(col, vec3(0.34, 0.36, 0.35) * (0.4 + lum), crack_haze * 0.6);
	}
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
