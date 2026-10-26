shader_type spatial;
render_mode cull_disabled;
// Touffes d'herbe sèche du bord de la route (plans en croix, instanciés) : balancées par le vent, éclairées comme
// le sol (normale vers le haut, sinon le dos des plans est noir) ; COLOR = teinte de chaque touffe.

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float sway = 0.05;

varying float tip;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	tip = 1.0 - UV.y;
	float t = TIME * 1.4 + w.x * 0.37 + w.z * 0.23;
	float bend = tip * tip * sway;
	VERTEX.x += sin(t) * bend + sin(t * 2.7) * bend * 0.3;
	VERTEX.z += cos(t * 0.8) * bend * 0.6;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.25) * tip;
}
