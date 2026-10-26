class_name Level
extends Node3D
## Base de tous les niveaux : environnement, joueur, outils de mise en scène
## (attentes, conditions, déclencheurs de zone).

signal ticked(delta: float)

var params := {}
var player: Player
var world_env: WorldEnvironment
var env: Environment
var cam_attr: CameraAttributesPractical
var _triggers: Array = []
## Documents déjà lus (relisibles depuis l'inventaire) : {"title", "text", "style"}.
var documents: Array = []


## Ce que Théo porte : [{"id", "name", "count", "desc", "icon"}] — à surcharger par niveau.
func inventory() -> Array:
	return []


## Affiche un document et le range dans l'inventaire (une seule fois par titre).
func read_document(title: String, text: String, style := "paper") -> void:
	var known := false
	for d in documents:
		if d["title"] == title:
			known = true
	if not known:
		documents.append({"title": title, "text": text, "style": style})
	await Game.ui.show_document(text, style)


func _process(delta: float) -> void:
	_check_triggers()
	ticked.emit(delta)


# ------------------------------------------------------------------ mise en scène
## Attend `sec` secondes (en pause si le jeu est en pause ; annulé si le niveau est détruit).
## Matériaux et modèles des nœuds de préchauffage, gardés en mémoire : Godot jette un shader compilé dès que plus
## aucun matériau ne s'en sert (il faudrait le recompiler au moment de l'événement).
var _prewarm_keep: Array = []


## Ce que ce niveau fera apparaître plus tard (créature, effets...) : dessiné une fois pendant le préchauffage.
## Les nœuds créés exprès portent la méta "prewarm_temp" : posés devant la caméra, puis libérés.
func prewarm_extras() -> Array:
	return []


## Anti micro-freezes. Un matériau, un modèle ou un effet que la carte graphique n'a encore jamais dessiné doit
## d'abord être compilé : un à-coup de 50 à 150 ms au moment où il apparaît (le premier cafard, la créature qui
## surgit, la poussière d'un éboulement, l'homme au masque...). Derrière l'écran de chargement (jeu en pause),
## une caméra temporaire fait le tour complet de la scène (sans occlusion, tout le niveau est dessiné), puis
## chaque nœud de prewarm_extras() passe devant elle (et revient à sa place). Tout est compilé avant que le
## joueur ne le croise.
func prewarm() -> void:
	# point de vue : la tête de Théo, ou la caméra active (voiture, cinématique de fin)
	var prev := get_viewport().get_camera_3d()
	if player == null and prev == null:
		return
	var origin := player.head.global_position if player != null else prev.global_position
	var cam := Camera3D.new()
	cam.fov = 120.0
	cam.near = 0.05
	add_child(cam)
	cam.global_position = origin
	cam.make_current()
	for e: Vector3 in [Vector3.ZERO, Vector3(0, 90, 0), Vector3(0, 180, 0), Vector3(0, 270, 0), Vector3(-80, 0, 0), Vector3(80, 0, 0)]:
		cam.global_rotation_degrees = e
		await RenderingServer.frame_post_draw
	cam.global_rotation_degrees = Vector3(-20, 0, 0)
	var front := cam.global_position - cam.global_basis.z * 2.0 + Vector3(0, -0.6, 0)
	# chaque nœud est amené devant la caméra, sous deux lampes à ombres (omni + spot) : la version « ombre »
	# de ses matériaux est compilée aussi (sinon : à-coup quand la créature entre dans la lumière d'une lampe)
	var omni := OmniLight3D.new()
	omni.omni_range = 8.0
	omni.light_energy = 0.3
	omni.shadow_enabled = true
	add_child(omni)
	omni.global_position = cam.global_position + Vector3(0, 0.5, 0)
	var spot := SpotLight3D.new()
	spot.spot_range = 8.0
	spot.light_energy = 0.3
	spot.shadow_enabled = true
	add_child(spot)
	spot.global_transform = cam.global_transform
	for n in prewarm_extras():
		var node := n as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var temp := node.has_meta("prewarm_temp")
		var was := node.visible
		var xf := node.global_transform
		node.visible = true
		node.global_position = front
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if not is_instance_valid(node):
			continue
		if temp:
			_keep_resources(node)
			node.queue_free()
		else:
			node.global_transform = xf
			node.visible = was
	omni.queue_free()
	spot.queue_free()
	cam.queue_free()
	if is_instance_valid(prev):
		prev.make_current()


func _keep_resources(node: Node) -> void:
	for n in [node] + node.find_children("*", "", true, false):
		if n is GPUParticles3D:
			_prewarm_keep.append_array([(n as GPUParticles3D).process_material, (n as GPUParticles3D).draw_pass_1])
		if n is GeometryInstance3D and (n as GeometryInstance3D).material_override != null:
			_prewarm_keep.append((n as GeometryInstance3D).material_override)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			_prewarm_keep.append(mi.mesh)
			for si in mi.get_surface_override_material_count():
				if mi.get_surface_override_material(si) != null:
					_prewarm_keep.append(mi.get_surface_override_material(si))


func wait(sec: float) -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = maxf(sec, 0.01)
	add_child(t)
	t.start()
	await t.timeout
	t.queue_free()


## Attend qu'une condition devienne vraie.
func wait_until(cond: Callable) -> void:
	while not cond.call():
		await ticked


## Déclencheur : appelle `cb` une fois quand le joueur entre dans la sphère.
func add_trigger(pos: Vector3, radius: float, cb: Callable, once := true) -> Dictionary:
	var t := {"pos": pos, "r": radius, "cb": cb, "once": once, "done": false, "inside": false}
	_triggers.append(t)
	return t


func _check_triggers() -> void:
	if player == null:
		return
	var p := player.global_position
	for t in _triggers:
		if t["done"]:
			continue
		var pos: Vector3 = t["pos"]
		var inside := Vector2(p.x - pos.x, p.z - pos.z).length() < float(t["r"])
		if inside and not t["inside"]:
			if t["once"]:
				t["done"] = true
			(t["cb"] as Callable).call()
		t["inside"] = inside


func spawn_player(pos: Vector3, yaw_deg: float) -> Player:
	player = Player.new()
	add_child(player)
	player.global_position = pos
	player.set_look(deg_to_rad(yaw_deg), 0.0)
	# options de test : --warp=x,z --yaw=deg --pitch=deg
	if Game.args.has("warp"):
		var w := str(Game.args["warp"]).split(",")
		player.global_position = Vector3(float(w[0]), pos.y, float(w[1]))
		if has_method("floor_y"):
			player.global_position.y = call("floor_y", player.global_position) + 0.05
	if Game.args.has("yaw") or Game.args.has("pitch"):
		player.set_look(deg_to_rad(float(Game.args.get("yaw", yaw_deg))), deg_to_rad(float(Game.args.get("pitch", 0.0))))
	return player


## Surface sous un point (pour les bruits de pas) — à surcharger.
func get_surface(_pos: Vector3) -> String:
	return "concrete"


## Le joueur a fait du bruit (pas, objets) — à surcharger (la créature écoute).
func on_noise(_pos: Vector3, _radius: float) -> void:
	pass


# ------------------------------------------------------------------ environnement
func make_environment(cfg: Dictionary) -> void:
	world_env = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = cfg.get("bg", Color(0, 0, 0))
	if cfg.has("sky"):
		env.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		sky.sky_material = cfg["sky"]
		env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = cfg.get("ambient", Color(0.02, 0.02, 0.025))
	env.ambient_light_energy = cfg.get("ambient_energy", 1.0)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = cfg.get("exposure", 1.0)
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = cfg.get("glow", 0.9)
	env.glow_strength = 1.0
	env.glow_bloom = cfg.get("bloom", 0.04)
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = cfg.get("ssao", true)
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.ssil_enabled = cfg.get("ssil", false)
	env.ssr_enabled = cfg.get("ssr", false)
	env.ssr_max_steps = 48
	env.fog_enabled = cfg.get("fog", false)
	env.fog_light_color = cfg.get("fog_color", Color(0.05, 0.06, 0.07))
	env.fog_density = cfg.get("fog_density", 0.02)
	env.fog_sky_affect = 1.0
	env.volumetric_fog_enabled = cfg.get("vfog", false)
	env.volumetric_fog_density = cfg.get("vfog_density", 0.03)
	env.volumetric_fog_albedo = cfg.get("vfog_albedo", Color(0.6, 0.62, 0.65))
	env.volumetric_fog_anisotropy = cfg.get("vfog_aniso", 0.5)
	env.volumetric_fog_length = cfg.get("vfog_length", 48.0)
	env.volumetric_fog_ambient_inject = cfg.get("vfog_ambient", 0.0)
	env.volumetric_fog_emission = cfg.get("vfog_emission", Color(0, 0, 0))
	env.adjustment_enabled = true
	env.adjustment_contrast = cfg.get("contrast", 1.08)
	env.adjustment_saturation = cfg.get("saturation", 1.0)
	world_env.environment = env
	cam_attr = CameraAttributesPractical.new()
	cam_attr.auto_exposure_enabled = cfg.get("auto_exposure", true)
	cam_attr.auto_exposure_scale = cfg.get("ae_scale", 0.35)
	cam_attr.auto_exposure_speed = cfg.get("ae_speed", 0.8)
	cam_attr.auto_exposure_min_sensitivity = cfg.get("ae_min", 50.0)
	cam_attr.auto_exposure_max_sensitivity = cfg.get("ae_max", 1600.0)
	world_env.camera_attributes = cam_attr
	add_child(world_env)
