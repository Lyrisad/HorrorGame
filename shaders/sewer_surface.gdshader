shader_type spatial;
render_mode cull_disabled;
// Murs, sols et plafonds des égouts : la texture de base (projection triplanaire « monde »), plus ce que
// l'humidité y met, réparti au hasard sans motif répété :
//   murs    : mousse et algues qui montent du bas, grosses plaques plus haut, efflorescences blanches
//             (sel qui ressort du béton / de la brique), coulures sombres et luisantes depuis la voûte ;
//   sols    : plaques de vase, zones mouillées qui brillent sous la lampe, crasse ;
//   plafonds: taches d'humidité et de moisissure.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 2.0;
uniform vec3 tint : source_color = vec3(0.6);
uniform float rough_mul = 0.7;
uniform float moss = 0.6;
uniform float salt = 0.4;
uniform float damp = 0.6;
uniform float mud = 0.5;
uniform float puddles = 0.5;

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

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 5.2) * 0.3 + vnoise(p * 4.7 + 1.7) * 0.15;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 tri(sampler2D t, vec3 p, vec3 w, float sc) {
	return texture(t, p.zy / sc) * w.x + texture(t, p.xz / sc) * w.y + texture(t, p.xy / sc) * w.z;
}

void fragment() {
	vec3 w = pow(abs(wnrm), vec3(6.0));
	w /= (w.x + w.y + w.z);
	vec3 alb = tri(albedo_tex, wpos, w, tile).rgb * tint;
	float rough = tri(rough_tex, wpos, w, tile).r * rough_mul;
	vec3 nt = tri(normal_tex, wpos, w, tile).rgb;

	float is_floor = smoothstep(0.6, 0.85, wnrm.y);
	float is_ceil = smoothstep(0.6, 0.85, -wnrm.y);
	float is_wall = clamp(1.0 - is_floor - is_ceil, 0.0, 1.0);
	float h = wpos.y;
	// coordonnée horizontale le long du mur (selon qu'il est orienté x ou z)
	float along = w.x > w.z ? wpos.z : wpos.x;

	if (is_wall > 0.01) {
		// mousse / algues : une bande qui monte du bas (bord déchiqueté) + des plaques plus haut
		float edge = 0.18 + fbm(vec2(along * 1.4, 1.3)) * 0.65;
		float band = 1.0 - smoothstep(edge * 0.6, edge, h);
		float patch = smoothstep(0.6, 0.74, fbm(vec2(along * 0.7, h * 0.9) + 3.0)) * (1.0 - smoothstep(1.2, 2.4, h));
		float m = clamp(band * 0.9 + patch * 0.8, 0.0, 1.0) * moss * is_wall;
		vec3 mcol = tri(moss_tex, wpos, w, 1.1).rgb * vec3(0.5, 0.62, 0.4);
		alb = mix(alb, mcol, m);
		rough = mix(rough, 0.42, m);
		// efflorescences : croûtes blanches de sel, granuleuses, à mi-hauteur
		float gr = vnoise(vec2(along * 40.0, h * 40.0));
		// (un voile minéral qui éclaircit la brique sans la recouvrir, pas des taches de peinture)
		float s = smoothstep(0.7, 0.85, fbm(vec2(along * 1.2, h * 1.5) + 7.0)) * smoothstep(0.35, 0.8, h) * (1.0 - smoothstep(1.9, 2.8, h));
		s *= salt * is_wall * (0.35 + 0.65 * gr) * (1.0 - m);
		alb = mix(alb, alb * 0.55 + vec3(0.2, 0.2, 0.19), s * 0.6);
		rough = mix(rough, 0.95, s);
		// coulures depuis la voûte : traînées verticales sombres et luisantes, plus fréquentes en haut
		float st = vnoise(vec2(along * 6.5, h * 0.3 + 4.0)) * 0.7 + vnoise(vec2(along * 19.0, h * 0.9)) * 0.3;
		float ds = smoothstep(0.58, 0.8, st) * smoothstep(0.3, 1.8, h) * damp * is_wall;
		alb *= 1.0 - ds * 0.5;
		rough = mix(rough, 0.2, ds);
	}
	if (is_floor > 0.01) {
		// plaques de vase
		float mp = smoothstep(0.56, 0.72, fbm(wpos.xz * 0.45 + 11.0)) * mud * is_floor;
		vec3 mudc = texture(mud_tex, wpos.xz / 1.4).rgb * vec3(0.5, 0.46, 0.38);
		alb = mix(alb, mudc, mp * 0.85);
		rough = mix(rough, 0.55, mp);
		// zones mouillées : plus sombres et très brillantes sous la lampe
		float wet = smoothstep(0.55, 0.7, fbm(wpos.xz * 0.7 + 23.0)) * puddles * is_floor;
		alb *= 1.0 - wet * 0.35;
		rough = mix(rough, 0.07, wet);
		// crasse fine
		float gm = smoothstep(0.5, 0.9, vnoise(wpos.xz * 9.0 + 2.0)) * 0.25 * is_floor;
		alb *= 1.0 - gm;
	}
	if (is_ceil > 0.01) {
		float cm = smoothstep(0.58, 0.74, fbm(wpos.xz * 0.9 + 31.0)) * damp * is_ceil;
		alb = mix(alb, alb * vec3(0.38, 0.42, 0.36), cm);
		rough = mix(rough, 0.3, cm);
	}
	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	NORMAL_MAP = nt;
	SPECULAR = 0.5;
}
