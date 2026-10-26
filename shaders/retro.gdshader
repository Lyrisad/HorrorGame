shader_type spatial;
// Film rétroréfléchissant (panneaux, balises, peinture du marquage) : il renvoie la lumière vers sa source. La lampe
// de Théo est contre l'objectif, donc tout ce qui est dans son faisceau s'allume vers la caméra, comme dans des
// phares ; la lampe à sodium du poteau, elle, éclaire de côté et ne fait presque rien briller.

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform vec3 tint = vec3(1.0);
uniform float retro = 6.0;  // force du renvoi vers la lampe
uniform float back = 0.0;  // 1 = dos du panneau : tôle galvanisée, sans film
uniform float rough = 0.55;
uniform bool use_alpha = true;

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = mix(t.rgb * tint, vec3(0.34, 0.35, 0.36) * (0.6 + 0.4 * t.a), back);
	if (use_alpha) {
		ALPHA = t.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
	ROUGHNESS = mix(rough, 0.45, back);
	METALLIC = back * 0.55;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR / PI;
	float facing = pow(clamp(dot(VIEW, LIGHT), 0.0, 1.0), 48.0);
	SPECULAR_LIGHT += ALBEDO * facing * sqrt(ndl) * retro * (1.0 - back) * ATTENUATION * LIGHT_COLOR / PI;
}
