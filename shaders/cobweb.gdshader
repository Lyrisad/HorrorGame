shader_type spatial;
// Toile d'araignée : soie translucide qui accroche la lumière (la lampe torche la fait apparaître),
// éclairée des deux côtés (la lumière traverse la nappe). Le courant d'air la fait onduler à peine ;
// les fils pendants se balancent. COLOR.r = souplesse du point (0 aux accroches, 1 au plus libre).
render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D web_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint : source_color = vec4(0.9, 0.9, 0.88, 1.0);
uniform float opacity = 0.95;
uniform float sway = 0.01;       // ondulation de la nappe (m), le long de sa normale
uniform float sway_hang = 0.0;   // balancement des fils pendants (m), à l'horizontale

void vertex() {
	float w = COLOR.r;
	float ph = NODE_POSITION_WORLD.x * 1.7 + NODE_POSITION_WORLD.z * 2.3;
	// rafales irrégulières : deux sinus lents qui se contrarient
	float gust = sin(TIME * 0.9 + ph) * 0.6 + sin(TIME * 2.3 + ph * 1.3) * 0.4;
	VERTEX += NORMAL * gust * sway * w;
	VERTEX.x += sin(TIME * 1.1 + ph) * sway_hang * w;
	VERTEX.z += cos(TIME * 0.8 + ph * 0.7) * sway_hang * w * 0.7;
}

void fragment() {
	vec4 t = texture(web_tex, UV);
	ALBEDO = tint.rgb * t.rgb;
	ALPHA = min(t.a * 1.35, 1.0) * opacity;
	// la soie est lustrée : des reflets fins quand le faisceau la prend
	ROUGHNESS = 0.38;
	SPECULAR = 0.8;
	BACKLIGHT = vec3(0.8);
}
