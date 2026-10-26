shader_type spatial;
// Sol de forêt la nuit : feuilles mortes et aiguilles mêlées par taches, mousse dans les creux, et le sentier
// tassé et boueux (COLOR.r = sentier, COLOR.g = mousse). Coordonnées du monde : pas d'étirement sur le relief.

uniform sampler2D litter_diff : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D litter_nor : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D needles_diff : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D needles_nor : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D path_diff : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D path_nor : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D moss_diff : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D mask_noise : filter_linear_mipmap;
uniform float tile = 2.6;
uniform float path_tile = 3.2;
uniform vec3 tint = vec3(0.75, 0.72, 0.68);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz / tile;
	// deux tailles de bruit pour casser la répétition
	float n = texture(mask_noise, wpos.xz * 0.025).r * 0.7 + texture(mask_noise, wpos.xz * 0.11).r * 0.3;
	float needles = smoothstep(0.42, 0.62, n);
	vec3 a = mix(texture(litter_diff, uv).rgb, texture(needles_diff, uv * 0.8 + 0.37).rgb, needles);
	vec3 na = mix(texture(litter_nor, uv).rgb, texture(needles_nor, uv * 0.8 + 0.37).rgb, needles);
	// mousse : dans les creux et par plaques
	float moss = clamp(COLOR.g * smoothstep(0.35, 0.7, texture(mask_noise, wpos.xz * 0.07 + 0.5).r) * 1.4, 0.0, 1.0);
	a = mix(a, texture(moss_diff, uv * 1.3).rgb * vec3(0.7, 0.85, 0.6), moss * 0.75);
	// sentier : terre tassée, boue, bords irréguliers
	float edge = texture(mask_noise, wpos.xz * 0.35).r;
	float path = smoothstep(0.25, 0.75, COLOR.r + (edge - 0.5) * 0.35);
	vec2 puv = wpos.xz / path_tile;
	a = mix(a, texture(path_diff, puv).rgb * 0.85, path);
	na = mix(na, texture(path_nor, puv).rgb, path);
	ALBEDO = a * tint;
	NORMAL_MAP = na;
	ROUGHNESS = mix(0.95, 0.55, path * 0.8);
	SPECULAR = mix(0.25, 0.45, path);
}
