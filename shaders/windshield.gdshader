shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;
// Pare-brise sous la pluie : gouttes qui s'accumulent puis sont balayées par les essuie-glaces.
// UV = coordonnées sur le vrai pare-brise, en mètres (x vers la droite, y en montant le long de la vitre).
// `wipe_t` = temps écoulé dans le cycle de balayage (au-delà de `cycle` quand ils sont arrêtés).

uniform float wipe_t = 99.0;
uniform float stroke = 0.6;
uniform float cycle = 3.2;
uniform float density = 0.55;
// balai gauche / droit : pivot (u, v) + longueur ; angles de repos et de haut de course (radians)
uniform vec3 piv_l = vec3(-0.44, -0.035, 0.6);
uniform vec2 ang_l = vec2(0.07, 1.85);
uniform vec3 piv_r = vec3(0.17, -0.035, 0.5);
uniform vec2 ang_r = vec2(0.07, 1.66);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// temps (s) depuis le dernier passage du balai sur ce point, ou très grand s'il n'y passe jamais
float age_for(vec2 p, vec3 piv, vec2 ang) {
	vec2 rel = p - piv.xy;
	float r = length(rel);
	if (r < 0.1 || r > piv.z) {
		return 99.0;
	}
	float s = (atan(rel.y, rel.x) - ang.x) / (ang.y - ang.x);
	if (s < 0.0 || s > 1.0) {
		return 99.0;
	}
	// mouvement sinusoïdal : montée pendant `stroke`, descente pendant `stroke`, puis pause
	float t_up = stroke * acos(1.0 - 2.0 * s) / PI;
	float t_dn = stroke + stroke * acos(2.0 * s - 1.0) / PI;
	if (wipe_t < t_up) {
		return wipe_t + cycle - t_dn;
	}
	if (wipe_t < t_dn) {
		return wipe_t - t_up;
	}
	return wipe_t - t_dn;
}

float drops(vec2 uv, vec2 grid, float salt) {
	vec2 cell = floor(uv * grid);
	vec2 f = fract(uv * grid) - 0.5;
	float h = hash12(cell + salt);
	float born = hash12(cell + 17.0 + salt);
	vec2 off = vec2(hash12(cell + 3.0 + salt), hash12(cell + 9.0 + salt)) - 0.5;
	// l'âge est pris au centre de la goutte : une goutte est balayée entière, jamais coupée
	vec2 c = (cell + 0.5 + off * 0.5) / grid;
	float age = min(age_for(c, piv_l, ang_l), age_for(c, piv_r, ang_r));
	float alive = step(born, min(age / cycle * density, 0.9));
	float r = 0.12 + 0.18 * h;
	float d = length((f - off * 0.5) * vec2(1.0, 1.6));
	return alive * smoothstep(r, r * 0.4, d);
}

void fragment() {
	vec2 uv = UV;
	float d = drops(uv, vec2(46.0, 34.0), 0.0) + drops(uv, vec2(78.0, 58.0), 41.0) * 0.6;
	ALBEDO = vec3(0.7, 0.75, 0.8);
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
	ALPHA = clamp(0.035 + d * 0.32, 0.0, 0.6);
}
