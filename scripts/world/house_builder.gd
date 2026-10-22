class_name HouseBuilder
extends Node3D
## La maison de Max : architecture (murs, plinthes, encadrements, fenêtres, rideaux,
## radiateurs, toit, perron), mobilier réaliste (Poly Haven / Sketchfab), lumières
## et caméras de surveillance. Repère local : la façade (porte d'entrée) regarde +Z.
## Toute la partie intérieure est sous `inside`, surélevée de FLOOR_Y.

const HH := 2.6
const FLOOR_Y := 0.36
const WT := 0.14

var inside: Node3D
var room_lights: Array[Light3D] = []
var lamp_glows: Array[GeometryInstance3D] = []
var window_glows: Array[MeshInstance3D] = []
var cams: Array[SecurityCamera] = []
var cam_rooms := {}
var feed: SecurityFeed
var office_cam: SecurityCamera
var front_door: Node3D
var front_door_body: StaticBody3D
var tv_material: ShaderMaterial
var tv_light: OmniLight3D
var office_door: Node3D
var office_door_body: StaticBody3D
var boombox: Node3D
var phones: Array[Node3D] = []
var rocking_chair: Node3D
var callbacks := {}  ## nom → Callable (interactions fournies par le niveau)
var _mats := {}
var _resting: Array[Node3D] = []
var _supports: Array[Node3D] = []
var use_layout := false  ## une disposition personnalisée existe (éditeur de carte)
var _layout: Variant = null


func build() -> void:
	_layout = MapLayout.load_entries("maison")
	use_layout = _layout != null
	inside = Node3D.new()
	inside.name = "Inside"
	add_child(inside)
	inside.position.y = FLOOR_Y
	_materials()
	_shell()
	_exterior()
	_living()
	_kitchen()
	_bedroom()
	_bathroom()
	_office()
	_cameras()
	if use_layout:
		MapLayout.spawn(_layout, self)
	MapLayout.apply_cams("maison", self)
	# objets de l'histoire déplacés dans l'éditeur : posés exactement où le joueur les a mis
	for n in MapLayout.apply_objs("maison", self):
		_resting.erase(n)
	settle()


# ================================================================== matériaux
func _mat_tex(path: String, tile: float, tint := Color.WHITE, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.albedo_color = tint
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _materials() -> void:
	_mats["salon"] = _mat_tex("res://assets/gen/wallpaper_living.png", 1.1, Color(0.95, 0.92, 0.88))
	_mats["chambre"] = _mat_tex("res://assets/gen/wallpaper_bedroom.png", 1.1)
	_mats["cuisine"] = B.mat("beige_wall_001", 1.6, {"color": Color(0.92, 0.9, 0.85)})
	_mats["sdb"] = B.mat("long_white_tiles", 1.0, {"roughness": 0.35})
	_mats["bureau"] = B.mat("painted_plaster_wall", 1.8, {"color": Color(0.55, 0.6, 0.56)})
	_mats["dehors"] = B.mat("weathered_plank_siding", 2.2, {"color": Color(0.78, 0.8, 0.82)})
	_mats["trim"] = B.color_mat(Color(0.9, 0.88, 0.84), 0.45)
	_mats["trim_dark"] = B.color_mat(Color(0.18, 0.16, 0.15), 0.5)
	_mats["ceiling"] = B.mat("white_plaster_02", 2.0, {"color": Color(0.9, 0.89, 0.86)})
	var dw := StandardMaterial3D.new()
	dw.albedo_texture = load("res://assets/gen/door_white.png")
	dw.normal_enabled = true
	dw.normal_texture = load("res://assets/gen/door_white_nrm.png")
	dw.roughness = 0.5
	_mats["door_white"] = dw
	var dd := dw.duplicate() as StandardMaterial3D
	dd.albedo_texture = load("res://assets/gen/door_wood.png")
	dd.normal_texture = load("res://assets/gen/door_wood_nrm.png")
	dd.roughness = 0.6
	_mats["door_wood"] = dd


func room_of(p: Vector3) -> String:
	if absf(p.x) > 8.0 or absf(p.z) > 6.0:
		return "dehors"
	if p.z > -1.0:
		return "salon" if p.x < 1.0 else "cuisine"
	if p.x < -2.0:
		return "chambre"
	if p.x < 2.0:
		return "sdb"
	return "bureau"


# ================================================================== murs
## Mur aligné sur un axe (coordonnées de `inside`). Ouvertures : [{a, b, bottom, top}].
## Chaque face reçoit le revêtement de la pièce qu'elle regarde ; plinthes et encadrements inclus.
func wall(p1: Vector2, p2: Vector2, openings: Array = [], thick := WT) -> void:
	var along_x := absf(p2.y - p1.y) < 0.001
	var start := minf(p1.x, p2.x) if along_x else minf(p1.y, p2.y)
	var end := maxf(p1.x, p2.x) if along_x else maxf(p1.y, p2.y)
	var fixed := p1.y if along_x else p1.x
	var n := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var pieces: Array = []
	var cursor := start
	var ops := openings.duplicate()
	ops.sort_custom(func(u: Dictionary, v: Dictionary) -> bool: return u["a"] < v["a"])
	for o in ops:
		if o["a"] > cursor:
			pieces.append([cursor, o["a"], 0.0, HH])
		if o.get("bottom", 0.0) > 0.0:
			pieces.append([o["a"], o["b"], 0.0, o["bottom"]])
		if o["top"] < HH:
			pieces.append([o["a"], o["b"], o["top"], HH])
		cursor = o["b"]
	if cursor < end:
		pieces.append([cursor, end, 0.0, HH])
	var body := StaticBody3D.new()
	inside.add_child(body)
	for pc in pieces:
		var length: float = pc[1] - pc[0]
		var h: float = pc[3] - pc[2]
		var mid: float = (pc[0] + pc[1]) * 0.5
		var cy: float = (pc[2] + pc[3]) * 0.5
		var size := Vector3(length, h, thick) if along_x else Vector3(thick, h, length)
		var pos := Vector3(mid, cy, fixed) if along_x else Vector3(fixed, cy, mid)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		body.add_child(cs)
		for sgn in [-1.0, 1.0]:
			var room := room_of(pos + n * sgn * (thick * 0.5 + 0.3))
			var half := size
			if along_x:
				half.z = thick * 0.5
			else:
				half.x = thick * 0.5
			var face := B.box(inside, half, pos + n * sgn * thick * 0.25, _mats[room], false)
			face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if room != "dehors" and pc[2] == 0.0:
				var bb := Vector3(length, 0.1, 0.018) if along_x else Vector3(0.018, 0.1, length)
				B.box(inside, bb, Vector3(pos.x, 0.05, pos.z) + n * sgn * (thick * 0.5 + 0.009), _mats["trim"], false)
	# encadrements
	for o in ops:
		var a: float = o["a"]
		var b: float = o["b"]
		var bottom: float = o.get("bottom", 0.0)
		var top: float = o["top"]
		for sgn in [-1.0, 1.0]:
			var c := Vector3((a + b) * 0.5, 0, fixed) if along_x else Vector3(fixed, 0, (a + b) * 0.5)
			var room := room_of(c + n * sgn * 0.4)
			var tm: Material = _mats["trim"]
			var off: Vector3 = n * sgn * (thick * 0.5 + 0.012)
			var w := b - a
			var horiz := func(y: float, ext: float, hgt: float) -> void:
				var s := Vector3(w + ext, hgt, 0.024) if along_x else Vector3(0.024, hgt, w + ext)
				B.box(inside, s, Vector3(c.x, y, c.z) + off, tm, false)
			var vert := func(t: float) -> void:
				var p := Vector3(t, (bottom + top) * 0.5, fixed) if along_x else Vector3(fixed, (bottom + top) * 0.5, t)
				var s := Vector3(0.07, top - bottom + 0.07, 0.024) if along_x else Vector3(0.024, top - bottom + 0.07, 0.07)
				B.box(inside, s, p + off, tm, false)
			if room == "dehors":
				tm = _mats["trim"]
			vert.call(a - 0.035)
			vert.call(b + 0.035)
			horiz.call(top + 0.035, 0.14, 0.07)
			if bottom > 0.0:
				# appui de fenêtre
				var ss := Vector3(w + 0.16, 0.035, 0.12) if along_x else Vector3(0.12, 0.035, w + 0.16)
				B.box(inside, ss, Vector3(c.x, bottom - 0.02, c.z) + n * sgn * (thick * 0.5 + 0.05), tm, false)


func window(center: Vector3, width: float, height: float, normal: Vector3, curtains := true, radiator := true) -> void:
	var horizontal := absf(normal.z) > 0.5
	var g := B.box(inside, Vector3(width, height, 0.02) if horizontal else Vector3(0.02, height, width), center, B.glass(Color(0.03, 0.035, 0.045, 0.5), 0.03), false)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fw := 0.05
	for dy in [-height * 0.5, height * 0.5, 0.0]:
		B.box(inside, Vector3(width, fw, 0.07) if horizontal else Vector3(0.07, fw, width), center + Vector3(0, dy, 0), _mats["trim"], false)
	for dx in [-width * 0.5, width * 0.5, 0.0]:
		B.box(inside, Vector3(fw, height, 0.07) if horizontal else Vector3(0.07, height, fw), center + (Vector3(dx, 0, 0) if horizontal else Vector3(0, 0, dx)), _mats["trim"], false)
	var rot := Vector3(0, rad_to_deg(atan2(normal.x, normal.z)), 0)
	# halo très léger côté extérieur (l'intérieur éclairé se voit à travers la vitre)
	var glow := B.quad(inside, Vector2(width - 0.08, height - 0.08), center + normal * 0.04, B.emissive(Color(1.0, 0.72, 0.42), 0.25), rot)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(glow.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	(glow.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.72, 0.42, 0.1)
	window_glows.append(glow)
	var inward := -normal
	if curtains:
		var fabric := B.mat("fabric_pattern_07", 0.5, {"color": Color(0.55, 0.42, 0.33), "triplanar": true, "world": false})
		for side in [-1.0, 1.0]:
			var along := Vector3(1, 0, 0) if horizontal else Vector3(0, 0, 1)
			var cpos: Vector3 = center + along * side * (width * 0.5 + 0.12) + inward * 0.16
			cpos.y = (center.y + height * 0.5 + 0.25 + 0.05) * 0.5 + 0.0
			var curtain := _curtain_mesh(0.55, center.y + height * 0.5 + 0.25 - 0.05)
			var mi := MeshInstance3D.new()
			mi.mesh = curtain
			mi.material_override = fabric
			inside.add_child(mi)
			mi.position = Vector3(cpos.x, 0.05, cpos.z)
			mi.rotation.y = atan2(normal.x, normal.z)
		# tringle
		var rod_len := width + 1.4
		var rod := B.cylinder(inside, 0.012, 0.012, rod_len, center + inward * 0.16 + Vector3(0, height * 0.5 + 0.24, 0), B.color_mat(Color(0.2, 0.18, 0.16), 0.4, 0.8), false, 8, Vector3(0, 0, 90) if horizontal else Vector3(90, 0, 0))
		rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if radiator:
		_radiator(Vector3(center.x, 0.0, center.z) + inward * 0.12, minf(width, 1.2), normal)


## Rideau plissé (maillage ondulé), largeur w, hauteur h, posé au sol (repère local, face +Z).
func _curtain_mesh(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 22
	var rows := 6
	for r in rows:
		for c in cols:
			var pts := []
			for k in [[c, r], [c + 1, r], [c + 1, r + 1], [c, r + 1]]:
				var u := float(k[0]) / cols
				var v := float(k[1]) / rows
				var x := (u - 0.5) * w
				var z := sin(u * TAU * 5.0) * 0.035 * (0.6 + 0.4 * v)
				pts.append([Vector3(x, v * h, z), Vector2(u * 3.0, v * 4.0)])
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_uv(pts[idx][1])
				st.add_vertex(pts[idx][0])
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


func _radiator(base: Vector3, width: float, normal: Vector3) -> void:
	var horizontal := absf(normal.z) > 0.5
	var mat := B.color_mat(Color(0.88, 0.87, 0.84), 0.35, 0.3)
	var fins := int(width / 0.06)
	for i in fins:
		var t := (i - fins * 0.5) * 0.06
		var off := Vector3(t, 0, 0) if horizontal else Vector3(0, 0, t)
		B.box(inside, Vector3(0.045, 0.55, 0.07) if horizontal else Vector3(0.07, 0.55, 0.045), base + off + Vector3(0, 0.42, 0), mat, false)
	B.cylinder(inside, 0.012, 0.012, 0.15, base + Vector3(0, 0.1, 0) + (Vector3(width * 0.5, 0, 0) if horizontal else Vector3(0, 0, width * 0.5)), B.color_mat(Color(0.7, 0.68, 0.62), 0.3, 0.9), false, 8)


func switch_plate(pos: Vector3, normal: Vector3) -> void:
	var rot := Vector3(0, rad_to_deg(atan2(normal.x, normal.z)), 0)
	var p := B.box(inside, Vector3(0.08, 0.08, 0.012), pos, _mats["trim"], false, rot)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	B.box(inside, Vector3(0.025, 0.035, 0.01), pos + normal * 0.008, B.color_mat(Color(0.95, 0.94, 0.9), 0.3), false, rot)


## Porte à panneaux (feuille + poignées) pivotant autour de `hinge`.
func door_leaf(hinge: Vector3, width: float, along: Vector3, open_deg: float, mat_name := "door_white") -> Node3D:
	var pivot := Node3D.new()
	inside.add_child(pivot)
	pivot.position = hinge
	pivot.rotation_degrees.y = rad_to_deg(atan2(-along.z, along.x))
	var leaf := Node3D.new()
	pivot.add_child(leaf)
	var h := 2.05
	B.box(leaf, Vector3(width, h, 0.04), Vector3(width * 0.5, h * 0.5, 0), _mats["trim"], false)
	for sgn in [-1.0, 1.0]:
		var q := B.quad(leaf, Vector2(width - 0.004, h - 0.004), Vector3(width * 0.5, h * 0.5, 0.0205 * sgn), _mats[mat_name], Vector3(0, 0 if sgn > 0 else 180, 0))
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var brass := B.color_mat(Color(0.75, 0.62, 0.38), 0.25, 1.0)
		B.box(leaf, Vector3(0.05, 0.16, 0.012), Vector3(width - 0.08, 1.0, 0.026 * sgn), brass, false)
		B.cylinder(leaf, 0.011, 0.011, 0.11, Vector3(width - 0.13, 1.02, 0.045 * sgn), brass, false, 8, Vector3(0, 0, 90))
	pivot.set_meta("leaf", leaf)
	set_door_angle(pivot, open_deg)
	return pivot


func set_door_angle(pivot: Node3D, deg: float) -> void:
	(pivot.get_meta("leaf") as Node3D).rotation_degrees.y = deg


func swing_door(pivot: Node3D, deg: float, duration: float) -> void:
	var leaf := pivot.get_meta("leaf") as Node3D
	var tw := create_tween()
	tw.tween_property(leaf, "rotation_degrees:y", deg, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func blocker(center: Vector3, size: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	inside.add_child(sb)
	sb.position = center
	return sb


func put(slug: String, pos: Vector3, yaw := 0.0, fit := {}) -> Node3D:
	return B.model(inside, slug, pos, yaw, fit)


func put_into(parent: Node3D, slug: String, pos: Vector3, yaw := 0.0, fit := {}) -> Node3D:
	return B.model(parent, slug, pos, yaw, fit)


## Petit objet posé sur un meuble : il sera « reposé » sur la surface réelle par settle().
func put_on(slug: String, pos: Vector3, yaw := 0.0, fit := {}) -> Node3D:
	return rest(put(slug, pos, yaw, fit))


## Objet de décor, déplaçable avec l'éditeur de carte (F8). Si le joueur a sauvegardé
## sa propre disposition, le code ne le pose pas : il est recréé depuis le fichier.
func deco(slug: String, pos: Vector3, yaw := 0.0, fit := {}, parent: Node3D = null) -> Node3D:
	if use_layout:
		return null
	var n := B.model(parent if parent != null else inside, slug, pos, yaw, fit)
	n.set_meta("decor", true)
	return n


func deco_on(slug: String, pos: Vector3, yaw := 0.0, fit := {}) -> Node3D:
	return rest(deco(slug, pos, yaw, fit))


func deco_cup(pos: Vector3, tipped := false) -> void:
	if use_layout:
		return
	var c := Props.red_cup(inside, pos, tipped)
	c.set_meta("decor", true)
	c.set_meta("spec", {"model": "proc:red_cup_tipped" if tipped else "proc:red_cup"})
	c.set_meta("size", Vector3(0.1, 0.12, 0.1))
	rest(c)


func rest(n: Node3D) -> Node3D:
	if n != null:
		_resting.append(n)
	return n


## Meuble dont la surface sert d'appui aux petits objets (tables, étagères, plans de travail...).
func support(n: Node3D) -> Node3D:
	if n != null:
		_supports.append(n)
	return n


## Pose chaque petit objet sur la surface réellement sous lui (lancer de rayon sur la géométrie
## exacte des meubles) : plus aucun objet ne flotte ni ne s'enfonce.
func settle() -> void:
	const LAYER := 1 << 19
	var body := StaticBody3D.new()
	body.collision_layer = LAYER
	body.collision_mask = 0
	add_child(body)
	for sup in _supports:
		for mi in sup.find_children("*", "MeshInstance3D", true, false) + ([sup] if sup is MeshInstance3D else []):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var cs := CollisionShape3D.new()
			cs.shape = m.mesh.create_trimesh_shape()
			body.add_child(cs)
			cs.global_transform = m.global_transform
	# le sol de la maison
	var fl := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(16.2, 0.2, 12.2)
	fl.shape = bs
	body.add_child(fl)
	fl.global_transform = inside.global_transform * Transform3D(Basis(), Vector3(0, -0.1, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var up := inside.global_basis.y
	for n in _resting:
		if not is_instance_valid(n):
			continue
		var p := n.global_position
		var q := PhysicsRayQueryParameters3D.create(p + up * 0.16, p - up * 0.6, LAYER)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			n.global_position = hit["position"] + up * 0.002
	body.queue_free()


func ceiling_light(pos: Vector3, energy := 1.0, light_range := 7.0, shadow := false) -> OmniLight3D:
	# l'abat-jour ne projette pas d'ombre : sinon l'ampoule dessous dessinait un grand disque noir au plafond
	B.set_shadows(put("modern_ceiling_lamp_01", Vector3(pos.x, HH - 0.95, pos.z), 0.0, {"center": false}), false)
	var glow := B.sphere(inside, 0.06, Vector3(pos.x, HH - 0.62, pos.z), B.emissive(Color(1.0, 0.85, 0.65), 1.6), 10)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamp_glows.append(glow)
	var l := B.omni(inside, Vector3(pos.x, HH - 0.78, pos.z), Color(1.0, 0.78, 0.55), energy, light_range, shadow)
	l.light_volumetric_fog_energy = 0.25
	room_lights.append(l)
	return l


# ================================================================== coque
func _shell() -> void:
	# dalle (avec collision) et sols par pièce
	var slab := B.box(self, Vector3(16.3, FLOOR_Y, 12.3), Vector3(0, FLOOR_Y * 0.5, 0), B.mat("brushed_concrete", 2.0, {"color": Color(0.6, 0.6, 0.58)}), true)
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var wood := B.mat("wood_floor", 1.8, {"color": Color(0.85, 0.78, 0.7)})
	var worn := B.mat("wood_floor_worn", 1.8)
	var tiles := B.mat("interior_tiles", 1.2, {"roughness": 0.35})
	for f in [[Vector3(-3.5, 0, 2.5), Vector3(9, 0, 7), wood], [Vector3(4.5, 0, 2.5), Vector3(7, 0, 7), tiles],
			[Vector3(-5, 0, -3.5), Vector3(6, 0, 5), wood], [Vector3(0, 0, -3.5), Vector3(4, 0, 5), tiles], [Vector3(5, 0, -3.5), Vector3(6, 0, 5), worn]]:
		var fb := B.box(inside, Vector3(f[1].x, 0.012, f[1].z), Vector3(f[0].x, 0.006, f[0].z), f[2], false)
		fb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	B.box(inside, Vector3(16.3, 0.1, 12.3), Vector3(0, HH + 0.05, 0), _mats["ceiling"], false)
	# murs extérieurs
	wall(Vector2(-8.07, 6), Vector2(8.07, 6), [
		{"a": -7.0, "b": -5.2, "bottom": 0.9, "top": 2.1},
		{"a": -3.0, "b": -2.0, "top": 2.1},
		{"a": 4.0, "b": 5.8, "bottom": 1.0, "top": 2.1},
	], 0.22)
	wall(Vector2(-8.07, -6), Vector2(8.07, -6), [
		{"a": -0.5, "b": 0.5, "bottom": 1.5, "top": 2.1},
	], 0.22)
	wall(Vector2(-8, -6), Vector2(-8, 6), [
		{"a": -4.5, "b": -2.8, "bottom": 0.9, "top": 2.1},
		{"a": 1.0, "b": 3.0, "bottom": 0.9, "top": 2.1},
	], 0.22)
	wall(Vector2(8, -6), Vector2(8, 6), [
		{"a": -4.5, "b": -3.0, "bottom": 0.9, "top": 2.1},
		{"a": 0.0, "b": 0.95, "top": 2.1},
	], 0.22)
	window(Vector3(-6.1, 1.5, 6.0), 1.8, 1.2, Vector3(0, 0, 1))
	window(Vector3(4.9, 1.55, 6.0), 1.8, 1.1, Vector3(0, 0, 1), false, false)
	window(Vector3(0.0, 1.8, -6.0), 1.0, 0.6, Vector3(0, 0, -1), false, false)
	window(Vector3(-8.0, 1.5, -3.65), 1.7, 1.2, Vector3(-1, 0, 0))
	window(Vector3(-8.0, 1.5, 2.0), 2.0, 1.2, Vector3(-1, 0, 0))
	window(Vector3(8.0, 1.5, -3.75), 1.5, 1.2, Vector3(1, 0, 0), true, false)
	# cloisons
	wall(Vector2(-8, -1), Vector2(8, -1), [
		{"a": -4.5, "b": -3.6, "top": 2.08},
		{"a": -1.2, "b": -0.3, "top": 2.08},
		{"a": 4.6, "b": 5.5, "top": 2.08},
	])
	wall(Vector2(1, -1), Vector2(1, 6), [{"a": 0.6, "b": 3.4, "top": 2.3}])
	wall(Vector2(-2, -6), Vector2(-2, -1))
	wall(Vector2(2, -6), Vector2(2, -1))
	# interrupteurs
	switch_plate(Vector3(-3.25, 1.1, 5.92), Vector3(0, 0, -1))
	switch_plate(Vector3(-4.65, 1.1, -1.08), Vector3(0, 0, -1))
	switch_plate(Vector3(4.45, 1.1, -0.92), Vector3(0, 0, 1))
	switch_plate(Vector3(0.92, 1.1, 3.6), Vector3(-1, 0, 0))
	# portes
	front_door = door_leaf(Vector3(-3.0, 0, 6.0), 1.0, Vector3(1, 0, 0), 18.0, "door_wood")
	front_door_body = blocker(Vector3(-2.5, 1.05, 6.0), Vector3(1.0, 2.1, 0.2))
	door_leaf(Vector3(-4.5, 0, -1.0), 0.9, Vector3(1, 0, 0), 78.0)
	door_leaf(Vector3(-1.2, 0, -1.0), 0.9, Vector3(1, 0, 0), 62.0)
	door_leaf(Vector3(8.0, 0, 0.0), 0.95, Vector3(0, 0, 1), 0.0, "door_wood")
	office_door = door_leaf(Vector3(4.6, 0, -1.0), 0.9, Vector3(1, 0, 0), 0.0)
	office_door_body = blocker(Vector3(5.05, 1.05, -1.0), Vector3(0.9, 2.1, 0.2))


func _exterior() -> void:
	var siding: Material = _mats["dehors"]
	# soubassement
	var found := B.mat("brushed_concrete", 1.5, {"color": Color(0.55, 0.55, 0.53)})
	for f in [[Vector3(0, FLOOR_Y * 0.5, 6.13), Vector3(16.5, FLOOR_Y, 0.06)], [Vector3(0, FLOOR_Y * 0.5, -6.13), Vector3(16.5, FLOOR_Y, 0.06)],
			[Vector3(-8.13, FLOOR_Y * 0.5, 0), Vector3(0.06, FLOOR_Y, 12.3)], [Vector3(8.13, FLOOR_Y * 0.5, 0), Vector3(0.06, FLOOR_Y, 12.3)]]:
		B.box(self, f[1], f[0], found, false)
	# planches d'angle
	for c in [Vector2(-8.1, 6.1), Vector2(8.1, 6.1), Vector2(-8.1, -6.1), Vector2(8.1, -6.1)]:
		B.box(self, Vector3(0.14, HH + 0.1, 0.14), Vector3(c.x, FLOOR_Y + HH * 0.5, c.y), _mats["trim"], false)
	# toit à deux pans avec débord
	var roof := B.mat("grey_roof_tiles", 1.6, {"color": Color(0.55, 0.55, 0.56)})
	var rise := 2.3
	var run := 6.9
	var ang := rad_to_deg(atan2(rise, run))
	var slab_len := sqrt(run * run + rise * rise)
	var base_y := FLOOR_Y + HH + 0.12
	B.box(self, Vector3(17.4, 0.14, slab_len), Vector3(0, base_y + rise * 0.5, run * 0.5 - 0.05), roof, false, Vector3(ang, 0, 0))
	B.box(self, Vector3(17.4, 0.14, slab_len), Vector3(0, base_y + rise * 0.5, -run * 0.5 + 0.05), roof, false, Vector3(-ang, 0, 0))
	for sx in [-8.0, 8.0]:
		var gable := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(12.4, rise, 0.2)
		gable.mesh = pm
		gable.material_override = siding
		add_child(gable)
		gable.position = Vector3(sx, base_y + rise * 0.5 - 0.05, 0)
		gable.rotation_degrees.y = 90
	# bandeaux de rive + gouttières
	for sz in [-1.0, 1.0]:
		B.box(self, Vector3(17.4, 0.2, 0.04), Vector3(0, base_y - 0.02, sz * 6.92), _mats["trim"], false)
		B.cylinder(self, 0.06, 0.06, 17.4, Vector3(0, base_y - 0.08, sz * 7.0), B.color_mat(Color(0.5, 0.5, 0.5), 0.4, 0.8), false, 10, Vector3(0, 0, 90))
	# cheminée
	B.box(self, Vector3(0.8, 2.6, 0.8), Vector3(-5.5, base_y + 1.6, -2.0), B.mat("red_brick", 1.0, {"color": Color(0.7, 0.6, 0.55)}) if ResourceLoader.exists("res://assets/textures/red_brick") else B.mat("dark_brick_wall", 1.0), false)
	# perron : terrasse, marches, poteaux, garde-corps, auvent, applique
	var deck := B.mat("worn_planks", 1.2, {"color": Color(0.62, 0.55, 0.48)})
	B.box(self, Vector3(4.2, FLOOR_Y, 2.2), Vector3(-2.5, FLOOR_Y * 0.5, 7.2), deck, true)
	# trois marches basses (12 cm) et larges ; le pied les franchit via une rampe invisible
	for k in 2:
		var top := FLOOR_Y * (2 - k) / 3.0
		B.box(self, Vector3(2.0, top, 0.3), Vector3(-2.5, top * 0.5, 8.45 + k * 0.3), deck, false)
	var ramp := StaticBody3D.new()
	add_child(ramp)
	var rs := CollisionShape3D.new()
	var rb := BoxShape3D.new()
	var run_len := 0.62  # du bord de la terrasse (z = 8.3) au sol (z = 8.92)
	var slope := atan2(FLOOR_Y, run_len)
	rb.size = Vector3(2.0, 0.1, sqrt(run_len * run_len + FLOOR_Y * FLOOR_Y))
	rs.shape = rb
	ramp.add_child(rs)
	# plan supérieur de la boîte : de (z = 8.92, y = 0) à (z = 8.3, y = FLOOR_Y)
	var mid := Vector3(-2.5, FLOOR_Y * 0.5, 8.3 + run_len * 0.5)
	var up := Vector3(0, cos(slope), sin(slope))
	ramp.transform = Transform3D(Basis(Vector3.RIGHT, slope), mid - up * 0.05)
	var post := B.color_mat(Color(0.88, 0.86, 0.82), 0.5)
	for px in [-4.45, -0.55]:
		B.box(self, Vector3(0.12, 2.65, 0.12), Vector3(px, FLOOR_Y + 1.32, 8.2), post, true)
	B.box(self, Vector3(4.6, 0.12, 2.5), Vector3(-2.5, FLOOR_Y + 2.72, 7.15), roof, false, Vector3(-9, 0, 0))
	var lamp := B.model(self, "industrial_wall_lamp", Vector3(-3.55, FLOOR_Y + 2.0, 6.12), 0.0, {"center": false})
	lamp.name = "PorchLamp"
	var porch := B.omni(self, Vector3(-3.55, FLOOR_Y + 1.95, 6.55), Color(1.0, 0.72, 0.42), 0.7, 9.0, true)
	porch.light_size = 0.15
	porch.light_volumetric_fog_energy = 2.5
	room_lights.append(porch)
	# paillasson : épaisseur en fibre + motif imprimé sur le dessus (texture entière, non découpée)
	B.box(self, Vector3(0.9, 0.015, 0.6), Vector3(-2.5, FLOOR_Y + 0.0075, 6.55), B.color_mat(Color(0.3, 0.22, 0.13), 0.95), false)
	var mat_top := B.quad(self, Vector2(0.9, 0.6), Vector3(-2.5, FLOOR_Y + 0.0155, 6.55), B.textured("res://assets/gen/doormat.png"), Vector3(-90, 0, 0))
	mat_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deco("potted_plant_01", Vector3(-4.0, FLOOR_Y, 6.5), 30.0, {"height": 0.9}, self)
	deco("rubber_boots", Vector3(-1.4, FLOOR_Y, 6.45), 200.0, {"scale": 0.6}, self)
	deco("metal_trash_can", Vector3(8.6, 0, 4.5), -90.0, {"scale": 0.75, "collide": true}, self)
	deco("wooden_crate_01", Vector3(8.5, 0, 3.0), 80.0, {"collide": true}, self)


# ================================================================== pièces
func _living() -> void:
	ceiling_light(Vector3(-5.6, 0, 2.2), 1.0, 8.0, true)
	ceiling_light(Vector3(-1.6, 0, 3.6), 0.7, 6.0, false)
	support(deco("sofa_02", Vector3(-5.6, 0, 2.95), 180.0, {"width": 2.1, "collide": true}))
	support(deco("ArmChair_01", Vector3(-7.35, 0, 0.6), 90.0, {"collide": true}))
	support(deco("modern_arm_chair_01", Vector3(-3.5, 0, 1.1), -100.0, {"collide": true}))
	support(put("modern_coffee_table_01", Vector3(-5.6, 0, 1.25), 90.0, {"collide": true}))
	deco("sf:persian_rug", Vector3(-5.6, 0.013, 1.4), 90.0, {"width": 3.2})
	deco_on("throw_pillows_01", Vector3(-5.6, 0.5, 3.12), 180.0, {"width": 1.3})
	deco_on("gamepad", Vector3(-6.25, 0.5, 2.85), 160.0, {"width": 0.16})
	# meuble télé + télévision (retransmission en direct) + console de jeu
	var cab := B.mat("kitchen_wood", 1.0, {"color": Color(0.55, 0.42, 0.32)})
	support(B.box(inside, Vector3(1.8, 0.48, 0.42), Vector3(-5.6, 0.24, -0.68), cab, true))
	put("sf:flat_tv", Vector3(-5.6, 0.48, -0.72), -90.0, {"height": 0.72})
	deco_on("gaming_console", Vector3(-4.9, 0.5, -0.66), 0.0)
	deco_on("potted_plant_04", Vector3(-6.3, 0.5, -0.66), 30.0, {"height": 0.24})
	feed = SecurityFeed.new()
	add_child(feed)
	# 8 mm devant la dalle du modèle (sinon la vitre noire du téléviseur recouvre l'image)
	tv_material = feed.screen_material(0.0)
	tv_material.set_shader_parameter("power", 0.0)  # éteinte : elle s'allumera toute seule
	var tv_screen := SecurityFeed.screen(inside, Vector2(1.04, 0.58), Vector3(-5.6, 0.48 + 0.39, -0.72 + 0.03 + 0.008), Vector3.ZERO, tv_material)
	tv_screen.name = "TV"
	tv_light = B.omni(inside, Vector3(-5.6, 0.9, -0.2), Color(0.6, 0.8, 0.75), 0.25, 3.5)
	tv_light.set_meta("screen", true)
	tv_light.visible = false
	if callbacks.has("tv"):
		var it := Interactable.create(inside, Vector3(-5.6, 0.9, -0.5), Vector3(1.2, 0.8, 0.3), "Allumer la télé", callbacks["tv"])
		it.name = "TVUse"
	# bibliothèque : livres, bougeoirs, vase, pendule, photo de famille
	support(deco("sf:old_shelves", Vector3(-7.55, 0, 4.2), 90.0, {"part": "book shelf", "collide": true}))
	deco_on("book_encyclopedia_set_01", Vector3(-7.62, 1.2, 4.2), 90.0, {"width": 0.6})
	deco_on("ceramic_vase_02", Vector3(-7.62, 1.72, 3.8), 0.0, {"height": 0.3})
	deco_on("mantel_clock_01", Vector3(-7.62, 1.72, 4.55), 90.0, {"height": 0.25})
	deco_on("brass_candleholders", Vector3(-7.62, 0.75, 3.85), 90.0, {"part": "brass_candleholder_02", "height": 0.3})
	deco_on("standing_picture_frame_02", Vector3(-7.62, 0.75, 4.5), 120.0, {"height": 0.22})
	deco_on("sf:beer_bottle", Vector3(-7.6, 0.75, 4.25), 0.0, {"height": 0.24})
	var lamp := put("sf:floor_lamp", Vector3(-7.35, 0, 2.95), 0.0, {"height": 1.75})
	lamp.name = "FloorLamp"
	var fl := B.omni(inside, Vector3(-7.35, 1.55, 2.95), Color(1.0, 0.75, 0.48), 0.6, 4.5, false)
	room_lights.append(fl)
	deco("sf:monstera", Vector3(-7.3, 0, 5.4), 0.0, {"height": 1.3})
	support(put("side_table_01", Vector3(-3.95, 0, 2.95), 0.0, {"collide": true}))
	boombox = put_on("boombox", Vector3(-3.95, 0.6, 2.95), 200.0, {"scale": 0.75})
	rocking_chair = put("Rockingchair_01", Vector3(0.1, 0, 5.15), -140.0, {"collide": true})
	# murs : cadres, horloge
	deco("fancy_picture_frame_01", Vector3(-7.9, 1.6, 0.9), 90.0, {"center": false, "height": 0.6})
	deco("hanging_picture_frame_03", Vector3(-7.15, 1.35, -0.92), 0.0, {"center": false, "height": 0.5})
	deco("hanging_picture_frame_02", Vector3(-2.45, 1.3, -0.92), 0.0, {"center": false, "width": 0.75})
	deco("fancy_picture_frame_02", Vector3(0.92, 1.45, 4.7), -90.0, {"center": false, "height": 0.5})
	deco("wall_clock", Vector3(0.0, 2.0, 5.88), 180.0, {"center": false})
	deco("wicker_basket_01", Vector3(-7.4, 0, -0.7), 15.0, {"height": 0.35})
	# entrée : patère, chaussures, plante
	deco("sf:coat_shelf", Vector3(-1.15, 1.55, 5.86), 90.0, {"center": false, "depth": 1.0})
	deco("sf:sneakers", Vector3(-1.45, 0, 5.62), 170.0, {"width": 0.34})
	deco("sf:sneakers_brown", Vector3(-0.85, 0, 5.6), 200.0, {"width": 0.36})
	deco("potted_plant_02", Vector3(-3.75, 0, 5.5), 40.0, {"height": 0.95})
	# la fête : gâteau, téléphones des amis, verres, bouteilles, pizzas
	var top := 0.39
	var cake := put_on("strawberry_chocolate_cake", Vector3(-5.85, top, 1.22), 0.0)
	var cake_top: float = (cake.get_meta("size") as Vector3).y
	for k in 4:
		Props.candle(cake, Vector3(cos(k * 1.57) * 0.05, cake_top, sin(k * 1.57) * 0.05))
	var candle := B.omni(cake, Vector3(0, cake_top + 0.2, 0), Color(1.0, 0.6, 0.25), 0.25, 2.5)
	candle.set_meta("candle", true)
	room_lights.append(candle)
	for k in 3:
		var ph := Props.phone(inside, Vector3(-5.44 + k * 0.12, top, 1.3), 0.0, [Color(0.05, 0.05, 0.06), Color(0.7, 0.68, 0.66), Color(0.12, 0.2, 0.35)][k], "res://assets/gen/phone_lock_%d.png" % k)
		rest(ph)
		phones.append(ph)
	if callbacks.has("phones"):
		Interactable.create(inside, Vector3(-5.32, top + 0.05, 1.3), Vector3(0.45, 0.15, 0.3), "Regarder les téléphones", callbacks["phones"])
	deco_on("sf:beer_bottle", Vector3(-6.05, top, 1.42), 0.0, {"height": 0.24})
	deco_on("sf:beer_can", Vector3(-5.12, top, 1.06), 40.0, {"height": 0.12})
	deco_cup(Vector3(-6.08, top, 1.06))
	deco_cup(Vector3(-5.6, top, 1.45))
	deco_on("wooden_bowl_01", Vector3(-5.6, top, 1.08), 0.0, {"height": 0.08})
	deco_on("sf:beer_can", Vector3(-3.95, 0.6, 3.15), 0.0, {"height": 0.12})
	deco_on("sf:beer_bottle", Vector3(-3.8, 0.6, 2.8), 0.0, {"height": 0.24})
	# par terre, autour du canapé
	deco_on("sf:beer_can", Vector3(-4.75, 0.02, 2.1), 0.0, {"height": 0.12, "rot": Vector3(90, 0, 30)})
	deco_cup(Vector3(-3.2, 0.0, 0.2), true)
	deco_on("sf:beer_bottle", Vector3(-6.9, 0.02, 2.1), 0.0, {"height": 0.24})
	for k in 2:
		deco_on("sf:pizza_box", Vector3(-2.75 + k * 0.03, 0.02 + k * 0.05, 1.95), 12.0 * k - 20.0, {"width": 0.36})
	var colors := [Color(0.8, 0.1, 0.12), Color(0.95, 0.75, 0.1), Color(0.15, 0.45, 0.85), Color(0.9, 0.9, 0.92), Color(0.6, 0.2, 0.7)]
	for k in 9:
		Props.balloon(inside, Vector3(-7.3 + k * 0.42, HH - 0.2 - randf() * 0.15, 3.2 + sin(k * 2.1) * 0.6), colors[k % colors.size()])
	var banner := B.quad(inside, Vector2(3.6, 0.45), Vector3(-2.6, 2.25, -0.91), B.textured("res://assets/gen/banner.png", false, true))
	banner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# guirlande lumineuse le long du plafond (mur de façade)
	var bulb := B.emissive(Color(1.0, 0.78, 0.45), 4.0, true)
	for k in 30:
		var t := k / 29.0
		var p := Vector3(lerpf(-7.85, 0.85, t), HH - 0.12 - absf(sin(t * PI * 6.0)) * 0.12, 5.85)
		var g := B.sphere(inside, 0.018, p, bulb, 6)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp_glows.append(g)
	var string_light := B.omni(inside, Vector3(-3.5, HH - 0.3, 5.4), Color(1.0, 0.75, 0.45), 0.35, 5.0)
	room_lights.append(string_light)


func _kitchen() -> void:
	ceiling_light(Vector3(4.6, 0, 2.6), 1.1, 8.0, true)
	var k := put("sf:kitchen_cabinets", Vector3(5.86, 0, 3.66), -90.0, {"scale": 0.0254, "remove": ["group_15", "instance_212"]})
	k.name = "KitchenCabinets"
	support(k)
	# collisions du plan de travail en L
	blocker(Vector3(7.58, 0.46, 3.67), Vector3(0.62, 0.92, 4.5))
	blocker(Vector3(5.86, 0.46, 5.6), Vector3(4.05, 0.92, 0.62))
	var fridge := put("sf:old_fridge", Vector3(2.75, 0, -0.55), 0.0, {"height": 1.75, "collide": true})
	fridge.name = "Fridge"
	# la liste, aimantée sur la porte du frigo (lisible de près)
	var fz := -0.55 + (fridge.get_meta("size") as Vector3).z * 0.5 + 0.004
	var note := B.quad(inside, Vector2(0.21, 0.287), Vector3(2.62, 1.32, fz), B.textured("res://assets/gen/note_list.png"), Vector3(0, 0, 2.5))
	note.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var magnet_cols := [Color(0.85, 0.2, 0.2), Color(0.2, 0.55, 0.9), Color(0.95, 0.8, 0.2), Color(0.3, 0.75, 0.35)]
	for i in 4:
		var mg := B.cylinder(inside, 0.016, 0.016, 0.012, Vector3(2.9 + (i % 2) * 0.12, 1.55 - (i / 2) * 0.35, fz + 0.006), B.color_mat(magnet_cols[i], 0.4), false, 12, Vector3(90, 0, 0))
		mg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 2:
		var ph := B.quad(inside, Vector2(0.1, 0.075), Vector3(2.92 + i * 0.12, 1.47 - i * 0.33, fz + 0.002), B.textured("res://assets/gen/photo_%d.png" % (i + 1)), Vector3(0, 0, -4.0 + i * 7.0))
		ph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if callbacks.has("note"):
		Interactable.create(inside, Vector3(2.62, 1.32, fz + 0.03), Vector3(0.28, 0.34, 0.1), "Lire la liste", callbacks["note"])
	var table := deco("dining_table", Vector3(3.6, 0, 2.6), 0.0, {"collide": true, "scale": 0.75})
	support(table)
	var tt: float = 0.66 if table == null else (table.get_meta("size") as Vector3).y
	for c in [[3.1, 1.85, 0.0], [4.1, 1.85, 0.0], [3.1, 3.35, 180.0], [4.1, 3.35, 180.0]]:
		deco("dining_chair_02", Vector3(c[0], 0, c[1]), c[2] + randf_range(-12, 12))
	deco_on("sf:pizza_open", Vector3(3.25, tt, 2.55), 15.0, {"width": 0.4})
	deco_on("sf:pizza_box", Vector3(3.95, tt, 2.35), -8.0, {"width": 0.36})
	deco_on("sf:kitchen_decor", Vector3(4.2, tt, 2.85), 0.0, {"part": "Fruit Bowl", "height": 0.15})
	deco_cup(Vector3(4.45, tt, 2.3))
	deco_on("sf:beer_bottle", Vector3(3.7, tt, 2.95), 0.0, {"height": 0.24})
	# appareils et objets sur les plans de travail
	var top := 0.93
	deco_on("vintage_microwave", Vector3(7.55, top, 2.3), -90.0, {"scale": 0.65})
	deco_on("sf:kitchen_decor", Vector3(7.6, top, 3.4), -90.0, {"part": "Toaster", "height": 0.22})
	deco_on("vintage_electric_kettle", Vector3(7.6, top, 3.95), -100.0, {"height": 0.26})
	deco_on("sf:kitchen_decor", Vector3(6.9, top, 5.62), 180.0, {"part": "SpiceJars", "width": 0.45})
	deco_on("sf:kitchen_decor", Vector3(4.3, top, 5.62), 180.0, {"part": "Paper Towel", "height": 0.3})
	deco_on("sf:kitchen_decor", Vector3(3.95, top, 5.62), 180.0, {"part": "WineBox", "height": 0.3})
	deco_on("sf:kitchen_decor", Vector3(7.55, top, 1.75), -90.0, {"part": "Plant", "height": 0.55})
	deco_on("wooden_cutting_board", Vector3(6.2, top, 5.55), 175.0, {"width": 0.42})
	deco_on("lemon", Vector3(6.15, top + 0.04, 5.55), 0.0, {"height": 0.07})
	deco_on("jug_01", Vector3(7.62, top, 4.55), -90.0, {"height": 0.18})
	deco_on("wine_bottles_01", Vector3(5.2, top, 5.62), 180.0, {"scale": 0.8})
	for i in 3:
		deco_on("sf:beer_can", Vector3(4.75 + i * 0.09, top, 5.5 + (i % 2) * 0.06), i * 40.0, {"height": 0.12})
	deco("metal_trash_can", Vector3(1.6, 0, 5.4), 0.0, {"scale": 0.5})
	deco("plastic_broom", Vector3(1.25, 0, 5.62), 160.0, {"height": 1.2})


func _bedroom() -> void:
	ceiling_light(Vector3(-5.0, 0, -3.5), 0.85, 7.0, false)
	support(put("sf:bedroom_set", Vector3(-5.0, 0, -3.55), 0.0, {"remove": ["Plane"], "collide": "mesh"}))
	deco("sf:old_shelves", Vector3(-2.47, 0, -2.4), -90.0, {"part": "closet", "collide": true})
	support(deco("ClassicNightstand_01", Vector3(-7.6, 0, -5.45), 0.0, {"collide": true}))
	deco_on("alarm_clock_01", Vector3(-7.6, 0.7, -5.45), 20.0, {"height": 0.1})
	deco_on("desk_lamp_arm_01", Vector3(-7.75, 0.7, -5.6), 30.0, {"height": 0.45})
	var bl := B.omni(inside, Vector3(-7.5, 1.0, -5.3), Color(1.0, 0.7, 0.4), 0.35, 3.5)
	room_lights.append(bl)
	deco_on("standing_picture_frame_01", Vector3(-7.45, 0.7, -5.3), 160.0, {"height": 0.18})
	deco("vintage_suitcase", Vector3(-2.75, 0, -4.6), -90.0, {"part": "vintage_suitcase_01_bottom", "height": 0.56})
	deco("wicker_basket_02", Vector3(-7.55, 0, -1.45), 20.0, {"height": 0.3})
	deco("sf:sneakers_brown", Vector3(-4.2, 0, -1.7), 120.0, {"width": 0.36})
	deco("hanging_picture_frame_01", Vector3(-7.9, 1.45, -3.6), 90.0, {"center": false, "height": 0.7})
	# ordinateur portable ouvert sur le bureau de la chambre, tourné vers la chaise ;
	# son écran montre la retransmission en direct
	var lap_pos := Vector3(-4.2, 0.78, -3.62)
	var lap := put("sf:laptop", lap_pos, -100.0, {"width": 0.31})
	lap.name = "Laptop"
	lap.set_meta("editobj", "laptop")
	rest(lap)
	for node in lap.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(si)
			if mat != null and mat.resource_name == "ComputerScreen":
				mi.set_surface_override_material(si, feed.screen_material(0.0))
				mi.layers = SecurityFeed.SCREEN_LAYER
	if callbacks.has("laptop"):
		# attaché à l'ordinateur : il le suit si on le déplace dans l'éditeur
		var k := 1.0 / lap.scale.x
		Interactable.create(lap, Vector3(0, 0.12, 0) * k, Vector3(0.45, 0.3, 0.45) * k, "Regarder l'ordinateur", callbacks["laptop"])


func _bathroom() -> void:
	ceiling_light(Vector3(0.0, 0, -3.5), 0.75, 5.0, false)
	# lave-linge + douche contre le mur du fond
	var set_d := 1.13
	support(deco("sf:bathroom_set", Vector3(0.1, 0, -5.89 + set_d * 0.5 + 0.01), 0.0, {"remove": ["Plane_001_Material 3"], "collide": "mesh"}))
	# toilettes contre le mur de droite, lavabo + miroir contre le mur de gauche
	var wc := deco("sf:toilet", Vector3(1.93, 0, -2.75), -90.0, {"height": 0.78, "collide": true})
	if wc != null:
		wc.position.x = 1.93 - (wc.get_meta("size") as Vector3).z * 0.5
	deco("sf:toilet_paper", Vector3(1.78, 0, -2.15), 0.0, {"height": 0.11})
	deco("plunger", Vector3(1.75, 0, -3.35), 15.0, {"height": 0.42})
	var vanity := put("sf:sink_vanity", Vector3(-1.93 + 0.225, 0, -3.0), 90.0, {"height": 0.94, "collide": true})
	vanity.name = "Vanity"
	deco("ornate_mirror_01", Vector3(-1.91, 1.22, -3.0), 90.0, {"height": 0.74})
	B.decal(inside, "res://assets/gen/decal_handprint.png", Vector3(-1.89, 1.55 + FLOOR_Y, -2.92), Vector3(1, 0, 0), 0.3, 0.4, 0.06)
	deco("sf:towel_rail", Vector3(-1.9, 1.3, -4.45), 0.0, {"center": false, "depth": 0.7})
	deco("rubber_duck_toy", Vector3(-0.45, 0, -5.55), 160.0, {"height": 0.08})
	deco("bleach_bottle", Vector3(-1.75, 0, -5.6), 20.0, {"height": 0.29})
	deco("multi_cleaner_bottle", Vector3(-1.6, 0, -5.65), -30.0, {"height": 0.23})
	# tapis de bain devant la douche (déplaçable dans l'éditeur de carte)
	var mat := B.mat("fabric_pattern_07", 0.4, {"color": Color(0.45, 0.6, 0.62)})
	var bath_mat := Node3D.new()
	bath_mat.name = "BathMat"
	inside.add_child(bath_mat)
	bath_mat.position = Vector3(0.6, 0, -4.45)
	B.box(bath_mat, Vector3(0.75, 0.012, 0.5), Vector3(0, 0.006, 0), mat, false)
	bath_mat.set_meta("editobj", "bathmat")
	bath_mat.set_meta("size", Vector3(0.75, 0.012, 0.5))
	bath_mat.set_meta("spec", {"model": "tapis de bain", "center": true})
	var tap := Node3D.new()
	inside.add_child(tap)
	tap.position = Vector3(-1.8, 0.92, -3.0)
	tap.name = "Tap"


func _office() -> void:
	# bureau (pack « Office ») contre le mur du fond : posé à sa vraie place, sans l'écran cathodique
	var pack := put("sf:office_assets", Vector3(7.85, 0, -5.64), -90.0, {"center": false,
		"remove": ["Vent", "Monitor_6", "Computer_5", "Cactus_Pot_2", "FileBox", "PhotoFrame_10x15", "Lamp01", "TapeRecorder", "Microphone", "PhotoFrame2"]})
	pack.name = "OfficeDesk"
	# le petit cadre du pack était à cheval sur le coin de la pièce : décalé sur le mur du fond
	put("sf:office_assets", Vector3(7.85 - 0.3, 0, -5.64), -90.0, {"center": false, "part": "PhotoFrame2_46"})
	blocker(Vector3(6.68, 0.375, -5.43), Vector3(2.02, 0.75, 0.86))
	# trois écrans de surveillance SUR le bureau : un en direct, deux en neige
	var desk_top := 0.75
	var live_mat := feed.screen_material(0.0)
	var specs := [[7.32, SecurityFeed.static_material(1.0), 6.0], [6.7, live_mat, 0.0], [6.08, SecurityFeed.static_material(0.85), -6.0]]
	for s in specs:
		var m := Node3D.new()
		inside.add_child(m)
		m.position = Vector3(s[0], desk_top, -5.62)
		m.rotation_degrees.y = s[2]
		put_into(m, "sf:flat_tv", Vector3.ZERO, -90.0, {"height": 0.36})
		var scr := SecurityFeed.screen(m, Vector2(0.52, 0.29), Vector3(0, 0.195, 0.016), Vector3.ZERO, s[1])
		if s[1] == live_mat:
			scr.name = "LiveMonitor"
	var glow := B.omni(inside, Vector3(6.7, 1.2, -4.9), Color(0.55, 0.75, 0.75), 0.45, 4.5)
	glow.set_meta("screen", true)
	deco("sf:office_assets", Vector3(7.62, desk_top, -5.25), -90.0, {"part": "Lamp01_57", "height": 0.5})
	# tableau de liège : les "sujets"
	var cork := B.color_mat(Color(0.55, 0.4, 0.26), 0.95)
	B.box(inside, Vector3(0.03, 1.0, 1.5), Vector3(2.1, 1.55, -3.4), cork, false)
	for k in 4:
		var ph := B.quad(inside, Vector2(0.3, 0.27), Vector3(2.125, 1.75 - (k / 2) * 0.42, -3.75 + (k % 2) * 0.7), B.textured("res://assets/gen/photo_%d.png" % (k + 1)), Vector3(0, 90, randf_range(-6, 6)))
		ph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	support(deco("sf:old_fridge", Vector3(7.6, 0, -2.0), -90.0, {"height": 1.2, "collide": true}))
	deco_on("sf:office_assets", Vector3(7.6, 1.25, -2.0), -90.0, {"part": "TapeRecorder_33", "width": 0.5})
	deco("cardboard_box_01", Vector3(2.6, 0, -5.5), 30.0)
	deco_on("cardboard_box_01", Vector3(2.65, 0.4, -5.45), 10.0)
	deco("plastic_crate_01", Vector3(3.2, 0, -5.55), -5.0)


func _cameras() -> void:
	var specs := [
		[Vector3(0.75, HH - 0.2, -0.75), Vector3(-1, -0.4, 1), "salon"],
		[Vector3(-7.75, HH - 0.2, 5.75), Vector3(1, -0.4, -1), "salon"],
		[Vector3(1.25, HH - 0.2, 5.75), Vector3(1, -0.4, -1), "cuisine"],
		[Vector3(-2.25, HH - 0.2, -1.25), Vector3(-1, -0.4, -1), "chambre"],
		[Vector3(1.75, HH - 0.2, -1.25), Vector3(-1, -0.5, -1), "sdb"],
		[Vector3(6.2, HH - 0.25, -5.75), Vector3(0, -0.35, 1), "bureau"],
	]
	for s in specs:
		var c := SecurityCamera.create(inside, s[0], s[1])
		c.set_meta("editcam", "cam%d" % cams.size())
		cams.append(c)
		cam_rooms[c] = s[2]
		if s[2] == "bureau":
			office_cam = c
	var outside := SecurityCamera.create(self, Vector3(-1.0, FLOOR_Y + 2.55, 6.35), Vector3(-0.3, -0.5, 1))
	outside.set_meta("editcam", "cam%d" % cams.size())
	cams.append(outside)
	cam_rooms[outside] = "dehors"
	feed.source = cams[0]
	feed.cam_label = "CAM 01 — SALON"
