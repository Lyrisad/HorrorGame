class_name MapLayout
extends RefCounted
## Disposition des objets de décor d'une carte ("maison", "egouts"), modifiable avec l'éditeur
## intégré au jeu (F8). Fichier JSON : user://cartes/<carte>.json (celui du joueur, prioritaire),
## sinon res://maps/<carte>.json (livré avec le jeu). Sans fichier, le code des niveaux pose le
## décor par défaut. Les objets liés au scénario ne sont jamais dans ce fichier.

const USER_DIR := "user://cartes/"
const RES_DIR := "res://maps/"


static func file_for(map_id: String) -> String:
	for dir in [USER_DIR, RES_DIR]:
		if FileAccess.file_exists(dir + map_id + ".json"):
			return dir + map_id + ".json"
	return ""


## Entrées sauvegardées, ou null s'il n'y a pas de disposition personnalisée.
static func load_entries(map_id: String) -> Variant:
	var p := file_for(map_id)
	if p == "":
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("props"):
		push_warning("Disposition illisible : " + p)
		return null
	return data["props"]


static func spawn(entries: Array, root: Node3D) -> void:
	for e in entries:
		# anciennes toiles d'araignée (coins, arêtes) retirées du jeu : seules restent celles qui pendent
		if str(e.get("model", "")) in ["proc:cobweb_corner", "proc:cobweb_edge"]:
			continue
		# objet jamais posé, resté là où l'éditeur le crée (ancien bug de la liste : des dizaines de troncs
		# empilés au point 0) : la souris ne peut pas poser un objet pile à l'origine, sans aucune rotation
		if e.get("xf", []) == IDENTITY_XF:
			continue
		spawn_entry(e, root)


const IDENTITY_XF := [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]


static func spawn_entry(e: Dictionary, root: Node3D) -> Node3D:
	var model: String = e.get("model", "")
	var n: Node3D
	var auto := false
	if model.begins_with("proc:"):
		n = _procedural(model, root)
	else:
		var col: Variant = e.get("collide", false)
		# "auto", ou une plante à qui l'ancien éditeur avait donné une boîte : hitbox recalculée (aucune)
		auto = str(col) == "auto" or (col is bool and col and is_soft(e))
		var fit := {"scale": float(e.get("scale", 1.0)), "center": bool(e.get("center", true)), "collide": false if auto else (col if str(col) == "mesh" else bool(col))}
		if str(e.get("part", "")) != "":
			fit["part"] = e["part"]
		if e.has("remove"):
			fit["remove"] = e["remove"]
		if e.has("rot"):
			var r: Array = e["rot"]
			fit["rot"] = Vector3(r[0], r[1], r[2])
		n = B.model(root, model, Vector3.ZERO, 0.0, fit)
	if e.has("xf"):
		n.transform = _xf_from(e["xf"])
	n.set_meta("decor", true)
	if auto:
		auto_collide(n)
	return n


## Mots (dans le modèle ou la pièce) des objets qu'on traverse : plantes, toiles, papiers...
const SOFT := ["fern", "shrub", "Shrub", "weed", "nettle", "Sapling", "dry_branches", "cobweb", "poster",
	"bottle", "sleeping_bag", "rug", "cap", "sneakers", "towel", "paper"]


static func is_soft(spec: Dictionary) -> bool:
	var what := str(spec.get("model", "")) + "|" + str(spec.get("part", ""))
	for word in SOFT:
		if what.contains(word):
			return true
	return false


## Hitbox automatique d'un objet de décor : les plantes se traversent, un arbre a un tronc, le reste (s'il est
## assez grand pour gêner) a une boîte à sa taille. Marqué "auto" : recréé pareil au chargement de la carte.
static func auto_collide(n: Node3D) -> void:
	var spec: Dictionary = n.get_meta("spec", {})
	var col: Variant = spec.get("collide", false)
	if (col is bool and col) or str(col) in ["mesh", "auto"] or not bool(spec.get("center", true)) or is_soft(spec):
		return
	var what := str(spec.get("model", "")) + "|" + str(spec.get("part", ""))
	var sz: Vector3 = n.get_meta("size", Vector3.ZERO)
	var cs := CollisionShape3D.new()
	if what.contains("pine_tree") or what.contains("Tree"):
		var cyl := CylinderShape3D.new()
		cyl.radius = clampf(sz.y * 0.017, 0.12, 0.38)
		cyl.height = minf(sz.y, 6.0)
		cs.shape = cyl
		cs.position = Vector3(0, cyl.height * 0.5, 0)
	elif sz.y > 0.35 and maxf(sz.x, sz.z) > 0.35:
		var bs := BoxShape3D.new()
		bs.size = sz
		cs.shape = bs
		cs.position = Vector3(0, sz.y * 0.5, 0)
	else:
		return
	var body := StaticBody3D.new()
	body.name = "AutoCollide"
	body.add_child(cs)
	n.add_child(body)
	spec["collide"] = "auto"


static func _procedural(model: String, root: Node3D) -> Node3D:
	if model.begins_with("proc:poster_"):
		var poster := Props.poster(root, int(model.trim_prefix("proc:poster_")))
		poster.set_meta("spec", {"model": model, "center": false})
		return poster
	if model == "proc:bottle":
		var bottle := Props.bottle(root)
		bottle.set_meta("spec", {"model": model, "center": true})
		return bottle
	if model.begins_with("proc:cobweb"):
		var web := Props.cobweb(root)
		web.set_meta("spec", {"model": "proc:cobweb_strands", "center": false})
		return web
	var n: Node3D = Props.red_cup(root, Vector3.ZERO, model == "proc:red_cup_tipped")
	n.set_meta("spec", {"model": model})
	n.set_meta("size", Vector3(0.1, 0.12, 0.1))
	return n


static func entry_of(n: Node3D, root: Node3D) -> Dictionary:
	var e: Dictionary = (n.get_meta("spec", {}) as Dictionary).duplicate(true)
	e["xf"] = _xf_to(root.global_transform.affine_inverse() * n.global_transform)
	return e


## Tous les objets de décor (déplaçables) sous `root`.
static func collect(root: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in root.find_children("*", "Node3D", true, false):
		if n.has_meta("decor") and n.is_inside_tree() and not n.is_queued_for_deletion():
			out.append(n)
	return out


## Caméras de surveillance réglables (meta "editcam").
static func cameras(root: Node3D) -> Array[SecurityCamera]:
	var out: Array[SecurityCamera] = []
	for n in root.find_children("*", "Node3D", true, false):
		if n is SecurityCamera and n.has_meta("editcam"):
			out.append(n as SecurityCamera)
	return out


## Objets liés à l'histoire mais déplaçables dans l'éditeur (meta "editobj" = identifiant) :
## leur position est sauvegardée, mais on ne peut ni les supprimer ni les dupliquer.
static func movables(root: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in root.find_children("*", "Node3D", true, false):
		if n.has_meta("editobj"):
			out.append(n)
	return out


## Réglage booléen rangé dans le fichier de la carte (ex. « toiles » : les toiles d'araignée par défaut
## ont déjà été posées et font partie de la disposition du joueur).
static func has_flag(map_id: String, key: String) -> bool:
	return bool(_data(map_id).get(key, false))


static func _data(map_id: String) -> Dictionary:
	var p := file_for(map_id)
	if p == "":
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return data if typeof(data) == TYPE_DICTIONARY else {}


## Replace les objets de l'histoire déplacés ; renvoie ceux qui ont une position sauvegardée.
static func apply_objs(map_id: String, root: Node3D) -> Array[Node3D]:
	var placed: Array[Node3D] = []
	var by_id := {}
	for o in _data(map_id).get("objs", []):
		by_id[str(o.get("id", ""))] = o
	for n in movables(root):
		var e: Dictionary = by_id.get(str(n.get_meta("editobj")), {})
		if e.has("xf"):
			n.global_transform = root.global_transform * _xf_from(e["xf"])
			placed.append(n)
	return placed


## Applique les réglages de caméras sauvegardés (position + direction de repos).
static func apply_cams(map_id: String, root: Node3D) -> void:
	var data := _data(map_id)
	if not data.has("cams"):
		return
	var by_id := {}
	for c in data["cams"]:
		by_id[str(c.get("id", ""))] = c
	for cam in cameras(root):
		var e: Dictionary = by_id.get(str(cam.get_meta("editcam")), {})
		if e.is_empty():
			continue
		var pos: Vector3 = root.global_transform * _xf_from(e["xf"]).origin
		var d: Array = e.get("dir", [0, 0, -1])
		var rest := root.global_basis * Vector3(d[0], d[1], d[2])
		cam.global_position = pos
		cam.set_rest(rest)
		if e.has("wall"):
			var w: Array = e["wall"]
			cam.set_mount(pos, root.global_basis * Vector3(w[0], w[1], w[2]))
		else:
			# ancienne sauvegarde : l'éditeur posait la caméra 22 cm devant la surface cliquée,
			# regard = sortie du mur + inclinaison (mur) ou bien vers le bas (plafond)
			var flat := Vector3(rest.x, 0, rest.z)
			if rest.y < -0.5 or flat.length() < 0.2:
				cam.attach_ceiling(pos + Vector3.UP * 0.18)
			else:
				var out := flat.normalized()
				cam.attach_wall(pos - out * 0.22, out)


static func save(map_id: String, root: Node3D) -> String:
	var props := []
	for n in collect(root):
		props.append(entry_of(n, root))
	var cams := []
	var inv := root.global_transform.affine_inverse()
	for cam in cameras(root):
		var d := root.global_basis.inverse() * cam.rest_dir
		var w := root.global_basis.inverse() * cam.mount_out
		cams.append({"id": cam.get_meta("editcam"), "xf": _xf_to(inv * cam.global_transform), "dir": [snappedf(d.x, 0.0001), snappedf(d.y, 0.0001), snappedf(d.z, 0.0001)],
			"wall": [snappedf(w.x, 0.0001), snappedf(w.y, 0.0001), snappedf(w.z, 0.0001)]})
	var objs := []
	for n in movables(root):
		objs.append({"id": n.get_meta("editobj"), "xf": _xf_to(inv * n.global_transform)})
	# drapeaux : le décor généré par défaut (toiles des égouts, sous-bois de la forêt) fait déjà partie de la carte
	var txt := JSON.stringify({"version": 1, "carte": map_id, "objets": props.size(), "props": props, "cams": cams, "objs": objs, "toiles": true, "sousbois": true}, "\t")
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var f := FileAccess.open(USER_DIR + map_id + ".json", FileAccess.WRITE)
	f.store_string(txt)
	f.close()
	# depuis les sources (éditeur Godot), la disposition est aussi rangée dans le projet → livrée avec le .exe
	if OS.has_feature("editor"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RES_DIR))
		var f2 := FileAccess.open(RES_DIR + map_id + ".json", FileAccess.WRITE)
		if f2 != null:
			f2.store_string(txt)
			f2.close()
	return ProjectSettings.globalize_path(USER_DIR + map_id + ".json")


## Revient au décor d'origine (supprime la disposition personnalisée).
static func reset(map_id: String) -> void:
	var dirs := [USER_DIR]
	if OS.has_feature("editor"):
		dirs.append(RES_DIR)
	for dir in dirs:
		if FileAccess.file_exists(dir + map_id + ".json"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + map_id + ".json"))


static func _xf_to(t: Transform3D) -> Array:
	var out := []
	for v in [t.basis.x, t.basis.y, t.basis.z, t.origin]:
		var w: Vector3 = v
		out.append_array([snappedf(w.x, 0.0001), snappedf(w.y, 0.0001), snappedf(w.z, 0.0001)])
	return out


static func _xf_from(a: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))
