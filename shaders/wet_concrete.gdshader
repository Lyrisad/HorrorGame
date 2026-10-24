shader_type spatial;
// Béton de coffrage vieilli des égouts (poteaux de la citerne, socles, cadres entre les galeries) :
// coulures verticales, crasse en bas, bande d'algues sombre à la ligne d'eau, partie immergée
// noire et luisante. Projection triplanaire « monde » : pas d'UV, densité de texture constante.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 1.6;          // mètres par répétition de la texture
uniform vec3 tint : source_color = vec3(0.62, 0.6, 0.56);
uniform float water_y = -0.045;    // niveau de l'eau (ou du sol pour les cadres)
uniform float algae_h = 0.5;       // hauteur de la bande d'algues / de crasse au-dessus de l'eau
uniform float submerged = 1.0;     // 1 = la base trempe dans l'eau

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy / tile) * w.x + texture(t, p.xz / tile) * w.y + texture(t, p.xy / tile) * w.z;
}

void fragment() {
	vec3 w = pow(abs(wnrm), vec3(6.0));
	w /= (w.x + w.y + w.z);
	vec3 alb = tri(albedo_tex, wpos, w).rgb * tint;
	float rough = tri(rough_tex, wpos, w).r;
	vec3 nt = tri(normal_tex, wpos, w).rgb;

	float h = wpos.y - water_y;
	// coordonnée le long de la surface (pour les coulures verticales)
	float along = dot(wpos.xz, vec2(0.83, 0.56)) * (1.0 - w.y);
	// coulures : de l'eau qui a ruisselé du plafond, plus marquées vers le bas
	float streak = vnoise(vec2(along * 9.0, wpos.y * 0.7)) * 0.65 + vnoise(vec2(along * 31.0, wpos.y * 2.0)) * 0.35;
	alb *= mix(1.0, 0.62 + 0.38 * streak, 0.55 * (1.0 - smoothstep(0.5, 3.5, h)));
	// crasse qui remonte du bas
	float n1 = vnoise(vec2(along * 4.0, wpos.y * 4.0));
	float grime = 1.0 - smoothstep(0.0, algae_h * 2.2 + n1 * 0.4, h);
	alb = mix(alb, alb * vec3(0.55, 0.5, 0.42), grime * 0.7);
	// bande d'algues / dépôt vaseux à la ligne d'eau, bord irrégulier
	float edge = algae_h * (0.6 + 0.8 * vnoise(vec2(along * 6.0, 3.1)));
	float algae = (1.0 - smoothstep(edge * 0.55, edge, h)) * step(-0.02, h) * submerged;
	alb = mix(alb, vec3(0.05, 0.065, 0.035) + alb * 0.18, algae * 0.85);
	// partie immergée : noire, luisante
	float wet = 1.0 - smoothstep(-0.01, 0.04, h);
	alb *= mix(1.0, 0.35, wet * submerged);
	ALBEDO = alb;
	ROUGHNESS = mix(clamp(rough * 0.95, 0.5, 1.0), 0.22, max(algae * 0.8, wet * submerged));
	NORMAL_MAP = nt;
	SPECULAR = 0.45;
}
