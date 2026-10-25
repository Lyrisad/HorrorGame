class_name Props
extends RefCounted
## Accessoires procéduraux (ce qui n'existe pas dans les bibliothèques de modèles) :
## téléphones des amis, ordinateur portable, bougies, ballons, gobelets.
## Chaque accessoire a son origine au point de contact avec la surface (pour HouseBuilder.settle()).


## Téléphone posé à plat, écran vers le haut. L'écran (éteint au départ) affiche `screen_tex`
## quand on monte son émission ; matériau accessible via get_meta("screen").
static func phone(parent: Node, pos: Vector3, rot_y_deg: float, case_color := Color(0.04, 0.04, 0.05), screen_tex := "") -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	n.position = pos
	n.rotation_degrees.y = rot_y_deg
	B.box(n, Vector3(0.074, 0.009, 0.155), Vector3(0, 0.0045, 0), B.color_mat(case_color, 0.35, 0.3), false)
	for sx in [-1.0, 1.0]:
		var edge := B.cylinder(n, 0.0045, 0.0045, 0.155, Vector3(sx * 0.037, 0.0045, 0), B.color_mat(case_color.lightened(0.15), 0.3, 0.7), false, 8, Vector3(90, 0, 0))
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var screen_mat := StandardMaterial3D.new()
	# verre noir brillant : reflets nets (pas de voile gris), l'image vient de l'émission
	screen_mat.albedo_color = Color(0.004, 0.004, 0.005)
	screen_mat.roughness = 0.25
	screen_mat.metallic_specular = 0.2
	screen_mat.emission_enabled = true
	# couleur d'émission NOIRE : Godot ADDITIONNE couleur et image (blanc + image = écran gris délavé)
	screen_mat.emission = Color.BLACK
	if screen_tex != "":
		screen_mat.emission_texture = load(screen_tex)
	screen_mat.emission_energy_multiplier = 0.0
	var scr := B.quad(n, Vector2(0.068, 0.145), Vector3(0, 0.0092, 0), screen_mat, Vector3(-90, 0, 0))
	scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.set_meta("screen", screen_mat)
	return n


## Ordinateur portable ouvert (écran face +Z). Renvoie l'écran (MeshInstance3D).
static func laptop(parent: Node, pos: Vector3, rot_y_deg: float, screen_mat: Material) -> MeshInstance3D:
	var n := Node3D.new()
	parent.add_child(n)
	n.position = pos
	n.rotation_degrees.y = rot_y_deg
	var alu := B.color_mat(Color(0.35, 0.36, 0.38), 0.35, 0.8)
	B.box(n, Vector3(0.34, 0.018, 0.24), Vector3(0, 0.009, 0), alu, false)
	B.box(n, Vector3(0.3, 0.004, 0.1), Vector3(0, 0.019, 0.02), B.color_mat(Color(0.05, 0.05, 0.05), 0.6), false)
	var lid := Node3D.new()
	n.add_child(lid)
	lid.position = Vector3(0, 0.018, -0.12)
	lid.rotation_degrees.x = -15
	B.box(lid, Vector3(0.34, 0.23, 0.01), Vector3(0, 0.115, -0.005), alu, false)
	return SecurityFeed.screen(lid, Vector2(0.31, 0.2), Vector3(0, 0.115, 0.001), Vector3.ZERO, screen_mat)


static func candle(parent: Node, pos: Vector3) -> void:
	B.cylinder(parent, 0.006, 0.006, 0.07, pos + Vector3(0, 0.035, 0), B.color_mat(Color(0.9, 0.85, 0.7), 0.6), false, 6)
	var flame := B.sphere(parent, 0.008, pos + Vector3(0, 0.082, 0), B.emissive(Color(1.0, 0.65, 0.25), 8.0, true), 6)
	flame.scale = Vector3(1, 1.8, 1)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func balloon(parent: Node, pos: Vector3, color: Color) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.15
	m.clearcoat_enabled = true
	var b := B.sphere(parent, 0.14, pos, m, 16)
	b.scale = Vector3(1, 1.18, 1)
	B.cylinder(parent, 0.0015, 0.0015, 0.7, pos + Vector3(0, -0.5, 0), B.color_mat(Color(0.55, 0.55, 0.55), 0.8), false, 4)


## Gobelet de fête rouge (debout, ou renversé sur le côté).
static func red_cup(parent: Node, pos: Vector3, tipped := false) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	n.position = pos
	var red := B.color_mat(Color(0.75, 0.05, 0.06), 0.4)
	var c := B.cylinder(n, 0.045, 0.032, 0.11, Vector3(0, 0.055, 0), red, false, 14)
	var rim := B.cylinder(n, 0.047, 0.047, 0.006, Vector3(0, 0.108, 0), B.color_mat(Color(0.95, 0.95, 0.95), 0.4), false, 14)
	if tipped:
		var yaw := randf() * TAU
		for part in [c, rim]:
			var mi := part as MeshInstance3D
			var local := mi.position
			mi.rotation = Vector3(PI * 0.5, 0, 0)
			mi.position = Vector3(0, 0.042, local.y - 0.055)
		n.rotation.y = yaw
	return n


## Toile d'araignée qui pend du plafond (ou d'un tuyau) : des fils souples et un lambeau de nappe, sur deux plans
## en croix. Origine en bas, haut de la toile au plafond (l'éditeur la suspend sous la surface visée).
static func cobweb(parent: Node) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.48
	var hw := 0.12
	var base := 0
	for ang in [0.0, PI * 0.5]:
		var ax := Vector3(cos(ang), 0, sin(ang))
		for iv in 7:
			var v := float(iv) / 6.0
			for iu in 2:
				# COLOR.r : plus on descend, plus le fil est libre de se balancer
				st.set_color(Color(v, 0, 0))
				st.set_uv(Vector2(iu, v))
				st.add_vertex(ax * (iu * 2.0 - 1.0) * hw + Vector3(0, h * (1.0 - v), 0))
		for iv in 6:
			var i0 := base + iv * 2
			st.add_index(i0)
			st.add_index(i0 + 1)
			st.add_index(i0 + 2)
			st.add_index(i0 + 1)
			st.add_index(i0 + 3)
			st.add_index(i0 + 2)
		base += 14
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _cobweb_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 22.0
	n.add_child(mi)
	n.set_meta("size", Vector3(hw * 2.0, h, hw * 2.0))
	return n


static var _web_mat: ShaderMaterial = null


static func _cobweb_mat() -> ShaderMaterial:
	if _web_mat == null:
		_web_mat = ShaderMaterial.new()
		_web_mat.shader = load("res://shaders/cobweb.gdshader")
		_web_mat.set_shader_parameter("web_tex", load("res://assets/gen/cobweb_strands.png"))
		_web_mat.set_shader_parameter("sway_hang", 0.03)
	return _web_mat
