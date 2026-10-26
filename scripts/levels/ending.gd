extends Level
## Chapitre final — Surface.
## Théo sort par une bouche d'égout au petit matin, dans la forêt. Sur le sentier : des traces des treize sessions
## d'avant, des pièges à loup sous les feuilles, un drone qui le filme pour le direct. La caméra d'une victime
## parle d'une cabane avec une radio ; la radio est morte, il faut une batterie... au camp des ravisseurs (régie,
## écrans, dossiers, dons, son propre téléphone). Prendre la batterie fait sortir l'homme au masque du van : il
## voit mais entend mal. À la radio, la voix qui répond est celle du direct : « Ouvrez la trappe. » La créature
## sort de la plaque « S·13 » : course jusqu'à la route... où une caméra sur un poteau se tourne vers lui.

const ROAD_Z := -52.0
const POLE := Vector3(3.5, 0, -47.5)
const HUT := Vector3(-24.0, 0, -19.0)  ## cabane du garde forestier (porte à l'est)
const CAMP := Vector3(28.0, 0, -31.0)  ## camp des ravisseurs
const S13 := Vector3(-6.5, 0, -10.0)  ## plaque d'égout « S·13 » (la créature en sortira)
const CAM13 := Vector3(-2.3, 0, -13.4)  ## caméra-piéton de la victime de la session 13
const TRAIL := [Vector3(0, 0, 3), Vector3(-1.5, 0, -8), Vector3(1.0, 0, -17), Vector3(-0.5, 0, -27), Vector3(1.0, 0, -38), Vector3(0, 0, -50)]
const HUT_PATH := [Vector3(0.8, 0, -16.5), Vector3(-9.0, 0, -19.5), Vector3(-19.5, 0, -19.0)]
const CAMP_PATH := [Vector3(-0.3, 0, -27.0), Vector3(10.0, 0, -29.5), Vector3(20.0, 0, -31.0)]
const TRAPS := [Vector3(-1.1, 0, -12.2), Vector3(0.7, 0, -21.5), Vector3(-12.8, 0, -19.4), Vector3(14.6, 0, -30.1), Vector3(0.3, 0, -33.8)]
const STONES := [Vector3(1.7, 0, -3.5), Vector3(-2.2, 0, -16.0), Vector3(-15.5, 0, -17.6), Vector3(7.5, 0, -28.2), Vector3(-1.8, 0, -31.0), Vector3(21.0, 0, -26.5)]
## ronde de l'homme au masque : autour du camp, jusqu'au sentier, et vers la cabane
const ROUTE := [Vector3(22.0, 0, -29.5), Vector3(14.0, 0, -29.8), Vector3(5.0, 0, -28.5), Vector3(0.5, 0, -22.0),
	Vector3(-6.0, 0, -19.4), Vector3(-1.0, 0, -26.0), Vector3(9.0, 0, -29.6), Vector3(30.0, 0, -24.0), Vector3(33.0, 0, -35.0)]

var pole_cam: SecurityCamera
var revealed := false
var wind: AudioStreamPlayer
var stage := "start"  ## start → battery (radio morte : il faut une batterie) → carry (il la rapporte) → chase → done
var has_battery := false
var battery_in := false
var stones := 0
var dying := false
var trunks: Array = []
var creature: Creature
var hunter: Hunter
var drone: Drone
var drones_left := 2
var feed: SecurityFeed
var _feed_mat: ShaderMaterial
var _trunk_grid := {}
var _traps: Array = []  ## [nœud, position, déclenché]
var _knows_hut := false
var _road_said := false
var _radio_glow: OmniLight3D
var _radio_static: AudioStreamPlayer3D
var _battery_node: Node3D
var _battery_slot: Node3D
var _van: Node3D
var _drone_cd := 25.0
var _report_cd := 8.0
var _phone_done := false


func _ready() -> void:
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.05, 0.07, 0.13)
	sky.sky_horizon_color = Color(0.32, 0.3, 0.33)
	sky.ground_horizon_color = Color(0.12, 0.12, 0.13)
	sky.ground_bottom_color = Color(0.02, 0.02, 0.02)
	sky.sky_energy_multiplier = 0.9
	make_environment({
		"sky": sky,
		"ambient": Color(0.09, 0.1, 0.13),
		"ambient_energy": 0.8,
		"fog": true,
		"fog_color": Color(0.1, 0.11, 0.13),
		"fog_density": 0.026,
		"vfog": true,
		"vfog_density": 0.014,
		"vfog_albedo": Color(0.6, 0.62, 0.68),
		"vfog_length": 80.0,
		"auto_exposure": false,
		"exposure": 1.9,
	})
	var dawn := DirectionalLight3D.new()
	dawn.light_color = Color(0.55, 0.62, 0.8)
	dawn.light_energy = 0.55
	dawn.rotation_degrees = Vector3(-12, -150, 0)
	add_child(dawn)
	Game.set_fx("grain", 0.05)
	Game.set_fx("gain", 0.4)
	Game.set_fx("saturation", 0.6)
	Game.set_fx("tint", Color(0.92, 0.96, 1.05))
	Sound.set_reverb(0.2, 0.05, 0.8)
	Game.set_clock(5, 47, 12, 15)

	Nature.ground(self, 400.0, "brown_mud_leaves_01", 3.0, Vector3(0, -0.01, -20), Color(0.6, 0.6, 0.55))
	trunks = Nature.scatter_forest(self, Rect2(-120, -150, 240, 260), 1100, _keep_clear, 33)
	trunks.append_array(Nature.scatter_forest(self, Rect2(-62, -62, 124, 82), 520, _keep_clear, 61))
	_build_trunk_colliders()
	_build_exit_and_road()
	_build_traces()
	_build_hut()
	_build_camp()
	for p: Vector3 in TRAPS:
		_build_trap(p)
	for p: Vector3 in STONES:
		_build_stones(p)
	_build_bounds()

	creature = Creature.new()
	creature.nav = self
	add_child(creature)
	creature.deactivate()
	creature.caught_player.connect(func() -> void: _die("creature"))
	hunter = Hunter.new()
	hunter.level = self
	hunter.camp = CAMP
	hunter.route = ROUTE
	add_child(hunter)
	hunter.global_position = CAMP + Vector3(3.0, 0, -4.0)

	var cp := str(params.get("checkpoint", Game.args.get("checkpoint", "")))
	drones_left = int(params.get("drones", 2))
	match cp:
		"carry":
			# reprise : sur le chemin du camp, hors de sa vue ; lui repart de l'autre côté
			player = spawn_player(Vector3(11.0, 0, -29.6), 90.0)
			_setup_player()
			has_battery = true
			stones = 4
			stage = "carry"
			_battery_node.queue_free()
			Game.ui.fade_rect.color.a = 0.0
			Game.hud.objective("Rapporter la batterie à la cabane, sans te faire voir")
			hunter.wake(false)
			hunter.wp = 7
			var away: Vector3 = ROUTE[7] - hunter.global_position
			hunter.heading = atan2(-away.x, -away.z)
			_drone_cd = 6.0
		"chase":
			player = spawn_player(HUT + Vector3(0.6, 0, 0.4), -90.0)
			_setup_player()
			battery_in = true
			stage = "chase"
			_battery_node.queue_free()
			_install_battery_visual()
			Game.ui.fade_rect.color.a = 0.0
			_release_creature(true)
		_:
			player = spawn_player(Vector3(0, 0, 0.9), 0.0)
			_setup_player()
			_play()
	pole_cam.target = player
	add_trigger(Vector3(0.0, 0, ROAD_Z + 3.0), 9.0, _at_road, false)
	add_trigger(HUT + Vector3(4.0, 0, 0), 4.0, func() -> void:
		if stage == "start" and not _knows_hut:
			Game.hud.say("Une cabane... Il y a peut-être quelqu'un. Ou un téléphone.", 3.2))
	add_trigger(CAMP + Vector3(-8.0, 0, 0), 9.0, func() -> void:
		if stage in ["start", "battery"]:
			Game.hud.say("Un groupe électrogène... Des écrans. C'est leur camp.", 3.2))
	# test : --freecam=x,y,z --freelook=x,y,z → caméra libre (inspection d'un détail)
	if Game.args.has("freecam"):
		var fc := Camera3D.new()
		fc.fov = float(Game.args.get("freefov", 50.0))
		add_child(fc)
		var a3 := str(Game.args["freecam"]).split(",")
		var b3 := str(Game.args.get("freelook", "0,0,0")).split(",")
		fc.look_at_from_position(Vector3(float(a3[0]), float(a3[1]), float(a3[2])), Vector3(float(b3[0]), float(b3[1]), float(b3[2])))
		fc.current = true
	if Game.args.has("torch"):
		player.set_flashlight(true, true)
	if Game.args.has("surfacetest"):
		_surface_test(str(Game.args["surfacetest"]))


func _setup_player() -> void:
	player.has_flashlight = true
	Game.hud.show_hud(true)
	Game.hud.set_battery(1)


func inventory() -> Array:
	var items: Array = [{"id": "flashlight", "name": "Lampe torche", "desc": "Ta lampe de service. [F] pour l'allumer."}]
	if stones > 0:
		items.append({"id": "stone", "name": "Cailloux", "count": stones, "desc": "À lancer ([G] ou clic droit) : sur le drone, ou loin de toi pour détourner l'homme au masque."})
	if has_battery:
		items.append({"id": "battery", "name": "Batterie 12 V", "desc": "Lourde. Pour la radio de la cabane."})
	return items


func get_surface(_pos: Vector3) -> String:
	return "grass"


func _play() -> void:
	Game.ui.fade_rect.color = Color(1, 1, 1, 1)
	wind = Sound.loop("wind_loop", -10.0)
	Sound.loop("birds_loop", -16.0)
	var tw := create_tween()
	tw.tween_property(Game.ui.fade_rect, "color:a", 0.0, 2.5)
	await tw.finished
	Game.ui.fade_rect.color = Color(0, 0, 0, 0)
	Game.hud.say("J'suis sorti... J'suis sorti !", 3.0)
	await wait(3.5)
	Game.hud.say("Une route. Il faut que je trouve quelqu'un.", 3.0)
	Game.hud.objective("Trouver de l'aide")


# ================================================================== forêt
func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * t).length()


func _near_path(p: Vector3, path: Array, w: float) -> bool:
	for i in path.size() - 1:
		if _seg_dist(p, path[i], path[i + 1]) < w:
			return true
	return false


## Pas d'arbre sur les sentiers, dans les clairières (cabane, camp), autour des plaques d'égout et sur la route.
func _keep_clear(p: Vector3) -> bool:
	if _near_path(p, TRAIL, 2.6) or _near_path(p, HUT_PATH, 2.0) or _near_path(p, CAMP_PATH, 2.2):
		return true
	if Vector2(p.x - HUT.x, p.z - HUT.z).length() < 6.5 or Vector2(p.x - CAMP.x, p.z - CAMP.z).length() < 11.5:
		return true
	if Vector2(p.x, p.z).length() < 4.0 or Vector2(p.x - S13.x, p.z - S13.z).length() < 2.5:
		return true
	return absf(p.z - ROAD_Z) < 6.0 or Vector2(p.x - POLE.x, p.z - POLE.z).length() < 3.0


## Les troncs bloquent le joueur, la vue de l'homme au masque, et la créature les contourne.
func _build_trunk_colliders() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	for t in trunks:
		var p: Vector3 = t[0]
		var r: float = t[1]
		if absf(p.x) > 70.0 or p.z < -75.0 or p.z > 25.0:
			continue
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = r
		cyl.height = 6.0
		cs.shape = cyl
		cs.position = p + Vector3(0, 3.0, 0)
		body.add_child(cs)
		_add_obstacle(p, r)


func _add_obstacle(p: Vector3, r: float) -> void:
	var key := Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
	if not _trunk_grid.has(key):
		_trunk_grid[key] = []
	_trunk_grid[key].append([p, r])


func trunks_near(p: Vector3) -> Array:
	var out: Array = []
	var c := Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			out.append_array(_trunk_grid.get(c + Vector2i(dx, dz), []))
	return out


func _build_bounds() -> void:
	# lisière : on ne s'enfonce pas au-delà (le brouillard cache la limite)
	for spec in [[Vector3(0, 2, 16), Vector3(130, 4, 1)], [Vector3(0, 2, -60), Vector3(130, 4, 1)],
			[Vector3(-56, 2, -22), Vector3(1, 4, 80)], [Vector3(56, 2, -22), Vector3(1, 4, 80)]]:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = spec[1]
		cs.shape = bs
		b.add_child(cs)
		add_child(b)
		b.position = spec[0]


# ----------------------------------------------------------- interface pour la créature (Creature.nav)
func nav_path(_from: Vector3, to: Vector3) -> PackedVector3Array:
	return PackedVector3Array([to])


func random_point(near: Vector3, max_tiles: int) -> Vector3:
	var r := float(max_tiles) * 2.8
	return near + Vector3(randf_range(-r, r), 0, randf_range(-r, r))


func has_los(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	# le corps de Théo ne compte pas comme un obstacle (on vise sa poitrine)
	if player != null:
		q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func floor_y(_p: Vector3) -> float:
	return 0.0


func _ground_y(_p: Vector3) -> float:
	return 0.0


func obstacles() -> Array:
	return trunks_near(creature.global_position)


func on_noise(pos: Vector3, radius: float) -> void:
	if hunter != null:
		hunter.hear(pos, radius)
	if creature != null and creature.visible:
		creature.hear(pos, radius)


# ================================================================== sortie, route, poteau
func _build_exit_and_road() -> void:
	B.model(self, "water_manhole_cover", Vector3(0.9, 0.0, 0.6), 30.0, {"width": 0.8})
	var hole := B.cylinder(self, 0.36, 0.36, 0.02, Vector3(0, 0.005, 0), B.color_mat(Color(0, 0, 0), 1.0), false, 20)
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var asphalt := B.mat("asphalt_02", 4.0, {"color": Color(0.5, 0.5, 0.5), "roughness": 0.6})
	B.box(self, Vector3(300, 0.04, 7.0), Vector3(0, 0.0, ROAD_Z), asphalt, false)
	B.box(self, Vector3(300, 0.045, 0.12), Vector3(0, 0.0, ROAD_Z), B.color_mat(Color(0.8, 0.8, 0.75), 0.5), false)
	# troncs tombés en travers du sentier (on les contourne : en pleine course, ça coûte cher)
	for spec in [[Vector3(0.6, 0, -24.0), 75.0], [Vector3(-0.8, 0, -36.5), 105.0], [Vector3(-10.0, 0, -22.4), 15.0]]:
		var fallen := B.model(self, "dead_tree_trunk", spec[0], spec[1], {"width": 5.0, "collide": true})
		fallen.name = "FallenLog"
		var yaw := deg_to_rad(float(spec[1]))
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		for k in range(-2, 3):
			var c: Vector3 = spec[0]
			_add_obstacle(c + dir * k * 0.9, 0.45)
	# poteau avec caméra et lampadaire au sodium
	var pole_pos := POLE
	B.cylinder(self, 0.11, 0.14, 7.5, pole_pos + Vector3(0, 3.75, 0), B.mat("bark_willow", 1.0, {"color": Color(0.35, 0.3, 0.25)}), true, 10)
	B.box(self, Vector3(0.08, 0.08, 1.6), pole_pos + Vector3(0, 7.0, 0.6), B.color_mat(Color(0.25, 0.25, 0.25), 0.5, 0.8), false)
	B.box(self, Vector3(0.3, 0.1, 0.5), pole_pos + Vector3(0, 6.95, 1.35), B.color_mat(Color(0.2, 0.2, 0.2), 0.5, 0.8), false)
	var sodium := B.spot(self, pole_pos + Vector3(0, 6.85, 1.35), pole_pos + Vector3(0, 0, 4.0), Color(1.0, 0.62, 0.3), 3.0, 18.0, 55.0, true)
	sodium.light_volumetric_fog_energy = 2.0
	Game.add_flare(sodium, 1.4, 1.3)
	var mount_y := 4.6
	var r := lerpf(0.14, 0.11, mount_y / 7.5)
	var steel := B.color_mat(Color(0.22, 0.22, 0.23), 0.45, 0.85)
	for dy in [-0.075, -0.01]:
		B.cylinder(self, r + 0.008, r + 0.008, 0.022, pole_pos + Vector3(0, mount_y + dy, 0), steel, false, 16)
	var face := Vector3(0, 0, 1)
	var watch_path := (Vector3(0, 1.0, -30.0) - (pole_pos + Vector3(0, mount_y, r))).normalized()
	pole_cam = SecurityCamera.create(self, pole_pos + Vector3(0, mount_y, r) + face * SecurityCamera.ARM, watch_path)
	pole_cam.attach_wall(pole_pos + Vector3(0, mount_y, r), face)
	pole_cam.pivot.global_basis = Basis.looking_at(Vector3(-1.0, -0.15, -0.35).normalized(), Vector3.UP)


# ================================================================== traces des sessions d'avant
func _build_traces() -> void:
	# la plaque de la session 13, marquée à la bombe (c'est d'ici que sortira la créature)
	var lid13 := B.model(self, "water_manhole_cover", S13, 0.0, {"width": 0.8})
	lid13.name = "S13Lid"
	B.decal(self, "res://assets/gen/decal_spray13.png", S13 + Vector3(0, 0.1, 0), Vector3.UP, 1.3, 1.3, 0.4)
	# des lambeaux de vêtements noués aux branches, à hauteur d'homme : des trophées
	var cloth := [Color(0.5, 0.08, 0.08), Color(0.12, 0.16, 0.3), Color(0.55, 0.52, 0.45), Color(0.15, 0.25, 0.15), Color(0.3, 0.3, 0.32)]
	var spots := [Vector3(2.9, 1.7, -6.0), Vector3(-3.4, 1.9, -10.5), Vector3(3.2, 1.6, -19.0), Vector3(-3.0, 1.8, -29.0),
		Vector3(3.3, 1.7, -33.0), Vector3(-11.0, 1.6, -21.4), Vector3(12.0, 1.8, -27.6), Vector3(-2.8, 1.5, -41.0)]
	for i in spots.size():
		var at: Vector3 = spots[i]
		var rag := B.box(self, Vector3(0.09, 0.5, 0.012), at - Vector3(0, 0.25, 0), B.color_mat(cloth[i % cloth.size()], 0.95), false, Vector3(randf_range(-8, 8), randf_range(0, 360), randf_range(-6, 6)))
		rag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		B.cylinder(self, 0.025, 0.035, 0.6, at + Vector3(0.0, 0.02, 0.0), B.mat("bark_willow", 1.0, {"color": Color(0.3, 0.26, 0.22)}), false, 6, Vector3(0, 0, 80))
	# une basket dans les feuilles, une valise éventrée, un sac de couchage pourri, une casquette
	B.model(self, "sf:sneakers_brown", Vector3(1.9, 0, -9.6), 130.0, {"width": 0.34})
	B.model(self, "vintage_suitcase", Vector3(-3.1, 0, -24.5), 200.0, {"width": 0.6})
	B.model(self, "sf:sleeping_bag", Vector3(13.0, 0, -32.6), 40.0, {"width": 1.8})
	B.model(self, "sf:worn_cap", Vector3(-2.6, 0.0, -38.8), 70.0, {"depth": 0.27})
	# la caméra-piéton de la victime de la session 13, tombée dans les feuilles
	var cam13 := Node3D.new()
	add_child(cam13)
	cam13.position = CAM13
	cam13.rotation_degrees = Vector3(0, 35, 82)
	var black := B.color_mat(Color(0.03, 0.03, 0.035), 0.35, 0.4)
	B.box(cam13, Vector3(0.065, 0.1, 0.032), Vector3(0, 0.05, 0), black, false)
	B.cylinder(cam13, 0.016, 0.016, 0.012, Vector3(0, 0.075, 0.021), B.color_mat(Color(0.02, 0.02, 0.025), 0.1, 0.6), false, 16, Vector3(90, 0, 0))
	B.box(cam13, Vector3(0.05, 0.012, 0.02), Vector3(0, 0.02, -0.022), B.color_mat(Color(0.2, 0.2, 0.22), 0.4, 0.8), false)
	# sa diode de batterie faible clignote encore, faiblement, dans les feuilles
	var led := B.omni(self, CAM13 + Vector3(0, 0.06, 0), Color(1.0, 0.1, 0.05), 0.12, 0.7)
	var dot := B.cylinder(cam13, 0.004, 0.004, 0.003, Vector3(0.02, 0.09, 0.017), B.emissive(Color(1.0, 0.08, 0.05), 5.0, true), false, 8, Vector3(90, 0, 0))
	var blink := create_tween().set_loops()
	blink.tween_callback(func() -> void:
		led.visible = true
		dot.visible = true)
	blink.tween_interval(0.12)
	blink.tween_callback(func() -> void:
		led.visible = false
		dot.visible = false)
	blink.tween_interval(1.9)
	Nature.leaves(self, CAM13, _ground_y, 9)
	var it := Interactable.create(self, CAM13 + Vector3(0, 0.08, 0), Vector3(0.5, 0.3, 0.5), "Ramasser la caméra", Callable())
	it.on_use = func() -> void:
		it.queue_free()
		_read_cam13()


func _read_cam13() -> void:
	Sound.play("pickup", -8.0, 0.9)
	Game.hud.say("Une caméra... comme la mienne. BWC-7, série 0402.", 3.0)
	await wait(3.2)
	await read_document("Caméra BWC-7 — n° 0402 — derniers fichiers",
		"[b]Fichier 0402-031 — 03/11/2026 — 05:40[/b]\n" +
		"(essoufflé) ...je suis sorti. Je suis dehors. Il fait encore nuit... Une cabane, sur la gauche du sentier. " +
		"Il y a une radio, mais elle est morte. Faut une batterie. Ils ont un camp, à l'est, avec un groupe électrogène... " +
		"je vais aller voir.\n\n" +
		"[b]Fichier 0402-032 — 03/11/2026 — 05:51[/b]\n" +
		"(on court) (un moteur) ...non. Non — NON —\n" +
		"[i]— fin de l'enregistrement —[/i]", "typed")
	_knows_hut = true
	Game.hud.say("Une radio... dans une cabane, à gauche du sentier.", 3.0)
	if stage == "start":
		Game.hud.objective("La cabane du garde forestier (à gauche du sentier)")


# ================================================================== pièges à loup
func _build_trap(p: Vector3) -> void:
	var trap := B.model(self, "sf:bear_trap", p + Vector3(0, 0.005, 0), randf_range(0, 360), {"width": 0.42})
	# à moitié caché sous les feuilles : seul l'acier qui accroche la lampe le trahit
	Nature.leaves(self, p, _ground_y, 6)
	_traps.append([trap, p, false])


func _check_traps() -> void:
	if dying or not player.control_enabled:
		return
	for i in _traps.size():
		var tr: Array = _traps[i]
		if tr[2]:
			continue
		var p: Vector3 = tr[1]
		if Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length() < 0.33:
			_spring_trap(i)
			return


## Le piège se referme sur la jambe : claquement, cri, sang ; Théo est bloqué jusqu'à ce qu'il desserre les
## mâchoires (maintenir E), puis il boite. Le bruit porte loin.
func _spring_trap(i: int) -> void:
	_traps[i][2] = true
	var p: Vector3 = _traps[i][1]
	Sound.play_at("trap_snap", p + Vector3(0, 0.2, 0), 6.0, 1.0, 5.0, 60.0)
	Game.shake(1.6)
	Game.flash(0.5)
	Game.glitch(0.5, false)
	player.control_enabled = false
	player.limp = minf(0.7, player.limp + 0.4)
	player.set_look(player.yaw, deg_to_rad(-62.0))
	B.decal(self, "res://assets/gen/decal_blood_pool.png", p + Vector3(0, 0.1, 0), Vector3.UP, 0.6, 0.6, 0.3, Color(1, 1, 1, 0.85))
	on_noise(p, 30.0)
	Game.hud.say("AAAH ! Putain... ma jambe !", 2.4)
	await wait(1.0)
	var it := Interactable.create(self, p + Vector3(0, 0.15, 0), Vector3(1.2, 0.6, 1.2), "Desserrer le piège", Callable(), 2.4)
	it.on_use = func() -> void:
		it.queue_free()
		Sound.play_at("trap_snap", p + Vector3(0, 0.2, 0), -6.0, 0.7, 3.0, 20.0)
		player.control_enabled = true
		Game.hud.say("...Ça saigne. Je peux encore marcher. Un peu.", 3.0)
	Game.hud.hint("Regarde le piège et maintiens [E] pour desserrer les mâchoires", 5.0)


# ================================================================== cailloux
func _build_stones(p: Vector3) -> void:
	var grey := B.mat("hacked_concrete", 0.3, {"color": Color(0.42, 0.41, 0.38), "roughness": 1.0})
	var pile := Node3D.new()
	add_child(pile)
	pile.position = p
	for k in 4:
		var sm := SphereMesh.new()
		sm.radius = randf_range(0.035, 0.06)
		sm.height = sm.radius * randf_range(1.2, 1.7)
		sm.radial_segments = 6
		sm.rings = 3
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = grey
		pile.add_child(mi)
		mi.position = Vector3(randf_range(-0.12, 0.12), sm.height * 0.4, randf_range(-0.12, 0.12))
	var it := Interactable.create(self, p + Vector3(0, 0.1, 0), Vector3(0.5, 0.3, 0.5), "Ramasser des cailloux", Callable())
	it.on_use = func() -> void:
		it.queue_free()
		pile.queue_free()
		stones += 3
		Sound.play("pickup", -10.0, 0.8)
		Game.hud.pickup("Cailloux (%d)" % stones)
		if stones <= 3:
			Game.hud.hint("[G] ou [clic droit]  lancer un caillou : sur le drone, ou loin de toi pour faire diversion", 6.0)


func _throw_stone() -> void:
	stones -= 1
	var rb := RigidBody3D.new()
	rb.mass = 0.25
	rb.collision_layer = 0
	rb.collision_mask = 1 | Drone.LAYER
	rb.contact_monitor = true
	rb.max_contacts_reported = 2
	rb.continuous_cd = true
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.045
	cs.shape = sh
	rb.add_child(cs)
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.07
	sm.radial_segments = 6
	sm.rings = 3
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = B.mat("hacked_concrete", 0.3, {"color": Color(0.42, 0.41, 0.38), "roughness": 1.0})
	rb.add_child(mi)
	add_child(rb)
	var cam := player.cam
	var fwd := -cam.global_basis.z
	rb.global_position = cam.global_position + fwd * 0.4 + cam.global_basis.x * 0.12 - Vector3(0, 0.1, 0)
	rb.linear_velocity = fwd * 16.0 + Vector3(0, 2.2, 0) + Vector3(player.velocity.x, 0, player.velocity.z)
	rb.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-4, 4), randf_range(-10, 10))
	Sound.play("flashlight_tap_0", -14.0, 0.6)
	var done := [false]
	rb.body_entered.connect(func(b: Node) -> void:
		if done[0]:
			return
		done[0] = true
		if drone != null and is_instance_valid(drone) and b == drone.body:
			drone.hit()
		else:
			Sound.play_at(Sound.variant("rock_hit", 3), rb.global_position, 0.0, randf_range(0.9, 1.1), 4.0, 35.0)
			# le caillou qui tombe attire l'homme au masque (il ne l'a pas vu partir)
			on_noise(rb.global_position, 16.0))
	await wait(6.0)
	if is_instance_valid(rb):
		rb.queue_free()


# ================================================================== la cabane du garde forestier
func _build_hut() -> void:
	var h := HUT
	var planks := B.mat("weathered_plank_siding", 1.2, {"color": Color(0.55, 0.5, 0.45), "roughness": 0.95})
	var floor_m := B.mat("worn_planks", 1.4, {"color": Color(0.5, 0.45, 0.4)})
	var roof_m := B.mat("grey_roof_tiles", 1.5, {"color": Color(0.45, 0.45, 0.45)})
	var w := 4.2
	var dp := 3.4
	var hh := 2.3
	B.box(self, Vector3(w, 0.12, dp), h + Vector3(0, 0.06, 0), floor_m, true)
	# murs : ouest plein, sud plein, nord avec une fenêtre, est avec la porte
	B.box(self, Vector3(0.1, hh, dp), h + Vector3(-w / 2, hh / 2, 0), planks, true)
	B.box(self, Vector3(w, hh, 0.1), h + Vector3(0, hh / 2, dp / 2), planks, true)
	B.box(self, Vector3(1.2, hh, 0.1), h + Vector3(-w / 2 + 0.6, hh / 2, -dp / 2), planks, true)
	B.box(self, Vector3(1.9, hh, 0.1), h + Vector3(w / 2 - 0.95, hh / 2, -dp / 2), planks, true)
	B.box(self, Vector3(1.1, 0.95, 0.1), h + Vector3(-w / 2 + 1.75, 0.475, -dp / 2), planks, true)
	B.box(self, Vector3(1.1, 0.55, 0.1), h + Vector3(-w / 2 + 1.75, hh - 0.275, -dp / 2), planks, true)
	B.box(self, Vector3(0.1, hh, 1.25), h + Vector3(w / 2, hh / 2, -dp / 2 + 0.625), planks, true)
	B.box(self, Vector3(0.1, hh, 1.25), h + Vector3(w / 2, hh / 2, dp / 2 - 0.625), planks, true)
	B.box(self, Vector3(0.1, 0.35, 0.9), h + Vector3(w / 2, hh - 0.175, 0), planks, true)
	# toit à deux pans
	for s in [-1.0, 1.0]:
		B.box(self, Vector3(w + 0.6, 0.08, dp * 0.6), h + Vector3(0, hh + 0.42, s * dp * 0.26), roof_m, false, Vector3(s * 22.0, 0, 0))
	# dedans : table, radio, chaise, caisse, bidon, boîte de conserve
	var table_top := h + Vector3(-w / 2 + 0.5, 0.78, 0.2)
	B.box(self, Vector3(0.7, 0.05, 1.3), table_top, planks, true)
	for dz in [-0.55, 0.55]:
		B.box(self, Vector3(0.6, 0.76, 0.05), table_top + Vector3(0, -0.4, dz), planks, false)
	var radio := B.model(self, "sf:cb_radio", table_top + Vector3(0.0, 0.025, 0.1), 90.0, {"width": 0.2})
	radio.name = "CBRadio"
	var label := StandardMaterial3D.new()
	label.albedo_texture = load("res://assets/gen/cb_label.png")
	B.quad(self, Vector2(0.14, 0.05), table_top + Vector3(0.12, 0.03, -0.32), label, Vector3(-90, 90, 0))
	# les câbles d'alimentation pendent, coupés de leur batterie
	for k in 2:
		var wire := B.cylinder(self, 0.004, 0.004, 0.55, table_top + Vector3(0.28, -0.25, 0.1 + k * 0.03), B.color_mat(Color(0.7, 0.05, 0.05) if k == 0 else Color(0.05, 0.05, 0.05), 0.5), false, 5)
		wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_battery_slot = Node3D.new()
	add_child(_battery_slot)
	_battery_slot.position = h + Vector3(-w / 2 + 0.55, 0.12, 0.85)
	B.model(self, "dining_chair_02", h + Vector3(-w / 2 + 1.05, 0.12, 0.25), -90.0, {"height": 0.9})
	B.model(self, "wooden_crate_01", h + Vector3(w / 2 - 0.5, 0.12, dp / 2 - 0.5), 10.0, {"height": 0.5})
	B.model(self, "can_rusted", table_top + Vector3(0.1, 0.025, 0.5), 0.0, {"height": 0.12})
	B.model(self, "metal_jerrycan", h + Vector3(-w / 2 + 0.4, 0.12, -1.2), 80.0, {"height": 0.45})
	var it := Interactable.create(self, table_top + Vector3(0, 0.1, 0.1), Vector3(0.6, 0.4, 0.7), "La radio", _use_radio)
	it.name = "RadioUse"


func _use_radio() -> void:
	if stage in ["chase", "done"]:
		return
	if battery_in:
		_radio_call()
		return
	if has_battery:
		has_battery = false
		battery_in = true
		Sound.play("pickup", -6.0, 0.7)
		_install_battery_visual()
		Game.hud.say("Les pinces... rouge sur le plus. Allez...", 2.6)
		await wait(2.0)
		_radio_power_on()
		Game.hud.objective("Appeler à l'aide (la radio)")
		var it := find_child("RadioUse", false, false) as Interactable
		if it != null:
			it.prompt = "Appeler à l'aide"
		return
	Game.hud.say("Une radio CB... morte. Les câbles pendent : il lui faut une batterie de 12 volts.", 4.0)
	if stage == "start":
		stage = "battery"
		await wait(4.2)
		Game.hud.say("Leur camp, à l'est... Ils doivent bien en avoir une.", 3.0)
		Game.hud.objective("Trouver une batterie 12 V (le camp, à l'est)")


func _install_battery_visual() -> void:
	_build_battery(_battery_slot, Vector3.ZERO)


func _radio_power_on() -> void:
	var radio := find_child("CBRadio", false, false) as Node3D
	var at := radio.global_position + Vector3(0.05, 0.06, 0) if radio != null else HUT
	_radio_glow = B.omni(self, at, Color(1.0, 0.55, 0.2), 0.25, 1.2)
	_radio_static = Sound.loop_at("radio_static_loop", radio if radio != null else self, -10.0, 1.5, 12.0)
	Sound.play_at("ui_beep", at, -8.0, 0.8, 2.0, 10.0)


## Il appelle à l'aide... et c'est le direct qui répond. Le public a voté : on ouvre la trappe.
func _radio_call() -> void:
	stage = "chase"
	var it := find_child("RadioUse", false, false) as Interactable
	if it != null:
		it.queue_free()
	player.control_enabled = false
	if is_instance_valid(_radio_static):
		_radio_static.volume_db = -4.0
	Game.hud.say("Allô ? Allô, quelqu'un m'entend ?", 2.6)
	await wait(3.0)
	Game.hud.say("À l'aide ! Je m'appelle Théo Marchand. Je suis dans une forêt, près d'une route... Il y a un camp, des caméras... et un truc. Un monstre.", 5.0)
	await wait(5.6)
	Sound.play("glitch_0", -6.0, 0.7)
	await wait(2.0)
	Game.hud.say("...On vous reçoit très bien, Théo.", 3.0, "Radio")
	await wait(3.3)
	Game.hud.say("Merci... Merci ! Envoyez quelqu'un, vite !", 2.6)
	await wait(3.0)
	Game.hud.say("Vous êtes en direct, Théo. Quatre mille trois cent douze personnes vous regardent.", 4.2, "Radio")
	await wait(4.6)
	Game.hud.say("Le public a voté.", 2.4, "Radio")
	await wait(2.8)
	Game.hud.say("...Ouvrez la trappe.", 2.4, "Radio")
	await wait(2.0)
	if is_instance_valid(_radio_static):
		Sound.fade(_radio_static, -60.0, 0.4, true)
	if is_instance_valid(_radio_glow):
		_radio_glow.queue_free()
	params = {"checkpoint": "chase", "drones": drones_left}
	Game.level_params = params
	_release_creature(false)


## La créature sort de la plaque « S·13 » : un clic dans le brouillard... puis elle fonce. Il faut courir jusqu'à
## la route. L'homme au masque, lui, rentre dans son van : le spectacle n'a plus besoin de lui.
func _release_creature(quick: bool) -> void:
	stage = "chase"
	if hunter != null:
		hunter.leave()
	Sound.play_at("lamp_break_0", S13 + Vector3(0, 0.3, 0), 2.0, 0.6, 8.0, 80.0)
	var lid := find_child("S13Lid", false, false) as Node3D
	if lid != null:
		var tw := create_tween()
		tw.tween_property(lid, "position", lid.position + Vector3(1.2, 0.0, 0.6), 0.35)
		tw.parallel().tween_property(lid, "rotation_degrees:z", 70.0, 0.35)
	await wait(0.4 if quick else 0.8)
	Sound.play_at("creature_shriek", S13 + Vector3(0, 1.0, 0), 4.0, 1.0, 10.0, 90.0, null, "Creature")
	Game.glitch(0.6)
	if not quick:
		await wait(1.2)
		Game.hud.say("Non... non, non, non.", 2.0)
	creature.player = player
	creature.global_position = S13
	creature.activate(Creature.State.CHASE)
	player.control_enabled = true
	player.stamina = 1.0
	Game.hud.objective("COURS. LA ROUTE.")
	await wait(1.0)
	Game.hud.say("Elle arrive... COURS !", 2.0)


# ================================================================== le camp des ravisseurs
func _build_camp() -> void:
	var c := CAMP
	_van = B.model(self, "sf:old_van", c + Vector3(4.0, 0, -4.0), 110.0, {"width": 5.2, "collide": true})
	# la bâche, la table de la régie, les écrans
	B.model(self, "sf:tarp", c + Vector3(-1.5, 0, 0.5), 90.0, {"width": 4.5})
	var top := c + Vector3(-1.5, 0.76, 0.0)
	B.box(self, Vector3(2.0, 0.05, 0.8), top, B.color_mat(Color(0.32, 0.32, 0.33), 0.6, 0.6), true)
	for dx in [-0.9, 0.9]:
		B.box(self, Vector3(0.05, 0.74, 0.7), top + Vector3(dx, -0.39, 0), B.color_mat(Color(0.2, 0.2, 0.2), 0.5, 0.8), false)
	# écran du drone (flux en direct), page du direct, ordinateur portable
	feed = SecurityFeed.new()
	feed.cam_label = "DRONE 2"
	add_child(feed)
	_feed_mat = feed.screen_material(1.0)
	var mon_mat := B.color_mat(Color(0.05, 0.05, 0.06), 0.4, 0.4)
	B.box(self, Vector3(0.62, 0.38, 0.04), top + Vector3(-0.45, 0.25, -0.25), mon_mat, false)
	SecurityFeed.screen(self, Vector2(0.58, 0.34), top + Vector3(-0.45, 0.25, -0.228), Vector3.ZERO, _feed_mat)
	B.box(self, Vector3(0.62, 0.38, 0.04), top + Vector3(0.25, 0.25, -0.25), mon_mat, false, Vector3(0, -10, 0))
	var stream := StandardMaterial3D.new()
	stream.albedo_color = Color.BLACK
	stream.emission_enabled = true
	stream.emission_texture = load("res://assets/gen/screen_stream.png")
	stream.emission_energy_multiplier = 1.1
	SecurityFeed.screen(self, Vector2(0.58, 0.34), top + Vector3(0.254, 0.25, -0.228), Vector3(0, -10, 0), stream)
	var lap_mat := StandardMaterial3D.new()
	lap_mat.albedo_color = Color.BLACK
	lap_mat.emission_enabled = true
	lap_mat.emission_texture = load("res://assets/gen/screen_stream.png")
	lap_mat.emission_energy_multiplier = 0.9
	Props.laptop(self, top + Vector3(0.75, 0.025, 0.15), -35.0, lap_mat)
	B.omni(self, top + Vector3(0, 0.45, 0.3), Color(0.7, 0.78, 1.0), 0.35, 3.0)
	# lampe de chantier : la seule vraie lumière du camp
	var lamp := B.spot(self, c + Vector3(-3.6, 2.2, 2.2), top, Color(1.0, 0.85, 0.65), 4.0, 12.0, 60.0, true)
	lamp.light_volumetric_fog_energy = 1.6
	B.cylinder(self, 0.02, 0.025, 2.2, c + Vector3(-3.6, 1.1, 2.2), B.color_mat(Color(0.8, 0.6, 0.1), 0.5, 0.4), false, 8)
	# groupe électrogène qui ronfle, bidons, caisses
	var gen := B.model(self, "sf:generator", c + Vector3(-6.0, 0, -2.0), 30.0, {"width": 0.75})
	Sound.loop_at("generator_loop", gen, -2.0, 3.0, 30.0)
	B.model(self, "metal_jerrycan", c + Vector3(-6.8, 0, -1.2), 10.0, {"height": 0.45})
	B.model(self, "plastic_jerrycan", c + Vector3(-5.3, 0, -2.9), 60.0, {"height": 0.4})
	B.model(self, "propane_tank", c + Vector3(1.5, 0, 3.0), 0.0, {"height": 0.6})
	B.model(self, "old_military_crate", c + Vector3(-3.4, 0, -1.6), 20.0, {"width": 1.0})
	B.model(self, "wooden_crate_01", c + Vector3(0.5, 0, 2.6), 40.0, {"height": 0.55})
	B.model(self, "sf:sleeping_bag", c + Vector3(-2.5, 0.02, 3.2), 100.0, {"width": 1.8})
	# le tableau des sujets, sur un chevalet
	var board := StandardMaterial3D.new()
	board.albedo_texture = load("res://assets/gen/board_subjects.png")
	board.roughness = 0.9
	B.quad(self, Vector2(1.4, 0.98), c + Vector3(-3.2, 1.3, 0.0), board, Vector3(0, 70, 0))
	for k in [-0.55, 0.55]:
		B.cylinder(self, 0.018, 0.018, 1.9, c + Vector3(-3.25, 0.95, k), B.color_mat(Color(0.3, 0.25, 0.2), 0.8), false, 6)
	Interactable.create(self, c + Vector3(-3.1, 1.3, 0.0), Vector3(0.4, 1.0, 1.4), "Le tableau", func() -> void:
		await read_document("Le tableau — session 14",
			"[b]SESSION 14 — 4 sujets[/b]   [i]« le public a choisi »[/i]\n\n" +
			"Sujet 1 — Maxime D., 24 ans — [color=#b33]✗[/color]\nSujet 2 — Inès F., 23 ans — [color=#b33]✗[/color]\n" +
			"Sujet 3 — Karim H., 25 ans — [color=#b33]✗[/color]\nSujet 4 — Théo M., 24 ans, agent de sécurité — [b]EN COURS[/b]\n\n" +
			"Pas d'intervention avant la sortie.\nLa bête se rappelle au sifflet.", "paper")
		Game.hud.say("Le public a choisi... Nous quatre. Comme des numéros.", 3.4))
	# le registre des sessions, sur la table
	B.box(self, Vector3(0.22, 0.01, 0.3), top + Vector3(-0.85, 0.03, 0.15), B.color_mat(Color(0.85, 0.83, 0.78), 0.9), false, Vector3(0, 15, 0))
	Interactable.create(self, top + Vector3(-0.85, 0.08, 0.15), Vector3(0.35, 0.2, 0.4), "Le registre", func() -> void:
		await read_document("Registre des sessions",
			"[b]SESSIONS — 2026[/b]\n\n" +
			"01 — 14/02 — 1 sujet — 312 spectateurs — 2 h 10 — non retrouvé\n" +
			"04 — 03/05 — 2 sujets — 870 spectateurs — 3 h 02 — non retrouvés\n" +
			"09 — 22/08 — 3 sujets — 2 140 spectateurs — 4 h 15 — non retrouvés\n" +
			"12 — 06/10 — 2 sujets — 2 980 spectateurs — 4 h 41 — non retrouvés\n" +
			"13 — 03/11 — 1 sujet (agent de sécurité, 41 ans) — 3 655 spectateurs — 5 h 02 — sorti à 05:51 — [i]récupéré au van[/i]\n" +
			"[b]14 — 14/11 — 4 sujets — EN COURS — 4 312 spectateurs[/b]\n\n" +
			"Recettes (dons) : 61 400 €\nProchaine étape : vote du public.", "typed")
		Game.hud.say("Treize avant nous... Et personne ne les a jamais retrouvés.", 3.4))
	Interactable.create(self, top + Vector3(0.75, 0.15, 0.15), Vector3(0.5, 0.3, 0.45), "L'ordinateur", func() -> void:
		await read_document("Le direct — session 14",
			"[b]● DIRECT — SESSION 14 — 4 312 spectateurs[/b]\n\n" +
			"[color=#7af]vlad_88[/color] [color=#5d7]50 €[/color] — fais-le passer par l'eau\n" +
			"[color=#7af]nightowl[/color] [color=#5d7]20 €[/color] — LÂCHE LA BÊTE\n" +
			"[color=#7af]k0rr[/color] [color=#5d7]100 €[/color] — coupe-lui la lumière lol\n" +
			"[color=#7af]m.b[/color] [color=#5d7]500 €[/color] — vote : LA RADIO\n" +
			"[color=#7af]lu_cie[/color] [color=#5d7]30 €[/color] — les 3 autres c'était trop court\n" +
			"[color=#7af]Dmitri[/color] [color=#5d7]250 €[/color] — plus long que la 13 svp\n\n" +
			"[b]PROCHAINE ÉTAPE — vote en cours :[/b]  « LA RADIO » 61 %  ·  « LA ROUTE » 39 %", "phone")
		Game.hud.say("« La radio »... Ils votent. Ils votent pour ce qui va m'arriver.", 3.6))
	Interactable.create(self, top + Vector3(-0.45, 0.25, -0.2), Vector3(0.6, 0.4, 0.2), "L'écran", func() -> void:
		if drone != null and is_instance_valid(drone) and not drone.down:
			Game.hud.say("C'est moi... vu d'en haut. Le drone. Ils me filment en ce moment même.", 3.6)
		else:
			Game.hud.say("Plus d'image. Le drone est par terre.", 2.6))
	# la caisse des téléphones confisqués (ceux des sessions d'avant)... le sien est dessus
	B.model(self, "plastic_crate_01", c + Vector3(-0.2, 0, 1.6), 15.0, {"height": 0.32})
	for k in 7:
		Props.phone(self, c + Vector3(-0.2 + randf_range(-0.12, 0.12), 0.22 + k * 0.012, 1.6 + randf_range(-0.08, 0.08)), randf_range(0, 360),
			[Color(0.05, 0.05, 0.06), Color(0.7, 0.68, 0.66), Color(0.12, 0.2, 0.35), Color(0.4, 0.1, 0.1)][k % 4])
	var mine := Props.phone(self, c + Vector3(-0.2, 0.33, 1.6), 20.0, Color(0.04, 0.04, 0.05))
	mine.name = "MyPhone"
	Interactable.create(self, c + Vector3(-0.2, 0.38, 1.6), Vector3(0.45, 0.25, 0.45), "Ton téléphone", _use_phone)
	# la batterie de secours, à côté du groupe
	_battery_node = Node3D.new()
	add_child(_battery_node)
	_battery_node.position = c + Vector3(-5.2, 0, -1.0)
	_build_battery(_battery_node, Vector3.ZERO)
	var bit := Interactable.create(_battery_node, Vector3(0, 0.15, 0), Vector3(0.5, 0.35, 0.45), "Débrancher la batterie", Callable(), 1.4)
	bit.on_use = _take_battery


func _build_battery(parent: Node3D, at: Vector3) -> void:
	var case := B.box(parent, Vector3(0.27, 0.19, 0.17), at + Vector3(0, 0.095, 0), B.color_mat(Color(0.06, 0.06, 0.07), 0.6, 0.1), false)
	case.name = "Battery"
	B.box(parent, Vector3(0.27, 0.012, 0.17), at + Vector3(0, 0.196, 0), B.color_mat(Color(0.12, 0.12, 0.13), 0.6), false)
	B.cylinder(parent, 0.012, 0.012, 0.025, at + Vector3(-0.09, 0.21, 0.04), B.color_mat(Color(0.75, 0.08, 0.06), 0.5, 0.3), false, 8)
	B.cylinder(parent, 0.012, 0.012, 0.025, at + Vector3(0.09, 0.21, 0.04), B.color_mat(Color(0.12, 0.12, 0.12), 0.5, 0.3), false, 8)


## Il débranche la batterie... et la porte latérale du van coulisse : l'homme au masque était dedans.
func _take_battery() -> void:
	if has_battery:
		return
	has_battery = true
	Sound.play("pickup", -6.0, 0.7)
	Game.hud.pickup("Batterie 12 V")
	_battery_node.queue_free()
	stage = "carry"
	params = {"checkpoint": "carry", "drones": drones_left}
	Game.level_params = params
	Game.hud.say("Je l'ai. Lourde... Vite, à la cabane.", 2.6)
	await wait(2.4)
	Sound.play_at("door_slam", _van.global_position + Vector3(0, 1.0, 0), 4.0, 0.85, 6.0, 50.0)
	await wait(0.7)
	hunter.wake(true)
	Game.glitch(0.4)
	await wait(1.4)
	Game.hud.say("Le van... Il était dedans. Il m'a pas vu. Pas encore.", 3.2)
	Game.hud.objective("Rapporter la batterie à la cabane, sans te faire voir")
	await wait(3.4)
	Game.hud.hint("Il voit, mais il entend mal : reste hors de sa lampe, accroupis-toi ([C]), éteins ta lampe ([F]). Un caillou lancé loin l'attire.", 8.0)


## Son propre téléphone : 3 %, une barre. Le 17 ne passe pas, le message non plus. Puis plus de batterie.
func _use_phone() -> void:
	if _phone_done:
		Game.hud.say("Mort. Plus de batterie.", 2.0)
		return
	_phone_done = true
	var desk_phone := find_child("MyPhone", false, false)
	if desk_phone != null:
		desk_phone.queue_free()
	player.control_enabled = false
	var ui := PhoneUI.new()
	add_child(ui)
	var phone := Node3D.new()
	player.cam.add_child(phone)
	phone.position = Vector3(0.02, -0.07, -0.3)
	phone.rotation_degrees = Vector3(8, 0, 0)
	var shell := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.0765, 0.1605, 0.0085)
	shell.mesh = bm
	shell.material_override = B.color_mat(Color(0.03, 0.03, 0.035), 0.3, 0.6)
	phone.add_child(shell)
	var scr_mat := StandardMaterial3D.new()
	scr_mat.albedo_color = Color(0.015, 0.015, 0.018)
	scr_mat.emission_enabled = true
	scr_mat.emission_texture = ui.get_texture()
	scr_mat.emission_energy_multiplier = 0.9
	var scr := B.quad(phone, Vector2(0.0725, 0.1525), Vector3(0, 0, 0.0044), scr_mat)
	scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := B.omni(phone, Vector3(0, 0, 0.1), Color(0.6, 0.7, 1.0), 0.15, 0.8)
	Sound.play("pickup", -10.0, 1.2)
	await get_tree().process_frame
	ui.set_time("05:58")
	ui.show_screen("lock")
	ui.notify("Maman", "14 appels manqués")
	ui.notify("Batterie", "3 % — batterie faible")
	await wait(0.6)
	Game.hud.say("Mon téléphone... 3 %. Une barre de réseau.", 2.8)
	await wait(3.0)
	ui.call_contact("17")
	Sound.play("ringback", -14.0)
	await wait(3.6)
	ui.set_call_status("Échec de l'appel")
	Sound.play("ui_beep", -10.0, 0.6)
	Game.hud.say("Allez... ALLEZ !", 1.6)
	await wait(2.0)
	ui.open_chat("Maman")
	await ui.type_reply("aide moi forêt route ils filment tout")
	await wait(0.8)
	Game.hud.say("Envoie... Envoie-toi !", 2.0)
	await wait(2.2)
	ui.notify("Message", "Échec de l'envoi")
	ui.show_screen("lock")
	await wait(1.4)
	var tw := create_tween()
	tw.tween_property(scr_mat, "emission_energy_multiplier", 0.0, 0.6)
	tw.parallel().tween_property(glow, "light_energy", 0.0, 0.6)
	await tw.finished
	Game.hud.say("...Mort.", 1.6)
	await wait(1.2)
	phone.queue_free()
	ui.queue_free()
	player.control_enabled = true


# ================================================================== le drone
func _update_drone(delta: float) -> void:
	if drone != null and is_instance_valid(drone) and not drone.down:
		feed.cam.global_transform = drone.view_transform()
		# il « signale » Théo à l'homme au masque : abattre le drone a un vrai intérêt
		if hunter != null and hunter.state in [Hunter.S.PATROL, Hunter.S.SEARCH]:
			_report_cd -= delta
			if _report_cd <= 0.0:
				_report_cd = 11.0
				if has_los(drone.global_position, player.eye_position()):
					hunter.hear(player.global_position, 999.0)
		return
	if stage in ["chase", "done"] or drones_left <= 0:
		return
	_drone_cd -= delta
	if _drone_cd <= 0.0:
		_drone_cd = 9999.0
		drones_left -= 1
		drone = Drone.new()
		drone.level = self
		add_child(drone)
		drone.global_position = (CAMP if drones_left < 1 else player.global_position) + Vector3(randf_range(-6, 6), 9.0, -14.0)
		_feed_mat.set_shader_parameter("static_mix", 0.0)
		await wait(4.0)
		if drones_left == 1:
			Game.hud.say("C'est quoi ce bruit... Un drone ?! Il me filme...", 3.2)
		else:
			Game.hud.say("Un autre drone... Ils en avaient un deuxième.", 3.0)


func on_drone_down(_d: Node) -> void:
	_feed_mat.set_shader_parameter("static_mix", 1.0)
	Game.hud.say("Touché !" if drones_left > 0 else "Et de deux. Plus d'yeux dans le ciel.", 2.0)
	_drone_cd = 55.0


# ================================================================== la route, la mort, la fin
func _at_road() -> void:
	if stage == "chase":
		stage = "done"
		_creature_recalled()
		_reveal()
	elif not _road_said and stage != "done":
		_road_said = true
		Game.hud.say("La route... Pas une voiture. Personne. Il faut que je trouve un moyen d'appeler.", 4.0)


## Un sifflet strident, quelque part près du poteau : la créature s'arrête net, puis repart dans le brouillard.
func _creature_recalled() -> void:
	Sound.play_at("whistle", POLE + Vector3(0, 4.0, 0), 4.0, 1.0, 20.0, 120.0)
	if creature == null or not creature.visible:
		return
	creature.stand_and_watch(null, "listen", 0.8)
	creature.twitch.spasm(1.0)
	await wait(1.6)
	creature.script_walk(PackedVector3Array([S13]), 2.6)
	await wait(4.0)
	creature.deactivate()


func _die(cause: String) -> void:
	if dying or stage == "done":
		return
	dying = true
	player.control_enabled = false
	player.look_enabled = false
	var start := player.head.global_transform
	var who: Vector3 = creature.head_position() if cause == "creature" else hunter.global_position + Vector3(0, 1.6, 0)
	var face := Transform3D(Basis.looking_at((who - start.origin).normalized(), Vector3.UP), start.origin)
	var tw := create_tween()
	tw.tween_method(func(w: float) -> void: player.set_cinematic(start.interpolate_with(face, w), 1.0), 0.0, 1.0, 0.2)
	if cause == "creature":
		Sound.play("creature_attack", 4.0)
	else:
		hunter.actor.play("strike", 0.1, 1.2)
		Sound.play("hit_impact", 0.0)
	Game.glitch(1.0, false)
	Game.shake(3.0)
	await wait(0.35)
	Sound.play(Sound.variant("theo_scream", 2), 2.0, randf_range(0.95, 1.05))
	Game.flash(0.4)
	var ground := player.global_position + Vector3(0, 0.06, 0)
	var ahead := Vector3(-sin(player.yaw), 0, -cos(player.yaw))
	var floor_t := Transform3D(Basis.looking_at(Vector3.UP, ahead) * Basis(Vector3(0, 0, 1), randf_range(-0.6, 0.6)), ground)
	var tw2 := create_tween()
	tw2.tween_method(func(w: float) -> void: player.set_cinematic(face.interpolate_with(floor_t, w), 1.0), 0.0, 1.0, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await wait(0.45)
	Sound.play("body_fall", -2.0)
	Game.shake(1.0)
	await wait(2.2)
	Sound.play("signal_lost", -4.0, 1.0, "UI")
	Game.hud.osd("SIGNAL PERDU")
	Game.glitch(1.0, false)
	await wait(1.0)
	Game.set_blackout(true)
	await wait(1.2)
	Game.hud.osd("")
	Game.set_blackout(false, true)
	Game.level_params = params
	Game.retry_from_checkpoint()


func _reveal() -> void:
	if revealed:
		return
	revealed = true
	pole_cam.tracking = true
	Sound.play_at("servo", pole_cam.global_position, 4.0, 0.8, 8.0, 80.0)
	await wait(1.5)
	Game.hud.say("Non...", 1.8)
	await wait(1.6)
	Game.hud.say("Non, non, non...", 2.0)
	Game.glitch(0.6)
	await wait(1.2)
	Game.glitch(1.0)
	Game.hud.set_rec(false)
	Game.hud.live_overlay(true, 4312, "")
	Sound.play("stinger_soft", -4.0)
	var viewers := 4312
	for i in 30:
		viewers += randi_range(40, 400)
		Game.hud.live_overlay(true, viewers, "")
		await wait(0.12)
	Game.hud.live_overlay(true, viewers, "SESSION 14 — TERMINÉE\nMerci d'avoir regardé.")
	await wait(3.5)
	player.control_enabled = false
	Sound.play("boom_hit", 0.0)
	Game.glitch(1.0, false)
	Game.set_blackout(true)
	Game.hud.show_hud(false)
	if wind != null:
		Sound.fade(wind, -60.0, 0.3, true)
	await wait(1.0)
	Sound.play("signal_lost", -2.0, 1.0, "UI")
	Game.clock_running = false
	await wait(2.0)
	Game.ui.fade_rect.color = Color(0, 0, 0, 1)
	Game.set_blackout(false, true)
	await Game.ui.show_card([
		{"text": "FIN DE L'ENREGISTREMENT", "style": "red"},
		"",
		"Cet enregistrement a été retrouvé le 2 décembre 2026",
		"sur un serveur hébergé à l'étranger, aux côtés de treize autres « sessions ».",
		"",
		"Théo Marchand, Maxime Dubreuil, Inès Ferrand et Karim Haddad",
		"n'ont jamais été retrouvés.",
	], 1.6, 5.0, 1.5)
	await Game.ui.show_card([
		{"text": "DERNIER ENREGISTREMENT", "style": "title"},
		{"text": "Merci d'avoir joué.", "style": "small"},
		"",
		{"text": "Modèles : Poly Haven (CC0), Sketchfab (CC BY — voir CREDITS.md), Microsoft Rocketbox (MIT)", "style": "small"},
		{"text": "Animations : CMU Motion Capture Database  ·  Sons : Freesound (CC0) et générés par code  ·  Moteur : Godot", "style": "small"},
	], 1.2, 4.0, 1.5)
	Game.quit_to_menu()


func _process(delta: float) -> void:
	super._process(delta)
	if player == null or dying:
		return
	_check_traps()
	_update_drone(delta)
	if Input.is_action_just_pressed("throw") and stones > 0 and player.can_act():
		_throw_stone()
	# danger : la créature ou l'homme au masque tout près
	var d := 99.0
	if creature != null and creature.visible:
		d = creature.global_position.distance_to(player.global_position)
	if hunter != null and hunter.state != Hunter.S.HIDDEN:
		d = minf(d, hunter.global_position.distance_to(player.global_position) * (0.6 if hunter.state == Hunter.S.CHASE else 1.4))
	player.danger = clampf(1.0 - d / 16.0, 0.0, 1.0)


func prewarm_extras() -> Array:
	var out: Array = [creature, hunter]
	var d := Drone.new()
	d.level = self
	d.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(d)
	d.set_meta("prewarm_temp", true)
	out.append(d)
	return out


## Tests : --surfacetest=trap|drone|hunter|chase|phone
func _surface_test(kind: String) -> void:
	await wait(1.0)
	player.set_flashlight(true, true)
	match kind:
		"trapview":
			var tv: Vector3 = TRAPS[0]
			player.global_position = tv + Vector3(0, 0.05, 1.3)
			player.set_look(0.0, deg_to_rad(-45.0))
		"seen":
			var fwd2 := Vector3(-sin(player.yaw), 0, -cos(player.yaw))
			hunter.wake(false)
			hunter.global_position = player.global_position + fwd2 * 12.0
			hunter.heading = player.yaw + PI
			hunter.rotation.y = hunter.heading
			hunter.state = Hunter.S.SEARCH
		"droneview", "hunterview":
			var fwd := Vector3(-sin(player.yaw), 0, -cos(player.yaw))
			if kind == "droneview":
				var dv := Drone.new()
				dv.level = self
				add_child(dv)
				dv.global_position = player.global_position + fwd * 1.6 + Vector3(0, 1.5, 0)
				await wait(0.3)
				dv.process_mode = Node.PROCESS_MODE_DISABLED
			else:
				hunter.wake(false)
				hunter.global_position = player.global_position + fwd * 4.0
				if Game.args.has("seetest"):
					hunter.heading = player.yaw + PI
					hunter.rotation.y = hunter.heading
					return
				hunter.heading = player.yaw
				hunter.rotation.y = player.yaw
				hunter.actor.play("idle", 0.0)
				await wait(0.3)
				hunter.process_mode = Node.PROCESS_MODE_DISABLED
		"radio":
			player.global_position = HUT + Vector3(0.4, 0.05, 0.3)
			battery_in = true
			_install_battery_visual()
			_radio_power_on()
			_radio_call()
		"road":
			_release_creature(true)
			await wait(2.0)
			player.global_position = Vector3(0.0, 0.05, ROAD_Z + 4.0)
		"trap":
			var p: Vector3 = TRAPS[0]
			player.global_position = p + Vector3(0, 0.05, 0.2)
		"drone":
			_drone_cd = 0.0
		"hunter":
			hunter.wake(true)
		"chase":
			_release_creature(true)
		"phone":
			_use_phone()
	for i in 12:
		await wait(1.0)
		var hs: String = Hunter.S.keys()[hunter.state]
		var cs: String = Creature.State.keys()[creature.state]
		var dr := "oui" if drone != null and is_instance_valid(drone) and not drone.down else "non"
		print("SURFACE t=%d étape=%s chasseur=%s soupçon=%.2f créature=%s boite=%.2f drone=%s" % [i + 1, stage, hs, hunter.suspicion, cs, player.limp, dr])


# ================================================================== drone
class Drone extends Node3D:
	const LAYER := 1 << 7
	var level
	var model: Node3D
	var body: StaticBody3D
	var led: OmniLight3D
	var buzz: AudioStreamPlayer3D
	var props: Array[Node3D] = []
	var down := false
	var vel := Vector3.ZERO
	var t := 0.0
	var orbit := 0.0

	func _ready() -> void:
		model = B.model(self, "sf:drone", Vector3.ZERO, 0.0, {"width": 0.55})
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var n := String(mi.name).to_lower()
			if n.contains("prop") or n.contains("rotor") or n.contains("blade") or n.contains("vint"):
				props.append(mi as Node3D)
		led = OmniLight3D.new()
		led.light_color = Color(1.0, 0.1, 0.08)
		led.light_energy = 0.8
		led.omni_range = 2.5
		add_child(led)
		led.position = Vector3(0, -0.05, 0.12)
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.014
		sm.height = 0.028
		dot.mesh = sm
		dot.material_override = B.emissive(Color(1.0, 0.1, 0.08), 6.0, true)
		led.add_child(dot)
		body = StaticBody3D.new()
		body.collision_layer = LAYER
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.45
		cs.shape = sh
		body.add_child(cs)
		add_child(body)
		buzz = Sound.loop_at("drone_loop", self, 0.0, 4.0, 50.0)
		orbit = randf() * TAU

	func _process(delta: float) -> void:
		if down or level == null:
			return
		t += delta
		var p: Player = level.player
		if p == null:
			return
		orbit += delta * 0.16
		var target := p.global_position + Vector3(cos(orbit) * 6.5, 4.4 + sin(t * 0.7) * 0.4, sin(orbit) * 6.5)
		var want := (target - global_position) * 1.1
		if want.length() > 6.5:
			want = want.normalized() * 6.5
		vel = vel.lerp(want, 1.0 - exp(-2.0 * delta))
		global_position += vel * delta
		# il fixe Théo ; il penche dans le sens où il file
		var to := p.global_position - global_position
		rotation.y = atan2(-to.x, -to.z)
		var local := global_basis.inverse() * vel
		model.rotation = Vector3(clampf(local.z * 0.06, -0.3, 0.3), 0, clampf(-local.x * 0.06, -0.3, 0.3))
		for pr in props:
			pr.rotate_object_local(Vector3.UP, delta * 70.0)
		led.visible = fmod(t, 1.0) < 0.18

	## Point de vue de sa caméra (sous le drone, braquée sur Théo) pour l'écran de la régie.
	func view_transform() -> Transform3D:
		var p: Player = level.player
		var eye := global_position + Vector3(0, -0.12, 0)
		return Transform3D(Basis.looking_at((p.global_position + Vector3(0, 1.0, 0) - eye).normalized(), Vector3.UP), eye)

	## Touché : il part en vrille et s'écrase. Le ronflement s'étrangle.
	func hit() -> void:
		if down:
			return
		down = true
		led.visible = false
		Sound.play_at("lamp_break_0", global_position, 4.0, 0.8, 6.0, 50.0)
		if is_instance_valid(buzz):
			var tw0 := buzz.create_tween()
			tw0.tween_property(buzz, "pitch_scale", 0.4, 1.0)
			tw0.parallel().tween_property(buzz, "volume_db", -60.0, 1.2)
		var ground := Vector3(global_position.x, 0.12, global_position.z)
		var tw := create_tween()
		tw.tween_property(self, "global_position", ground, sqrt(2.0 * maxf(global_position.y, 0.5) / 9.8)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(self, "rotation", rotation + Vector3(2.4, 6.0, 1.1), 1.0)
		tw.tween_callback(func() -> void:
			Sound.play_at(Sound.variant("rock_hit", 3), global_position, 2.0, 0.6, 4.0, 30.0)
			body.collision_layer = 0
			level.on_drone_down(self))


# ================================================================== l'homme au masque
class Hunter extends Node3D:
	enum S { HIDDEN, PATROL, INVESTIGATE, SEARCH, CHASE, LEAVING }
	const WALK := 1.15
	const RUN := 4.2
	var level
	var camp := Vector3.ZERO
	var route: Array = []
	var actor: Actor
	var lamp: SpotLight3D
	var breath: AudioStreamPlayer3D
	var state := S.HIDDEN
	var wp := 0
	var target := Vector3.ZERO
	var suspicion := 0.0
	var last_seen := Vector3.ZERO
	var lost_t := 0.0
	var wait_t := 0.0
	var speed := 0.0
	var heading := 0.0
	var _vis_cd := 0.0
	var _said := false

	func _ready() -> void:
		actor = Actor.new()
		actor.character = "kidnapper"
		actor.ready.connect(func() -> void:
			actor.tint("", Color(0.22, 0.22, 0.24), 0.8)
			actor.hide_material("helmet")
			var mask := Node3D.new()
			B.model(mask, "sf:gasmask_gp5", Vector3.ZERO, 180.0, {"remove": ["Icosphere"], "height": 0.43})
			actor.attach("Head", mask, Vector3(0, -0.2, -0.1)), CONNECT_ONE_SHOT)
		add_child(actor)
		lamp = SpotLight3D.new()
		lamp.light_color = Color(1.0, 0.95, 0.85)
		lamp.light_energy = 5.0
		lamp.spot_range = 22.0
		lamp.spot_angle = 20.0
		lamp.shadow_enabled = true
		lamp.light_volumetric_fog_energy = 1.4
		add_child(lamp)
		lamp.position = Vector3(0.22, 1.35, -0.25)
		lamp.rotation_degrees = Vector3(-8, 0, 0)
		visible = false

	## Il sort du van (ou est déjà dehors) : sa ronde commence.
	func wake(from_van: bool) -> void:
		visible = true
		state = S.PATROL
		wp = 0
		heading = PI * 0.5
		breath = Sound.loop_at("gasmask_breath_loop", self, -2.0, 2.0, 16.0)
		if breath != null:
			breath.position.y = 1.6
		if from_van:
			# il va d'abord voir le groupe électrogène (là où était la batterie)
			state = S.INVESTIGATE
			target = camp + Vector3(-5.0, 0, -1.0)

	## Il remonte dans le van : la suite ne le regarde plus.
	func leave() -> void:
		if state == S.HIDDEN:
			return
		state = S.LEAVING
		target = camp + Vector3(3.0, 0, -4.0)

	func hear(pos: Vector3, radius: float) -> void:
		if state in [S.HIDDEN, S.CHASE, S.LEAVING]:
			return
		# il entend mal (le masque, le groupe électrogène) : seulement les bruits proches ou forts
		if global_position.distance_to(pos) < radius * 0.6:
			state = S.INVESTIGATE
			target = pos
			wait_t = 0.0

	func _process(delta: float) -> void:
		if state == S.HIDDEN or level == null or level.dying:
			return
		var p: Player = level.player
		_vision(delta, p)
		var goal := global_position
		var want_speed := 0.0
		match state:
			S.PATROL:
				goal = route[wp]
				want_speed = WALK
				if _flat(goal - global_position).length() < 0.6:
					wp = (wp + 1) % route.size()
			S.INVESTIGATE:
				goal = target
				want_speed = WALK * 1.5
				if _flat(goal - global_position).length() < 0.8:
					state = S.SEARCH
					wait_t = 0.0
			S.SEARCH:
				wait_t += delta
				heading += sin(wait_t * 1.6) * delta * 1.5
				if wait_t > 5.0:
					state = S.PATROL
			S.CHASE:
				goal = p.global_position if lost_t < 0.5 else last_seen
				want_speed = RUN
				if global_position.distance_to(p.global_position) < 1.25:
					level._die("hunter")
					return
				if lost_t > 4.5:
					state = S.SEARCH
					wait_t = 0.0
					suspicion = 0.5
			S.LEAVING:
				goal = target
				want_speed = WALK * 1.4
				if _flat(goal - global_position).length() < 0.8:
					state = S.HIDDEN
					visible = false
					if breath != null:
						breath.queue_free()
					return
		speed = lerpf(speed, want_speed, 1.0 - exp(-4.0 * delta))
		var to := _flat(goal - global_position)
		if to.length() > 0.2 and want_speed > 0.0:
			heading = lerp_angle(heading, atan2(-to.x, -to.z), 1.0 - exp(-5.0 * delta))
			var fwd := Vector3(-sin(heading), 0, -cos(heading))
			global_position += fwd * speed * delta
			# il contourne les troncs
			for o in level.trunks_near(global_position):
				var c: Vector3 = o[0]
				var r: float = float(o[1]) + 0.35
				var off := _flat(global_position - c)
				if off.length() < r and off.length() > 0.001:
					var out := off.normalized() * r
					global_position.x = c.x + out.x
					global_position.z = c.z + out.z
		rotation.y = heading
		global_position.y = 0.0
		actor.locomote("run" if speed > 2.5 else "walk", speed if want_speed > 0.0 else 0.0, "idle")
		# il balaie les sous-bois de sa lampe
		lamp.rotation_degrees.y = sin(Time.get_ticks_msec() / 900.0) * (6.0 if state == S.CHASE else 18.0)

	func _flat(v: Vector3) -> Vector3:
		return Vector3(v.x, 0, v.z)

	## Il VOIT : Théo dans son champ (55°), sans arbre entre eux. Plus visible debout, lampe allumée, en mouvement,
	## et surtout dans le faisceau de sa lampe ; beaucoup moins accroupi dans le noir.
	func _vision(delta: float, p: Player) -> void:
		_vis_cd -= delta
		if _vis_cd > 0.0:
			return
		_vis_cd = 0.12
		var dt := 0.12
		var eye := global_position + Vector3(0, 1.6, 0)
		var chest := p.global_position + Vector3(0, 0.6 if p.crouching else 1.1, 0)
		var to := chest - eye
		var d := to.length()
		var seen := false
		if d < 24.0 and state != S.LEAVING:
			var fwd := -global_basis.z
			var ang := fwd.dot(to.normalized())
			if ang > cos(deg_to_rad(55.0)) and level.has_los(eye, chest):
				var v := 1.0 - d / 24.0
				v *= 0.45 if p.crouching else 1.0
				v *= 1.0 if p.flashlight_on else 0.55
				if ang > cos(deg_to_rad(20.0)) and d < 16.0:
					v *= 2.2
				if p.moving:
					v *= 1.3
				suspicion = minf(suspicion + v * dt * 2.4, 1.5)
				seen = true
				if state == S.CHASE:
					last_seen = p.global_position
					lost_t = 0.0
		if not seen:
			suspicion = maxf(0.0, suspicion - dt * 0.3)
			if state == S.CHASE:
				lost_t += dt
		if state in [S.PATROL, S.SEARCH, S.INVESTIGATE]:
			if suspicion >= 1.0:
				state = S.CHASE
				last_seen = p.global_position
				lost_t = 0.0
				if not _said:
					_said = true
					Game.hud.say("Il m'a vu... COURS !", 1.8)
			elif suspicion > 0.45 and seen and state != S.INVESTIGATE:
				# quelque chose a bougé là-bas : il s'arrête et va voir
				state = S.INVESTIGATE
				target = p.global_position
