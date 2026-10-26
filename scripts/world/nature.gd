class_name Nature
extends RefCounted
## Végétation procédurale : sapins (tronc + étages de branches en alpha) instanciés en masse,
## sol forestier, pluie en particules.

static var _needle_mat: StandardMaterial3D
static var _bark_mat: StandardMaterial3D


static func _materials() -> void:
	if _needle_mat != null:
		return
	_needle_mat = StandardMaterial3D.new()
	_needle_mat.albedo_texture = load("res://assets/gen/needles.png")
	_needle_mat.albedo_color = Color(0.32, 0.4, 0.33)
	_needle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_needle_mat.alpha_scissor_threshold = 0.45
	_needle_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_needle_mat.roughness = 0.9
	_needle_mat.uv1_scale = Vector3(3, 2, 1)
	_needle_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_bark_mat = B.mat("bark_willow", 1.0, {"triplanar": true, "world": false, "color": Color(0.6, 0.55, 0.5)})


## Maillage d'un sapin (deux surfaces : tronc, branches). Hauteur ~1, à mettre à l'échelle.
static func pine_mesh() -> ArrayMesh:
	_materials()
	var mesh := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.008
	trunk.bottom_radius = 0.03
	trunk.height = 1.0
	trunk.radial_segments = 7
	trunk.rings = 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, 0.5, 0)))
	mesh = st.commit()
	mesh.surface_set_material(0, _bark_mat)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tiers := 7
	for i in tiers:
		var t := float(i) / tiers
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = lerpf(0.28, 0.06, t)
		cone.height = lerpf(0.26, 0.16, t)
		cone.radial_segments = 9
		cone.rings = 1
		cone.cap_bottom = false
		var y := lerpf(0.22, 0.9, t) + cone.height * 0.35
		st2.append_from(cone, 0, Transform3D(Basis(Vector3.UP, i * 0.7), Vector3(0, y, 0)))
	st2.commit(mesh)
	mesh.surface_set_material(1, _needle_mat)
	return mesh


## Disperse des sapins dans un rectangle, en évitant les zones où `avoid(pos)` est vrai.
static func scatter_pines(parent: Node, area: Rect2, count: int, avoid: Callable, seed := 7, min_h := 9.0, max_h := 19.0) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < count and tries < count * 6:
		tries += 1
		var p := Vector3(rng.randf_range(area.position.x, area.end.x), 0, rng.randf_range(area.position.y, area.end.y))
		if avoid.is_valid() and avoid.call(p):
			continue
		var h := rng.randf_range(min_h, max_h)
		var w := h * rng.randf_range(0.75, 1.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, h, w))
		transforms.append(Transform3D(b, p + Vector3(0, -0.2, 0)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pine_mesh()
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)
	return mmi


## Fusionne un modèle (ou une de ses pièces) en un seul ArrayMesh normalisé :
## hauteur 1, base à y=0, centré. Les feuillages transparents passent en "alpha scissor".
static var _mesh_cache := {}


static func mesh_from_model(slug: String, part := "") -> ArrayMesh:
	var key := slug + "|" + part
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var inst: Node3D = (load(B.model_path(slug)) as PackedScene).instantiate()
	var root: Node3D = inst
	if part != "":
		for n in inst.find_children("*", "Node3D", true, false):
			if String(n.name).begins_with(part):
				root = n
				break
	var aabb := B.local_aabb(root)
	var s := 1.0 / maxf(aabb.size.y, 0.001)
	var c := aabb.get_center()
	var norm := Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(-c.x * s, -aabb.position.y * s, -c.z * s))
	var mesh := ArrayMesh.new()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var xf := norm * B._relative_xform(root, mi)
		for si in mi.mesh.get_surface_count():
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.append_from(mi.mesh, si, xf)
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
			var mat := mi.get_active_material(si)
			if mat is StandardMaterial3D:
				var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				if m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA or m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					m.alpha_scissor_threshold = 0.45
				if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.albedo_color = m.albedo_color * Color(0.75, 0.8, 0.75)
				mat = m
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	inst.free()
	_mesh_cache[key] = mesh
	return mesh


## Forêt réaliste : plusieurs espèces (modèles Sketchfab) dispersées par MultiMesh.
## `kinds` : [[slug, part, poids, h_min, h_max], ...]
## Renvoie les troncs posés : [position, rayon] (arbres et rochers ; pas les buissons ni les jeunes pousses),
## pour leur donner une collision et en faire des obstacles (créature, regard d'un personnage).
## `chunk` : taille des parcelles masquées d'un bloc au-delà de `view_dist` ; `fade` : elles apparaissent en fondu.
static func scatter_forest(parent: Node, area: Rect2, count: int, avoid: Callable, seed := 7, kinds: Array = [], ground := Callable(), view_dist := 150.0, chunk := 50.0, fade := false) -> Array:
	if kinds.is_empty():
		kinds = [
			["sf:pine_tree", "", 5.0, 11.0, 20.0],
			["sf:conifer_pack", "FirTree", 2.0, 12.0, 22.0],
			["sf:conifer_pack", "PineTree", 2.0, 12.0, 20.0],
			["sf:conifer_pack", "NobleFirTree", 1.0, 4.0, 8.0],
			["sf:conifer_pack", "Coniferous Dead Tree_", 0.4, 9.0, 15.0],
			["sf:conifer_pack", "ConiferousShrub", 1.0, 1.0, 2.2],
			["sf:conifer_pack", "Coniferous Sapling", 0.8, 1.2, 2.6],
			["sf:conifer_pack", "BoulderMossyLarge", 0.4, 0.8, 1.6],
		]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var total_w := 0.0
	for k in kinds:
		total_w += float(k[2])
	var buckets: Array = []
	for k in kinds:
		buckets.append([])
	var tries := 0
	var placed := 0
	var trunks: Array = []
	while placed < count and tries < count * 6:
		tries += 1
		var p := Vector3(rng.randf_range(area.position.x, area.end.x), 0, rng.randf_range(area.position.y, area.end.y))
		if avoid.is_valid() and avoid.call(p):
			continue
		var r := rng.randf() * total_w
		var ki := 0
		for i in kinds.size():
			r -= float(kinds[i][2])
			if r <= 0.0:
				ki = i
				break
		var h := rng.randf_range(float(kinds[ki][3]), float(kinds[ki][4]))
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(h * rng.randf_range(0.85, 1.15), h, h * rng.randf_range(0.85, 1.15)))
		if ground.is_valid():
			p.y = ground.call(p)
		buckets[ki].append(Transform3D(b, p + Vector3(0, -0.15, 0)))
		placed += 1
		var part: String = kinds[ki][1]
		if part.begins_with("Boulder"):
			trunks.append([p, h * 0.5])
		elif not (part.contains("Shrub") or part.contains("Sapling")):
			trunks.append([p, clampf(h * 0.017, 0.12, 0.38)])
	# découpage en parcelles : chaque parcelle est masquée hors champ et au-delà de VIEW_DIST
	var CHUNK := chunk
	var VIEW_DIST := view_dist
	for i in kinds.size():
		if buckets[i].is_empty():
			continue
		var mesh := mesh_from_model(kinds[i][0], kinds[i][1])
		var chunks := {}
		for xf in buckets[i]:
			var key := Vector2i(int(floor(xf.origin.x / CHUNK)), int(floor(xf.origin.z / CHUNK)))
			if not chunks.has(key):
				chunks[key] = []
			chunks[key].append(xf)
		for key in chunks:
			var list: Array = chunks[key]
			var center := Vector3((key.x + 0.5) * CHUNK, 0, (key.y + 0.5) * CHUNK)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = list.size()
			for j in list.size():
				var t: Transform3D = list[j]
				t.origin -= center
				mm.set_instance_transform(j, t)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.visibility_range_end = VIEW_DIST
			mmi.visibility_range_end_margin = 10.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if fade else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			parent.add_child(mmi)
			mmi.global_position = center
	return trunks


## Grand sol texturé avec collision.
static func ground(parent: Node, size: float, slug: String, tile: float, center := Vector3.ZERO, color := Color.WHITE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	mi.mesh = pm
	mi.material_override = B.mat(slug, tile, {"color": color})
	parent.add_child(mi)
	mi.position = center
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size, 1.0, size)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	mi.add_child(sb)
	return mi


## Pluie : traits fins éclairés uniquement par les lumières (phares, porche...).
static func rain(parent: Node, extents: Vector3, amount := 5000) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.15
	p.preprocess = 1.2
	p.visibility_aabb = AABB(Vector3(-extents.x, -16.0, -extents.z) * 1.2, Vector3(extents.x * 2.4, 18.0, extents.z * 2.4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# les gouttes naissent dans une couche fine en hauteur (au-dessus des toits) et tombent :
	# ainsi les collisions (toit de la maison) les arrêtent avant l'intérieur
	pm.emission_box_extents = Vector3(extents.x, 0.5, extents.z)
	pm.direction = Vector3(0.08, -1, 0.03)
	pm.spread = 3.0
	pm.initial_velocity_min = 11.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3(0, -4, 0)
	pm.particle_flag_align_y = true
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.008, 0.38)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.8, 0.85, 0.32)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	p.draw_pass_1 = q
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


## Poussière en suspension : de fines particules qui flottent et ne se voient que dans la lumière
## (faisceau de la lampe, clair de lune des puits). L'émetteur suit le joueur ; les grains, eux,
## restent en place dans le monde.
static func dust(parent: Node, extents: Vector3, amount := 700) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.local_coords = false
	p.visibility_aabb = AABB(-extents * 1.5, extents * 3.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(0.3, 0.05, 0.2)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.005
	pm.initial_velocity_max = 0.035
	# un rien plus lourd que l'air : la plupart descendent très lentement, certains remontent
	pm.gravity = Vector3(0, -0.003, 0)
	# l'air bouge à peine : lentes volutes, chaque grain dérive à sa façon
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.9
	pm.turbulence_noise_scale = 1.6
	pm.turbulence_noise_speed = Vector3(0.025, 0.012, 0.02)
	pm.turbulence_influence_min = 0.04
	pm.turbulence_influence_max = 0.14
	pm.scale_min = 0.35
	pm.scale_max = 1.6
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	# éclat variable : poussières, fibres, petites peluches, plus ou moins claires
	var tint := Gradient.new()
	tint.set_color(0, Color(0.7, 0.68, 0.62, 0.35))
	tint.set_color(1, Color(1.0, 0.97, 0.9, 1.0))
	tint.add_point(0.6, Color(0.88, 0.85, 0.78, 0.7))
	var tint_t := GradientTexture1D.new()
	tint_t.gradient = tint
	pm.color_initial_ramp = tint_t
	# apparition / disparition en douceur
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.12, Color(1, 1, 1, 1))
	fade.add_point(0.88, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.0055, 0.0055)
	# grain rond, bord adouci (éclairé seulement par la lampe et les luminaires)
	var dot := Gradient.new()
	dot.set_color(0, Color(1, 1, 1, 1))
	dot.set_color(1, Color(1, 1, 1, 0))
	dot.add_point(0.4, Color(1, 1, 1, 0.8))
	var disc := GradientTexture2D.new()
	disc.gradient = dot
	disc.fill = GradientTexture2D.FILL_RADIAL
	disc.fill_from = Vector2(0.5, 0.5)
	disc.fill_to = Vector2(1.0, 0.5)
	disc.width = 32
	disc.height = 32
	var m := StandardMaterial3D.new()
	m.albedo_texture = disc
	m.albedo_color = Color(0.9, 0.87, 0.8, 0.7)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


## Quelques grains de poussière tout près de l'objectif : hors de la mise au point, ils deviennent de
## grosses taches rondes, floues et pâles dans le faisceau (les « orbes » des vidéos de caméra-piéton).
static func dust_bokeh(parent: Node, amount := 14) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.spread = 180.0
	pm.initial_velocity_min = 0.005
	pm.initial_velocity_max = 0.03
	pm.gravity = Vector3(0, -0.002, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 1.2
	pm.turbulence_noise_speed = Vector3(0.03, 0.015, 0.03)
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.12
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.25, Color(1, 1, 1, 1))
	fade.add_point(0.75, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	# disque de flou : plat, bord légèrement plus clair, puis fondu
	var bok := Gradient.new()
	bok.set_color(0, Color(1, 1, 1, 0.55))
	bok.set_color(1, Color(1, 1, 1, 0))
	bok.add_point(0.7, Color(1, 1, 1, 0.7))
	bok.add_point(0.85, Color(1, 1, 1, 0.35))
	var disc := GradientTexture2D.new()
	disc.gradient = bok
	disc.fill = GradientTexture2D.FILL_RADIAL
	disc.fill_from = Vector2(0.5, 0.5)
	disc.fill_to = Vector2(1.0, 0.5)
	disc.width = 64
	disc.height = 64
	var m := StandardMaterial3D.new()
	m.albedo_texture = disc
	m.albedo_color = Color(0.9, 0.88, 0.82, 0.045)
	# trop près de l'objectif (contre la lampe), ils s'effacent au lieu de faire des billes blanches
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.35
	m.distance_fade_max_distance = 1.0
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p


## Essaim de mouches autour d'un corps : petites, rapides, trajectoires en zigzag, elles ne
## s'éloignent jamais (un attracteur les ramène) ; étirées dans le sens du vol comme sur une vidéo.
static func flies(parent: Node, pos: Vector3, amount := 18) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.5
	p.preprocess = 2.5
	p.visibility_aabb = AABB(Vector3(-1.5, -1.0, -1.5), Vector3(3.0, 2.5, 3.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.3
	pm.damping_max = 0.8
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 7.0
	pm.turbulence_noise_scale = 0.3
	pm.turbulence_noise_speed = Vector3(1.6, 1.2, 1.6)
	pm.turbulence_influence_min = 0.55
	pm.turbulence_influence_max = 0.9
	pm.particle_flag_align_y = true
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.06, Color(1, 1, 1, 1))
	fade.add_point(0.94, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	# deux petits rubans croisés, étirés dans le sens du vol (visibles sous tous les angles)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var ax := Vector3(0.0028, 0, 0) if k == 0 else Vector3(0, 0, 0.0028)
		var up := Vector3(0, 0.009, 0)
		var a := -ax - up
		var b := ax - up
		var c := ax + up
		var d := -ax + up
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.035, 0.035, 0.03)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.35
	m.metallic_specular = 0.6
	mesh.surface_set_material(0, m)
	p.draw_pass_1 = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	# l'essaim reste groupé autour du corps
	var att := GPUParticlesAttractorSphere3D.new()
	att.radius = 0.9
	att.strength = 5.0
	att.attenuation = 0.6
	p.add_child(att)
	return p


## Jet de vapeur (fuite sur une canalisation), dirigé selon `dir`.
static func steam(parent: Node, pos: Vector3, dir: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 110
	p.lifetime = 1.6
	p.preprocess = 1.6
	p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 14.0
	pm.initial_velocity_min = 3.2
	pm.initial_velocity_max = 4.4
	pm.gravity = Vector3(0, 0.8, 0)
	pm.damping_min = 2.6
	pm.damping_max = 3.6
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.1))
	grow.add_point(Vector2(1, 2.2))
	var grow_t := CurveTexture.new()
	grow_t.curve = grow
	pm.scale_curve = grow_t
	var fade := Gradient.new()
	# presque invisible à la sortie du tuyau, puis un voile léger qui se dissipe
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.08, Color(1, 1, 1, 0.24))
	fade.add_point(0.45, Color(1, 1, 1, 0.12))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.4, 0.4)
	var puff := Gradient.new()
	puff.set_color(0, Color(1, 1, 1, 1))
	puff.set_color(1, Color(1, 1, 1, 0))
	puff.add_point(0.35, Color(1, 1, 1, 0.3))
	var tex := GradientTexture2D.new()
	tex.gradient = puff
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(0.8, 0.82, 0.84, 0.6)
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.4
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	var d := dir.normalized()
	p.global_transform = Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.FORWARD), pos)
	return p


## Quelques feuilles mortes qui tombent en tournoyant dans un puits et restent un moment au sol
## (`ground` donne la hauteur du sol ou de l'eau sous un point).
static func leaves(parent: Node, pos: Vector3, ground: Callable, amount := 7) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.065)
	var shape := Gradient.new()
	shape.set_color(0, Color(1, 1, 1, 1))
	shape.set_color(1, Color(1, 1, 1, 0))
	shape.add_point(0.75, Color(1, 1, 1, 1))
	var tex := GradientTexture2D.new()
	tex.gradient = shape
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	for k in amount:
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.albedo_color = Color(0.42, 0.27, 0.12).lerp(Color(0.3, 0.22, 0.1), randf())
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.9
		var leaf := MeshInstance3D.new()
		leaf.mesh = q
		leaf.material_override = m
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		leaf.visible = false
		root.add_child(leaf)
		var start := pos + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
		var land := Vector3(start.x + randf_range(-0.6, 0.6), 0.0, start.z + randf_range(-0.6, 0.6))
		land.y = float(ground.call(land)) + 0.01 + k * 0.002
		var dur := (pos.y - land.y) / randf_range(0.9, 1.4)
		var phase := randf() * TAU
		var amp := randf_range(0.15, 0.35)
		var spin := randf_range(2.0, 4.0)
		leaf.global_position = start
		var tw := leaf.create_tween()
		tw.tween_interval(randf_range(0.0, 1.8))
		tw.tween_callback(leaf.show)
		# chute lente en zigzag, la feuille tourne sur elle-même puis se pose à plat
		tw.tween_method(func(f: float) -> void:
			var w := f * dur
			var flat := smoothstep(0.85, 1.0, f)
			leaf.global_position = start.lerp(land, f) + Vector3(sin(w * 2.3 + phase), 0, cos(w * 1.9 + phase)) * amp * (1.0 - flat)
			leaf.rotation = Vector3(lerpf(sin(w * spin + phase) * 1.3, -PI / 2, flat), w * spin * 0.7 + phase, lerpf(cos(w * spin * 0.8) * 0.8, 0.0, flat)),
			0.0, 1.0, dur)
		tw.tween_interval(randf_range(15.0, 25.0))
		tw.tween_callback(leaf.queue_free)
	root.get_tree().create_timer(45.0).timeout.connect(root.queue_free)
	return root
