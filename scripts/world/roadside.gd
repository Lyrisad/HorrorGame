class_name Roadside
extends RefCounted
## Le mobilier de la départementale qui longe la forêt (objets « proc:road_<sorte> » de l'éditeur de carte) :
## balise de bord de route, panneaux, borne kilométrique, panneau de l'ONF, barrière du chemin forestier.
## Origine au sol, face avant vers +z. Panneaux, balises et marquage sont rétroréfléchissants (retro.gdshader) :
## ils s'allument dans le faisceau de la lampe, comme dans des phares.

## sorte → nom dans le catalogue de l'éditeur
const KINDS := {
	"delineator": "balise de bord de route (J6)",
	"sign_80": "panneau 80 km/h",
	"sign_chasse": "panneau danger « chasse en cours »",
	"sign_b0": "panneau interdit à tout véhicule",
	"borne": "borne kilométrique (D 47)",
	"foret": "panneau en bois « Forêt domaniale »",
	"barrier": "barrière du chemin forestier (ouverte)",
}

static var _mats := {}


static func make(kind: String, parent: Node) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	n.name = "road_" + kind
	match kind:
		"delineator":
			_delineator(n)
		"sign_80":
			_sign(n, "road_sign_80", Vector2(0.6, 0.6))
		"sign_b0":
			_sign(n, "road_sign_b0", Vector2(0.6, 0.6))
		"sign_chasse":
			_sign(n, "road_sign_chasse", Vector2(0.7, 0.875))
		"borne":
			_borne(n)
		"foret":
			_forest_sign(n)
		_:
			_barrier(n)
	# collide true : ses propres collisions (le poteau, pas une boîte autour du panneau)
	n.set_meta("spec", {"model": "proc:road_" + kind, "collide": true})
	return n


static func retro(tex_path: String, strength := 6.0, back := false, alpha := true, tint := Color.WHITE) -> ShaderMaterial:
	var key := "%s|%s|%s|%s|%s" % [tex_path, strength, back, alpha, tint]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/retro.gdshader")
	if tex_path != "":
		m.set_shader_parameter("tex", load(tex_path))
	m.set_shader_parameter("retro", strength)
	m.set_shader_parameter("back", 1.0 if back else 0.0)
	m.set_shader_parameter("use_alpha", alpha)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_mats[key] = m
	return m


static func _collider(n: Node3D, shape: Shape3D, pos: Vector3, rot_y := 0.0) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	sb.add_child(cs)
	n.add_child(sb)
	sb.position = pos
	sb.rotation.y = rot_y


static func _post_collider(n: Node3D, r: float, h: float, pos := Vector3.ZERO) -> void:
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	_collider(n, cyl, pos + Vector3(0, h * 0.5, 0))


## Balise J6 : PVC blanc d'un mètre, bande noire en biais, un catadioptre de chaque côté (vers chaque sens).
static func _delineator(n: Node3D) -> void:
	var h := 1.05
	B.box(n, Vector3(0.1, h, 0.12), Vector3(0, h * 0.5, 0), B.color_mat(Color(0.86, 0.86, 0.83), 0.6), false)
	var face := retro("res://assets/gen/road_delineator.png", 0.0, false, false)
	var cat := retro("", 14.0, false, false, Color(0.95, 0.95, 0.9))
	for side in [1.0, -1.0]:
		B.quad(n, Vector2(0.1, h), Vector3(0, h * 0.5, 0.061 * side), face, Vector3(0, 0 if side > 0 else 180, 0))
		B.quad(n, Vector2(0.045, 0.1), Vector3(0, 0.83, 0.063 * side), cat, Vector3(0, 0 if side > 0 else 180, 0))
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.1, h, 0.12)
	_collider(n, bs, Vector3(0, h * 0.5, 0))
	n.set_meta("size", Vector3(0.1, h, 0.12))


## Panneau sur poteau galvanisé : film rétroréfléchissant devant, tôle grise derrière, deux colliers.
static func _sign(n: Node3D, tex: String, size: Vector2) -> void:
	var path := "res://assets/gen/%s.png" % tex
	var bottom := 1.05
	var cy := bottom + size.y * 0.5
	B.quad(n, size, Vector3(0, cy, 0.003), retro(path, 2.8))
	B.quad(n, size, Vector3(0, cy, -0.003), retro(path, 0.0, true), Vector3(0, 180, 0))
	var steel := B.color_mat(Color(0.5, 0.52, 0.53), 0.45, 0.8)
	var top := bottom + size.y - 0.06
	B.cylinder(n, 0.03, 0.03, top, Vector3(0, top * 0.5, -0.04), steel, false, 10)
	B.cylinder(n, 0.032, 0.032, 0.012, Vector3(0, top + 0.001, -0.04), B.color_mat(Color(0.2, 0.2, 0.2), 0.6), false, 10)
	for y in [bottom + 0.12, bottom + size.y - 0.14]:
		B.box(n, Vector3(0.09, 0.03, 0.05), Vector3(0, y, -0.02), steel, false)
	_post_collider(n, 0.05, top, Vector3(0, 0, -0.04))
	n.set_meta("size", Vector3(size.x, bottom + size.y, 0.1))


## Borne kilométrique : corps en béton blanc, capuchon arrondi jaune (route départementale), D 47 / PR 12.
static func _borne(n: Node3D) -> void:
	var w := 0.4
	var hb := 0.45
	var d := 0.18
	B.box(n, Vector3(w, hb, d), Vector3(0, hb * 0.5, 0), B.color_mat(Color(0.82, 0.82, 0.79), 0.85), false)
	B.cylinder(n, w * 0.5, w * 0.5, d, Vector3(0, hb, 0), B.color_mat(Color(0.8, 0.6, 0.1), 0.6), false, 24, Vector3(90, 0, 0))
	var face := retro("res://assets/gen/road_borne.png", 0.8)
	for side in [1.0, -1.0]:
		B.quad(n, Vector2(w, hb + w * 0.5), Vector3(0, (hb + w * 0.5) * 0.5, (d * 0.5 + 0.002) * side), face, Vector3(0, 0 if side > 0 else 180, 0))
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, hb + w * 0.5, d)
	_collider(n, bs, Vector3(0, (hb + w * 0.5) * 0.5, 0))
	n.set_meta("size", Vector3(w, hb + w * 0.5, d))


## Panneau de l'ONF à l'entrée de la forêt : deux poteaux, une planche gravée, un petit toit.
static func _forest_sign(n: Node3D) -> void:
	var wood := B.mat("worn_planks", 1.2, {"color": Color(0.45, 0.32, 0.22), "triplanar": true, "world": false})
	for x in [-0.72, 0.72]:
		B.box(n, Vector3(0.1, 1.62, 0.1), Vector3(x, 0.81, 0), wood, false)
		_post_collider(n, 0.07, 1.62, Vector3(x, 0, 0))
	B.box(n, Vector3(1.6, 0.45, 0.04), Vector3(0, 1.2, 0.07), wood, false)
	var face := StandardMaterial3D.new()
	face.albedo_texture = load("res://assets/gen/road_forest_sign.png")
	face.roughness = 0.9
	B.quad(n, Vector2(1.6, 0.45), Vector3(0, 1.2, 0.0905), face)
	B.box(n, Vector3(1.78, 0.035, 0.3), Vector3(0, 1.645, 0.04), wood, false, Vector3(-8, 0, 0))
	n.set_meta("size", Vector3(1.78, 1.68, 0.3))


## Barrière forestière pivotante, peinte en vert, ouverte (repoussée dans le bois) ; chaîne et cadenas coupé.
static func _barrier(n: Node3D) -> void:
	var paint := B.color_mat(Color(0.13, 0.2, 0.14), 0.55, 0.35)
	var half := 1.8
	for x in [-half, half]:
		B.cylinder(n, 0.06, 0.06, 1.0, Vector3(x, 0.5, 0), paint, false, 12)
		B.cylinder(n, 0.07, 0.07, 0.03, Vector3(x, 1.0, 0), paint, false, 12)
		_post_collider(n, 0.07, 1.0, Vector3(x, 0, 0))
	# la fourche où repose la lisse quand c'est fermé
	for dz in [-0.07, 0.07]:
		B.box(n, Vector3(0.03, 0.14, 0.02), Vector3(half, 1.07, dz), paint, false)
	# la lisse : ouverte à 100° (repoussée côté bois, hors du chemin), bandes rouges et blanches
	var ang := deg_to_rad(100.0)
	var dir := Vector3(cos(ang), 0, -sin(ang))
	var hinge := Vector3(-half, 0.9, 0)
	var length := 3.55
	var bar := Node3D.new()
	n.add_child(bar)
	bar.position = hinge
	bar.basis = Basis(Vector3.UP, atan2(-dir.z, dir.x))
	B.cylinder(bar, 0.045, 0.045, length, Vector3(length * 0.5, 0, 0), paint, false, 10, Vector3(0, 0, 90))
	var red := retro("", 4.0, false, false, Color(0.75, 0.08, 0.08))
	var white := retro("", 4.0, false, false, Color(0.85, 0.85, 0.82))
	for k in 6:
		B.cylinder(bar, 0.048, 0.048, 0.25, Vector3(1.0 + k * 0.4, 0, 0), red if k % 2 == 0 else white, false, 10, Vector3(0, 0, 90))
	B.box(bar, Vector3(0.3, 0.22, 0.22), Vector3(-0.2, 0, 0), B.color_mat(Color(0.18, 0.18, 0.18), 0.7, 0.4), false)
	var bs := BoxShape3D.new()
	bs.size = Vector3(length, 0.12, 0.12)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = bs
	sb.add_child(cs)
	bar.add_child(sb)
	sb.position = Vector3(length * 0.5, 0, 0)
	# la chaîne pend encore au poteau du loquet, cadenas cisaillé par terre
	var chain := B.color_mat(Color(0.3, 0.3, 0.3), 0.4, 0.9)
	for k in 7:
		B.box(n, Vector3(0.012, 0.045, 0.03 if k % 2 == 0 else 0.012), Vector3(half + 0.07, 0.95 - k * 0.04, 0.0), chain, false)
	B.box(n, Vector3(0.05, 0.06, 0.025), Vector3(half + 0.25, 0.015, 0.15), B.color_mat(Color(0.55, 0.42, 0.18), 0.4, 0.8), false, Vector3(90, 30, 0))
	n.set_meta("size", Vector3(half * 2.0 + 0.14, 1.1, 0.3))
