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


## Toile d'araignée (« corner » : coin deux murs + plafond, « edge » : arête mur / plafond, « strands » : fils
## qui pendent). Origine en bas, contre le mur (comme les appliques) : mur du fond = plan z = 0 (+Z vers la pièce),
## plafond en haut de la toile. Pour « corner », le second mur est le plan x = 0 (pièce vers +X).
static func cobweb(parent: Node, kind: String) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var size := Vector3.ONE
	match kind:
		"corner":
			# triangle tendu en travers du coin : B et A accrochés au plafond, C dans l'angle des murs
			# (un peu en avant : les angles des égouts sont arrondis) ; la nappe pend un peu vers la pièce
			# (en hamac), ses bords restent collés aux parois
			var a := 0.48
			var c := 0.42
			var A := Vector3(a, c, 0)
			var Bp := Vector3(0, c, a)
			var C := Vector3(0.13, 0, 0.13)
			var G := (A + Bp + C) / 3.0
			var bulge := ((G - Vector3(0, c, 0)).normalized() + Vector3(0, -0.6, 0)).normalized()
			var N := 8
			var idx := {}
			var k := 0
			for i in N + 1:
				for j in N - i + 1:
					var s := float(i) / N
					var t := 0.0 if i == N else float(j) / (N - i)
					var la := (1.0 - s) * t
					var lb := (1.0 - s) * (1.0 - t)
					var w := clampf(27.0 * la * lb * s, 0.0, 1.0)
					st.set_color(Color(w, 0, 0))
					st.set_uv(Vector2(t, 0).lerp(Vector2(0.5, 1.0), s))
					st.add_vertex(Bp.lerp(A, t).lerp(C, s) + bulge * 0.07 * w)
					idx[Vector2i(i, j)] = k
					k += 1
			for i in N:
				for j in N - i:
					st.add_index(idx[Vector2i(i, j)])
					st.add_index(idx[Vector2i(i, j + 1)])
					st.add_index(idx[Vector2i(i + 1, j)])
					if j < N - i - 1:
						st.add_index(idx[Vector2i(i, j + 1)])
						st.add_index(idx[Vector2i(i + 1, j + 1)])
						st.add_index(idx[Vector2i(i + 1, j)])
			size = Vector3(a, c, a)
		"edge":
			# nappe le long de l'arête : haut au plafond (à d du mur), bas sur le mur (d sous le plafond)
			var L := 0.95
			var d := 0.3
			var U := 12
			var V := 5
			for iv in V + 1:
				for iu in U + 1:
					var u := float(iu) / U
					var v := float(iv) / V
					var w := sin(PI * v) * pow(sin(PI * u), 0.6)
					st.set_color(Color(w, 0, 0))
					st.set_uv(Vector2(u, v))
					var x := (u - 0.5) * L
					st.add_vertex(Vector3(x, d, d).lerp(Vector3(x, 0, 0), v) + Vector3(0, -0.7, 0.7) * 0.05 * w)
			for iv in V:
				for iu in U:
					var i0 := iv * (U + 1) + iu
					st.add_index(i0)
					st.add_index(i0 + 1)
					st.add_index(i0 + U + 1)
					st.add_index(i0 + 1)
					st.add_index(i0 + U + 2)
					st.add_index(i0 + U + 1)
			size = Vector3(L, d, d)
		_:
			# fils pendants : deux plans en croix, accrochés en haut ; le bas se balance
			var h := 0.48
			var hw := 0.12
			var base := 0
			for ang in [0.0, PI * 0.5]:
				var ax := Vector3(cos(ang), 0, sin(ang))
				for iv in 7:
					var v := float(iv) / 6.0
					for iu in 2:
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
			size = Vector3(hw * 2.0, h, hw * 2.0)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _cobweb_mat(kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 22.0
	n.add_child(mi)
	n.set_meta("size", size)
	return n


static var _web_mats := {}


static func _cobweb_mat(kind: String) -> ShaderMaterial:
	if _web_mats.has(kind):
		return _web_mats[kind]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/cobweb.gdshader")
	m.set_shader_parameter("web_tex", load("res://assets/gen/cobweb_%s.png" % kind))
	m.set_shader_parameter("sway", 0.0 if kind == "strands" else 0.012)
	m.set_shader_parameter("sway_hang", 0.03 if kind == "strands" else 0.0)
	_web_mats[kind] = m
	return m
