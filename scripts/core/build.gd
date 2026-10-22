class_name B
extends RefCounted
## Boîte à outils de construction de décors : matériaux PBR (textures Poly Haven),
## formes de base avec collisions, modèles 3D recadrés, lumières, textes, décalcomanies.

static var _mats := {}


static func tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


## Matériau PBR à partir d'un dossier assets/textures/<slug>/.
## Par défaut en projection "triplanaire monde" : pas besoin d'UV, densité de texture constante.
## `tile` = taille en mètres d'une répétition de la texture.
static func mat(slug: String, tile := 1.0, opts := {}) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [slug, tile, str(opts)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	var base := "res://assets/textures/%s/%s_" % [slug, slug]
	var a := tex(base + "diff.jpg")
	if a != null:
		m.albedo_texture = a
	var n := tex(base + "nor.jpg")
	if n != null:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = opts.get("normal", 1.0)
	var r := tex(base + "rough.jpg")
	if r != null:
		m.roughness_texture = r
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	var ao := tex(base + "ao.jpg")
	if ao != null and opts.get("ao", true):
		m.ao_enabled = true
		m.ao_texture = ao
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	m.albedo_color = opts.get("color", Color.WHITE)
	m.roughness = opts.get("roughness", 1.0)
	m.metallic = opts.get("metallic", 0.0)
	m.uv1_triplanar = opts.get("triplanar", true)
	m.uv1_world_triplanar = opts.get("world", true)
	m.uv1_triplanar_sharpness = 6.0
	m.uv1_scale = Vector3.ONE / tile
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


static func color_mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var key := "col|%s|%s|%s" % [c, rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


static func emissive(c: Color, energy := 2.0, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func glass(tint := Color(0.05, 0.06, 0.07, 0.35), rough := 0.04) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# ------------------------------------------------------------------ formes
static func _collider(on: Node3D, shape: Shape3D, offset := Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = offset
	sb.add_child(cs)
	on.add_child(sb)
	return sb


static func box(parent: Node, size: Vector3, pos: Vector3, material: Material, collide := true, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if collide:
		var bs := BoxShape3D.new()
		bs.size = size
		_collider(mi, bs)
	return mi


static func cylinder(parent: Node, r_top: float, r_bottom: float, height: float, pos: Vector3, material: Material, collide := false, segments := 16, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = material
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if collide:
		var cs := CylinderShape3D.new()
		cs.radius = maxf(r_top, r_bottom)
		cs.height = height
		_collider(mi, cs)
	return mi


static func sphere(parent: Node, radius: float, pos: Vector3, material: Material, segments := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = segments
	sm.rings = segments / 2
	mi.mesh = sm
	mi.material_override = material
	parent.add_child(mi)
	mi.position = pos
	return mi


static func capsule(parent: Node, radius: float, height: float, pos: Vector3, material: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = height
	cm.radial_segments = 16
	cm.rings = 6
	mi.mesh = cm
	mi.material_override = material
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	return mi


## Quad vertical (face +Z), utile pour écrans, affiches, notes.
static func quad(parent: Node, size: Vector2, pos: Vector3, material: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.material_override = material
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	return mi


static func textured(path: String, unshaded := false, alpha := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(path)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	return m


# ------------------------------------------------------------------ modèles glTF
## Instancie un modèle Poly Haven. `fit` : {"height": h} | {"width": w} | {"depth": d} | {"scale": s},
## "collide": true pour une boîte de collision, "center": false pour garder l'origine d'origine.
## Chemin d'un modèle : "slug" Poly Haven, "sf:pack" Sketchfab, ou chemin res:// complet.
static func model_path(slug: String) -> String:
	if slug.begins_with("res://"):
		return slug
	if slug.begins_with("sf:"):
		var p := slug.substr(3)
		return "res://assets/sketchfab/%s/%s.glb" % [p, p]
	return "res://assets/models/%s/%s_1k.gltf" % [slug, slug]


## Instance "modèle" gardée en mémoire : chaque utilisation en fait une copie (bien plus rapide).
static var _templates := {}
## Modèles en carton / nourriture livrés avec des matériaux métalliques (ils brillaient comme du chrome).
const MATTE_MODELS := ["pizza_box", "pizza_open"]


static func _make_matte(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as StandardMaterial3D
			if m == null:
				continue
			var mm := m.duplicate() as StandardMaterial3D
			mm.metallic = 0.0
			mm.metallic_texture = null
			mm.roughness = 0.92
			mm.roughness_texture = null
			mm.metallic_specular = 0.2
			mi.set_surface_override_material(s, mm)


static func _template(path: String) -> Node3D:
	if _templates.has(path):
		return _templates[path]
	if not ResourceLoader.exists(path):
		return null
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var inst: Node3D = ps.instantiate()
	_clear_owner(inst)
	if path.get_file().get_basename() in MATTE_MODELS:
		_make_matte(inst)
	# sans ça, duplicate() ré-instancie la scène d'origine ET recopie les enfants (devenus sans
	# propriétaire) : chaque modèle existait en double (portes de la grille fantômes, rendu x2)
	inst.scene_file_path = ""
	_templates[path] = inst
	return inst


static func clear_templates() -> void:
	for k in _templates:
		var n: Node = _templates[k]
		if is_instance_valid(n):
			n.free()
	_templates.clear()


static func _clear_owner(n: Node) -> void:
	n.owner = null
	for c in n.get_children():
		_clear_owner(c)


## Fit en plus : "part" (garder seulement le nœud dont le nom commence par…),
## "remove" (liste de préfixes de nœuds à supprimer), "material" (matériau imposé).
static var profile := false


static func model(parent: Node, slug: String, pos: Vector3, rot_y_deg := 0.0, fit := {}) -> Node3D:
	var t0 := Time.get_ticks_usec()
	var r := _model(parent, slug, pos, rot_y_deg, fit)
	if profile:
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if ms > 40.0:
			print("  modèle %s %s : %.0f ms" % [slug, fit.get("part", ""), ms])
	return r


static func _model(parent: Node, slug: String, pos: Vector3, rot_y_deg := 0.0, fit := {}) -> Node3D:
	var path := model_path(slug)
	var holder := Node3D.new()
	holder.name = slug.get_file().get_basename().replace(":", "_")
	parent.add_child(holder)
	holder.position = pos
	holder.rotation_degrees.y = rot_y_deg
	var template := _template(path)
	if template == null:
		push_warning("Modèle introuvable : " + slug)
		return holder
	var inst: Node3D
	if fit.has("part"):
		var keep: Node3D = null
		for n in template.find_children("*", "Node3D", true, false):
			if String(n.name).begins_with(fit["part"]):
				keep = n
				break
		if keep != null:
			var copy: Node3D = keep.duplicate()
			inst = Node3D.new()
			inst.add_child(copy)
			copy.transform = _relative_xform(template, keep)
		else:
			push_warning("pièce introuvable : %s dans %s" % [fit["part"], slug])
			inst = template.duplicate()
	else:
		inst = template.duplicate()
	if fit.has("remove"):
		var doomed: Array[Node] = []
		for n in inst.find_children("*", "", true, false):
			for prefix in fit["remove"]:
				if String(n.name).begins_with(prefix):
					doomed.append(n)
					break
		for n in doomed:
			if is_instance_valid(n) and n.get_parent() != null:
				n.get_parent().remove_child(n)
				n.free()
	if fit.has("material"):
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = fit["material"]
	holder.add_child(inst)
	if fit.has("rot"):
		inst.rotation_degrees = fit["rot"]
	var aabb: AABB
	if fit.has("rot"):
		# rotation imposée : on mesure le modèle déjà tourné (sommets exacts)
		var probe := Node3D.new()
		var tmp := inst
		holder.remove_child(tmp)
		probe.add_child(tmp)
		aabb = local_aabb(probe, "%s|%s|%s|rot%s" % [path, fit.get("part", ""), fit.get("remove", []), fit["rot"]])
		probe.remove_child(tmp)
		holder.add_child(tmp)
		probe.free()
	else:
		aabb = local_aabb(inst, "%s|%s|%s" % [path, fit.get("part", ""), fit.get("remove", [])])
	var s := 1.0
	if fit.has("height"):
		s = float(fit["height"]) / maxf(aabb.size.y, 0.001)
	elif fit.has("width"):
		s = float(fit["width"]) / maxf(aabb.size.x, 0.001)
	elif fit.has("depth"):
		s = float(fit["depth"]) / maxf(aabb.size.z, 0.001)
	elif fit.has("scale"):
		s = float(fit["scale"])
	inst.scale = Vector3.ONE * s
	var c := aabb.get_center() * s
	if fit.get("center", true):
		inst.position = Vector3(-c.x, -aabb.position.y * s, -c.z)
	if str(fit.get("collide", false)) == "mesh":
		# collision à la forme exacte (meuble en un seul bloc : lit + bureau + chaise...)
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var shape := mi.mesh.create_trimesh_shape() if mi.mesh != null else null
			if shape != null:
				var sb := StaticBody3D.new()
				var cs := CollisionShape3D.new()
				cs.shape = shape
				sb.add_child(cs)
				mi.add_child(sb)
	elif fit.get("collide", false):
		var bs := BoxShape3D.new()
		bs.size = aabb.size * s
		_collider(holder, bs, Vector3(0, aabb.size.y * s * 0.5, 0))
	holder.set_meta("size", aabb.size * s)
	# de quoi recréer exactement ce modèle (éditeur de carte / sauvegarde de la disposition)
	var spec := {"model": slug, "scale": s, "center": fit.get("center", true), "collide": fit.get("collide", false)}
	if fit.has("part"):
		spec["part"] = fit["part"]
	if fit.has("remove"):
		spec["remove"] = fit["remove"]
	if fit.has("rot"):
		var r: Vector3 = fit["rot"]
		spec["rot"] = [r.x, r.y, r.z]
	holder.set_meta("spec", spec)
	return holder


## Boîte englobante exacte d'un modèle dans le repère de `root`.
## Une boîte transformée par une rotation quelconque est gonflée (objets qui flottent,
## mauvaise échelle) : dans ce cas on recalcule à partir des sommets. Résultat mis en cache.
static var _aabb_cache := {}


static func local_aabb(root: Node3D, cache_key := "") -> AABB:
	if cache_key != "" and _aabb_cache.has(cache_key):
		return _aabb_cache[cache_key]
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := _relative_xform(root, mi)
		var b: AABB
		if _axis_aligned(xf.basis):
			b = xf * mi.get_aabb()
		else:
			b = _vertex_aabb(mi.mesh, xf)
		if first:
			result = b
			first = false
		else:
			result = result.merge(b)
	if cache_key != "":
		_aabb_cache[cache_key] = result
	return result


static func _axis_aligned(b: Basis) -> bool:
	for c in [b.x, b.y, b.z]:
		var v: Vector3 = c
		var nz := 0
		for k in 3:
			if absf(v[k]) > 1e-4 * v.length():
				nz += 1
		if nz != 1:
			return false
	return true


static func _vertex_aabb(mesh: Mesh, xf: Transform3D) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for s in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			var p := xf * v
			lo = lo.min(p)
			hi = hi.max(p)
	if lo.x == INF:
		return xf * mesh.get_aabb()
	return AABB(lo, hi - lo)


static func _relative_xform(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func set_layers(root: Node, layer_mask: int) -> void:
	for node in root.find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = layer_mask
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers = layer_mask


static func set_shadows(root: Node, on: bool) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ------------------------------------------------------------------ lumières
static func omni(parent: Node, pos: Vector3, color: Color, energy: float, light_range: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.6
	l.shadow_enabled = shadow
	l.shadow_bias = 0.05
	l.shadow_normal_bias = 1.5
	l.light_volumetric_fog_energy = 0.8
	parent.add_child(l)
	l.position = pos
	return l


static func spot(parent: Node, pos: Vector3, target: Vector3, color: Color, energy: float, light_range: float, angle_deg: float, shadow := false) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.spot_range = light_range
	l.spot_angle = angle_deg
	l.shadow_enabled = shadow
	parent.add_child(l)
	l.position = pos
	if (target - pos).normalized().abs() != Vector3.UP:
		l.look_at_from_position(pos, target, Vector3.UP)
	else:
		l.look_at_from_position(pos, target, Vector3.FORWARD)
	return l


# ------------------------------------------------------------------ textes & décalcomanies
static func label3d(parent: Node, text: String, pos: Vector3, font_size := 32, color := Color.WHITE, rot_deg := Vector3.ZERO, font: Font = null, pixel := 0.002) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.modulate = color
	l.outline_size = 0
	l.pixel_size = pixel
	l.shaded = true
	l.double_sided = false
	if font != null:
		l.font = font
	parent.add_child(l)
	l.position = pos
	l.rotation_degrees = rot_deg
	return l


## Décalcomanie (graffiti, sang, crasse) projetée sur un mur ou le sol.
## `normal` = direction vers laquelle la surface regarde.
static func decal(parent: Node, tex_path: String, pos: Vector3, normal: Vector3, w: float, h: float, depth := 0.5, modulate := Color.WHITE) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex(tex_path)
	d.size = Vector3(w, depth, h)
	d.modulate = modulate
	d.normal_fade = 0.3
	d.cull_mask = 1
	var y := normal.normalized()
	var x := Vector3.RIGHT if absf(y.y) > 0.9 else Vector3.UP.cross(y).normalized()
	var z := x.cross(y).normalized()
	parent.add_child(d)
	d.transform = Transform3D(Basis(x, y, z), pos)
	return d
