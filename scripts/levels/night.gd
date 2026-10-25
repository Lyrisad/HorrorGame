extends Level
## Actes I et II — La route puis la maison de Max, dans UN SEUL monde continu :
## la route traverse la forêt et continue après la maison ; la voiture quitte la route,
## remonte l'allée et se gare ; on en sort au même endroit.

const ROAD_W := 6.6
const D_JUNCTION := 1000.0
const CRUISE := 13.0
const PARK_LOCAL := Vector3(-0.6, 0, 13.6)

var curve := Curve3D.new()
var road_len := 0.0
var car_path := Curve3D.new()
var car_path_len := 0.0
var car_dist := 0.0
var car: CarRig
var house: HouseBuilder
var phase := "drive"
var creature: Creature
var figure_dist := 340.0
var figure_done := false
var music: AudioStreamPlayer3D
var _music_cut_said := false
var engine: AudioStreamPlayer
var roof_rain: AudioStreamPlayer
var radio: AudioStreamPlayer
var rain_out: AudioStreamPlayer
var rain_in: AudioStreamPlayer
var drone: AudioStreamPlayer
var rain_fx: GPUParticles3D
var lightning: DirectionalLight3D
var kidnapper: Actor
var _kidnapper_ready: Actor = null  ## créé (caché) au chargement : il n'a plus qu'à apparaître dans le bureau
var arrived := false
var _prev_heading := 0.0
var _lightning_cd := 14.0
var _inside_smooth := 0.0
var _time := 0.0

# état de la maison
var entered := false
var clues := {}
var blackout := false
var office_open := false
var abducted := false
var _entered_time := 0.0
var _phones_busy := false


func _ready() -> void:
	make_environment({
		"bg": Color(0.004, 0.005, 0.008),
		"ambient": Color(0.05, 0.06, 0.08),
		"ambient_energy": 0.3,
		"fog": true,
		"fog_color": Color(0.02, 0.025, 0.035),
		"fog_density": 0.014,
		"vfog": true,
		"vfog_density": 0.012,
		"vfog_albedo": Color(0.75, 0.78, 0.82),
		"vfog_length": 70.0,
		"vfog_aniso": 0.7,
		"ssao": true,
		"auto_exposure": true,
		"ae_scale": 0.3,
		"ae_max": 900.0,
		"exposure": 1.25,
	})
	env.sdfgi_enabled = false
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.15
	env.sdfgi_energy = 0.9
	Game.set_fx("grain", 0.045)
	Game.set_fx("gain", 0.28)
	Game.set_fx("saturation", 0.78)
	Sound.set_reverb(0.18, 0.06, 0.8)

	B.profile = Game.args.has("profile")
	var t0 := Time.get_ticks_msec()
	_build_road()
	var t1 := Time.get_ticks_msec()
	_build_house()
	var t2 := Time.get_ticks_msec()
	_build_world()
	var t3 := Time.get_ticks_msec()
	_build_car_path()
	print("CHARGEMENT route=%d maison=%d monde=%d ms" % [t1 - t0, t2 - t1, t3 - t2])

	car = CarRig.new()
	add_child(car)
	creature = Creature.new()
	add_child(creature)
	if Game.args.has("figtest"):
		figure_dist = 30.0
	var fp := curve.sample_baked(figure_dist)
	creature.global_position = fp + _right_at(figure_dist) * 4.3

	music = Sound.loop_at("party_music_loop", house.boombox, 6.0, 16.0, 260.0, "Music")
	rain_fx = Nature.rain(self, Vector3(16, 5, 26), 7000)
	var pm := rain_fx.process_material as ParticleProcessMaterial
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	var shield := GPUParticlesCollisionBox3D.new()
	shield.size = Vector3(17.6, 6.4, 14.4)
	house.add_child(shield)
	shield.position = Vector3(0, 3.2, 0.3)

	var start := str(params.get("start", Game.args.get("start", "drive")))
	if Game.args.get("autotest", "") == "house":
		start = "house"
	if start == "house":
		_start_parked()
	else:
		_drive()


# ================================================================== route & monde
func _build_road() -> void:
	var pts := [Vector3(0, 0, 40), Vector3(0, 0, -60), Vector3(22, 0, -160), Vector3(12, 0, -260), Vector3(-28, 0, -350),
		Vector3(-34, 0, -450), Vector3(-4, 0, -540), Vector3(26, 0, -630), Vector3(24, 0, -720), Vector3(10, 0, -800),
		Vector3(6, 0, -900), Vector3(-14, 0, -1000), Vector3(-46, 0, -1090), Vector3(-70, 0, -1200)]
	for i in pts.size():
		var p: Vector3 = pts[i]
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var nxt: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var handle: Vector3 = (nxt - prev) * 0.22
		curve.add_point(p, -handle, handle)
	curve.bake_interval = 0.5
	road_len = curve.get_baked_length()
	var road_st := SurfaceTool.new()
	road_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var line_st := SurfaceTool.new()
	line_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shoulder_st := SurfaceTool.new()
	shoulder_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 2.0
	var d := 0.0
	while d < road_len - step:
		var a := curve.sample_baked(d)
		var b := curve.sample_baked(d + step)
		var ra := _right_at(d)
		var rb := _right_at(d + step)
		_strip(road_st, a, b, ra, rb, -ROAD_W * 0.5, ROAD_W * 0.5, 0.03, d, d + step)
		for side in [-1.0, 1.0]:
			_strip(shoulder_st, a, b, ra, rb, minf(side * ROAD_W * 0.5, side * (ROAD_W * 0.5 + 1.2)), maxf(side * ROAD_W * 0.5, side * (ROAD_W * 0.5 + 1.2)), 0.015, d, d + step)
		for e in [-ROAD_W * 0.5 + 0.25, ROAD_W * 0.5 - 0.25]:
			_strip(line_st, a, b, ra, rb, e - 0.06, e + 0.06, 0.04, d, d + step)
		if fmod(d, 9.0) < 3.0:
			_strip(line_st, a, b, ra, rb, -0.06, 0.06, 0.04, d, d + step)
		d += step
	for pair in [[road_st, B.mat("asphalt_02", 4.0, {"triplanar": false, "roughness": 0.45, "color": Color(0.5, 0.5, 0.5)})],
			[line_st, B.color_mat(Color(0.72, 0.72, 0.68), 0.4)],
			[shoulder_st, B.mat("gravel_road", 2.0, {"triplanar": false, "color": Color(0.5, 0.48, 0.45)})]]:
		var st: SurfaceTool = pair[0]
		st.generate_normals()
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = pair[1]
		add_child(mi)


func _right_at(d: float) -> Vector3:
	var a := curve.sample_baked(clampf(d - 1.0, 0.0, road_len))
	var b := curve.sample_baked(clampf(d + 1.0, 0.0, road_len))
	return (b - a).normalized().cross(Vector3.UP).normalized()


func _strip(st: SurfaceTool, a: Vector3, b: Vector3, ra: Vector3, rb: Vector3, x0: float, x1: float, y: float, d0: float, d1: float) -> void:
	var a0 := a + ra * x0 + Vector3(0, y, 0)
	var a1 := a + ra * x1 + Vector3(0, y, 0)
	var b0 := b + rb * x0 + Vector3(0, y, 0)
	var b1 := b + rb * x1 + Vector3(0, y, 0)
	for v in [[a0, Vector2(x0, d0)], [b0, Vector2(x0, d1)], [b1, Vector2(x1, d1)], [a0, Vector2(x0, d0)], [b1, Vector2(x1, d1)], [a1, Vector2(x1, d0)]]:
		st.set_uv(v[1])
		st.add_vertex(v[0])


func _build_house() -> void:
	var j := curve.sample_baked(D_JUNCTION)
	var r := _right_at(D_JUNCTION)
	var f := r.cross(Vector3.UP) * -1.0
	house = HouseBuilder.new()
	house.name = "House"
	house.callbacks = {"tv": _clue_tv, "phones": _clue_phones, "note": _clue_note, "laptop": _clue_laptop}
	add_child(house)
	house.global_position = j + r * 28.0 + f * 2.0
	var to_road := -r
	house.rotation.y = atan2(to_road.x, to_road.z)
	house.build()
	# les lampes de la maison (et leurs ombres) s'éteignent au loin : gros gain de performance
	for l in house.find_children("*", "Light3D", true, false):
		var light := l as Light3D
		light.distance_fade_enabled = true
		light.distance_fade_begin = 40.0
		light.distance_fade_shadow = 22.0
		light.distance_fade_length = 10.0
	# porte d'entrée, porte de derrière, bureau
	var fd := Interactable.create(house.inside, Vector3(-2.5, 1.1, 5.95), Vector3(1.0, 2.0, 0.4), "Pousser la porte", _open_front_door)
	fd.name = "FrontDoor"
	var bd := Interactable.create(house.inside, Vector3(7.9, 1.1, 0.47), Vector3(0.4, 2.0, 0.95), "Ouvrir", _try_back_door)
	bd.name = "BackDoor"
	var od := Interactable.create(house.inside, Vector3(5.05, 1.1, -0.9), Vector3(0.9, 2.0, 0.4), "Ouvrir", func() -> void:
		Sound.play_at("door_locked", house.inside.to_global(Vector3(5.05, 1.0, -1.0)), -6.0)
		Game.hud.say("Fermé à clé. Max garde son bureau fermé ?", 3.0)
		_clue("office_door"))
	od.name = "OfficeDoor"
	var tap := house.inside.find_child("Tap", false, false) as Node3D
	# un filet d'eau qui tombe dans l'évier (audible depuis le couloir, sans couvrir la musique)
	var tap_sound := Sound.loop_at("tap_running_loop", tap, -6.0, 2.0, 14.0)
	Interactable.create(house.inside, Vector3(-1.75, 0.95, -3.0), Vector3(0.4, 0.3, 0.55), "Fermer le robinet", func() -> void:
		if is_instance_valid(tap_sound):
			tap_sound.queue_free()
		Sound.play_at("pickup", tap.global_position, -8.0)
		Game.hud.say("Le robinet coulait... Qui laisse couler l'eau comme ça ?", 3.5))
	# l'enceinte : on peut couper (et remettre) la musique
	var k := 1.0 / house.boombox.scale.x
	var bb := Interactable.create(house.boombox, Vector3(0, 0.2, 0) * k, Vector3(0.6, 0.45, 0.4) * k, "Couper la musique", Callable())
	bb.name = "Boombox"
	bb.on_use = func() -> void:
		if blackout or not is_instance_valid(music):
			return
		music.stream_paused = not music.stream_paused
		Sound.play_at("ui_beep", house.boombox.global_position, -14.0, 0.6)
		bb.prompt = "Remettre la musique" if music.stream_paused else "Couper la musique"
		if music.stream_paused and not _music_cut_said:
			_music_cut_said = true
			Game.hud.say("Voilà. On s'entend penser.", 2.5)


func _build_world() -> void:
	Nature.ground(self, 1700.0, "forrest_ground_01", 3.0, Vector3(0, -0.02, -560), Color(0.45, 0.45, 0.4))
	# pelouse et allée autour de la maison
	var lawn := B.box(house, Vector3(34, 0.02, 34), Vector3(0, 0.0, 6), B.mat("leafy_grass", 2.5, {"color": Color(0.5, 0.55, 0.45)}), false)
	lawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gravel := B.mat("gravel_road", 2.0, {"color": Color(0.55, 0.54, 0.5)})
	var pad := B.box(house, Vector3(10, 0.04, 8), Vector3(-3.5, 0.0, 13.5), gravel, false)
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# allée : s'arrête au bord de la route (accotement), avec un évasement pour tourner
	var road_edge := 28.0 - ROAD_W * 0.5 - 0.1
	var dv_pts := PackedVector2Array([Vector2(-3.4, 17.0), Vector2(0.2, 17.0), Vector2(0.2, road_edge - 2.2), Vector2(1.9, road_edge),
		Vector2(-5.1, road_edge), Vector2(-3.4, road_edge - 2.2)])
	var dv := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(dv_pts)
	for i in range(0, tris.size(), 3):
		var a := Vector3(dv_pts[tris[i]].x, 0.022, dv_pts[tris[i]].y)
		var b := Vector3(dv_pts[tris[i + 1]].x, 0.022, dv_pts[tris[i + 1]].y)
		var c := Vector3(dv_pts[tris[i + 2]].x, 0.022, dv_pts[tris[i + 2]].y)
		if (c - a).cross(b - a).y < 0.0:
			var tmp := b
			b = c
			c = tmp
		for v in [a, b, c]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(v.x, v.z) * 0.5)
			st.add_vertex(v)
	st.generate_tangents()
	dv.mesh = st.commit()
	dv.material_override = gravel
	dv.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	house.add_child(dv)
	B.box(house, Vector3(1.5, 0.04, 2.6), Vector3(-2.5, 0.0, 9.9), gravel, false)
	# voitures des amis
	_parked_car(Vector3(-6.9, 0, 12.2), 4.0, Color(0.45, 0.06, 0.07))
	_parked_car(Vector3(-4.1, 0, 12.9), -3.0, Color(0.55, 0.56, 0.58))
	# boîte aux lettres à l'entrée de l'allée, en retrait de la route
	var mb_pos := house.to_global(Vector3(3.3, 0, 23.0))
	var mb := Node3D.new()
	add_child(mb)
	mb.global_position = mb_pos
	mb.rotation.y = house.rotation.y
	var wood := B.mat("worn_planks", 1.0, {"color": Color(0.5, 0.45, 0.4)})
	B.box(mb, Vector3(0.1, 1.1, 0.1), Vector3(0, 0.55, 0), wood, true)
	B.box(mb, Vector3(0.28, 0.25, 0.45), Vector3(0, 1.2, 0), B.color_mat(Color(0.15, 0.25, 0.18), 0.5, 0.4), false)
	B.label3d(mb, "DUBREUIL", Vector3(0.0, 1.2, 0.231), 28, Color(0.9, 0.9, 0.85), Vector3.ZERO, null, 0.0016)
	# forêt
	var hp := house.global_position
	Nature.scatter_forest(self, Rect2(-150, -1250, 300, 1310), 3200, func(p: Vector3) -> bool:
		var c := curve.get_closest_point(p)
		if Vector2(c.x - p.x, c.z - p.z).length() < 8.5:
			return true
		var lp := house.to_local(p)
		return absf(lp.x) < 19.0 and lp.z > -16.0 and lp.z < 36.0, 9)
	# balises
	var post_mat := B.color_mat(Color(0.85, 0.85, 0.82), 0.5)
	var refl := B.emissive(Color(1.0, 0.45, 0.1), 0.5)
	var d := 10.0
	while d < road_len - 20.0:
		var p := curve.sample_baked(d)
		var r := _right_at(d)
		for side in [-1.0, 1.0]:
			var pos: Vector3 = p + r * side * (ROAD_W * 0.5 + 1.3)
			if absf(d - D_JUNCTION) < 12.0 and side > 0.0:
				continue
			B.box(self, Vector3(0.1, 1.0, 0.1), pos + Vector3(0, 0.5, 0), post_mat, false)
			B.box(self, Vector3(0.105, 0.12, 0.06), pos + Vector3(0, 0.82, 0), refl, false)
		d += 25.0
	# lune, éclairs
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.5, 0.6, 0.85)
	moon.light_energy = 0.05
	moon.rotation_degrees = Vector3(-40, -30, 0)
	add_child(moon)
	lightning = DirectionalLight3D.new()
	lightning.light_color = Color(0.75, 0.82, 1.0)
	lightning.light_energy = 0.0
	lightning.rotation_degrees = Vector3(-60, -20, 0)
	lightning.shadow_enabled = true
	add_child(lightning)


func _parked_car(local_pos: Vector3, yaw_deg: float, color: Color) -> void:
	var holder := Node3D.new()
	house.add_child(holder)
	holder.position = local_pos
	holder.rotation_degrees.y = yaw_deg
	var m := B.model(holder, "sf:corolla", Vector3.ZERO, 180.0, {"center": false, "remove": ["Cube_002", "Cube_003"], "collide": true})
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := mi as MeshInstance3D
		for s in mesh_i.mesh.get_surface_count():
			var mat := mesh_i.get_active_material(s)
			if mat is StandardMaterial3D and mat.resource_name.begins_with("main_paint"):
				var nm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				nm.albedo_color = color
				nm.metallic = 0.6
				nm.roughness = 0.3
				nm.clearcoat_enabled = true
				mesh_i.set_surface_override_material(s, nm)


## Trajet de la voiture : la route, puis l'allée jusqu'à la place de parking.
func _build_car_path() -> void:
	var pts: Array[Vector3] = []
	var d := 0.0
	while d < D_JUNCTION - 26.0:
		pts.append(curve.sample_baked(d) + _right_at(d) * 1.7)
		d += 12.0
	var j := curve.sample_baked(D_JUNCTION)
	var r := _right_at(D_JUNCTION)
	var f := r.cross(Vector3.UP) * -1.0
	pts.append(j - f * 12.0 + r * 1.8)
	pts.append(j - f * 4.0 + r * 2.8)
	pts.append(house.to_global(Vector3(-1.6, 0, 25.5)))
	pts.append(house.to_global(Vector3(-1.4, 0, 19.0)))
	pts.append(house.to_global(PARK_LOCAL + Vector3(0, 0, 0.8)))
	pts.append(house.to_global(PARK_LOCAL))
	for i in pts.size():
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var nxt: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var h: Vector3 = (nxt - prev) * 0.2
		car_path.add_point(pts[i], -h, h)
	car_path.bake_interval = 0.25
	car_path_len = car_path.get_baked_length()


func _place_car(delta: float) -> void:
	var p := car_path.sample_baked(car_dist)
	var ahead := car_path.sample_baked(minf(car_dist + 2.0, car_path_len))
	var fwd := ahead - p
	fwd.y = 0
	if fwd.length() < 0.05:
		fwd = -car.global_basis.z
	fwd = fwd.normalized()
	var heading := atan2(-fwd.x, -fwd.z)
	if car_dist > car_path_len - 1.0:
		heading = house.rotation.y
	if delta > 0.0:
		var turn := wrapf(heading - _prev_heading, -PI, PI) / delta
		car.steer = lerpf(car.steer, turn * 0.6, 1.0 - exp(-3.0 * delta))
	_prev_heading = heading
	car.global_position = p
	car.rotation = Vector3(0, lerp_angle(car.rotation.y, heading, 1.0 if delta == 0.0 else 1.0 - exp(-8.0 * delta)), 0)


# ================================================================== acte I : la route
func _drive() -> void:
	phase = "drive"
	# en voiture : exposition fixe (habitacle sombre, seuls le tableau de bord et les phares éclairent)
	cam_attr.auto_exposure_enabled = false
	env.tonemap_exposure = 1.7
	env.ambient_light_energy = 0.18
	Game.set_clock(23, 41, 7, 14)
	Game.hud.show_hud(true)
	Game.hud.set_battery(4)
	car.cam.current = true
	car.speed = CRUISE
	_place_car(0.0)
	engine = Sound.loop("engine_loop", -8.0, "World")
	roof_rain = Sound.loop("rain_car_loop", -12.0)
	radio = Sound.loop("radio_loop", -18.0, "World")
	Sound.muffle_music(300.0)
	Sound.play("ui_beep", -10.0, 1.0, "UI")
	await Game.ui.fade_to(0.0, 2.0)
	await wait(1.0)
	Game.hud.say("Douze heures de garde... J'en peux plus.", 3.2)
	await wait(4.5)
	# les messages se lisent sur l'écran du téléphone, que Théo lève devant la caméra
	var ph := car.phone_ui
	car.message("Max", "t'es où ?? on t'attend 🍻")
	await wait(1.4)
	car.raise_phone(true)
	await wait(2.4)
	ph.open_chat("Max")
	Sound.play("phone_tap", -18.0, 0.8, "UI")
	await wait(1.6)
	Game.hud.say("J'arrive, j'arrive...", 2.2)
	await ph.type_reply("j'arrive, j'arrive… 10 min")
	await wait(0.8)
	await ph.receive("Max", "grouille, on coupe le gâteau sans toi sinon 🎂", 1.6)
	await wait(2.6)
	car.raise_phone(false)
	# (la silhouette au bord de la route)
	await wait_until(func() -> bool: return figure_done)
	await wait(5.0)
	car.message("Inès", "ramène des glaçons stp 🙏")
	await wait(1.2)
	car.raise_phone(true)
	await wait(2.6)
	Game.hud.say("Trop tard pour les glaçons.", 2.4)
	await wait(1.6)
	car.raise_phone(false)
	await wait(4.5)
	car.message("Karim", "théo viens vite")
	await wait(1.2)
	car.raise_phone(true)
	await wait(1.8)
	ph.open_chat("Karim")
	await wait(0.6)
	await ph.receive("Karim", "y a un truc bizarre ici", 1.8)
	await wait(1.6)
	Game.hud.say("Comment ça, « bizarre » ?", 2.2)
	await ph.type_reply("?? réponds")
	await wait(2.5)
	ph.call_contact("Karim")
	Sound.play("phone_tap", -18.0, 0.8, "UI")
	await wait(0.8)
	for i in 3:
		Sound.play_at("ringback", car.phone.global_position, -16.0, 1.0, 1.0, 6.0)
		await wait(2.4)
	ph.set_call_status("Messagerie vocale")
	await wait(0.6)
	Game.hud.say("Il répond pas...", 2.5)
	await wait(2.6)
	car.raise_phone(false)
	await wait_until(func() -> bool: return car_dist > D_JUNCTION - 120.0)
	Game.hud.say("C'est la maison de Max, là-bas. Ils ont mis le son à fond, eux.", 4.0)


func _figure_sequence() -> void:
	creature.stand_and_watch(car.cam_rig, "listen", 0.5)
	if Game.args.has("debugfig"):
		for i in 12:
			print("FIG creature=%s vis=%s state=%d car=%s dist=%.1f" % [creature.global_position, creature.is_visible_in_tree(), creature.state, car.global_position, car_dist])
			await wait(1.0)
	await wait_until(func() -> bool: return car_dist > figure_dist - 32.0)
	Sound.fade(radio, -40.0, 0.2)
	var stat := Sound.loop("static_loop", -14.0, "World")
	Game.glitch(0.35)
	await wait_until(func() -> bool: return car_dist > figure_dist + 8.0)
	Sound.play("stinger_soft", -8.0)
	await wait(1.5)
	if is_instance_valid(stat):
		stat.queue_free()
	Sound.fade(radio, -18.0, 1.0)
	Game.hud.say("...C'était quoi, ça ?", 2.5)
	await wait_until(func() -> bool: return car_dist > figure_dist + 45.0)
	creature.deactivate()
	figure_done = true
	await wait(1.0)
	Game.hud.say("Quelqu'un... planté au bord de la route, à cette heure-là ?", 3.5)


func _arrive() -> void:
	arrived = true
	car.speed = 0.0
	car.engine_on = false
	Sound.fade(engine, -60.0, 1.5, true)
	Sound.play("engine_stop", -6.0)
	Sound.fade(radio, -60.0, 0.5, true)
	car.set_headlights(false)
	await wait(1.4)
	Game.hud.say("Bon. C'est là.", 2.0)
	await wait(1.0)
	Game.hud.prompt("Sortir de la voiture")
	await wait_until(func() -> bool: return Input.is_action_just_pressed("interact") or Game.args.has("autoexit"))
	Game.hud.prompt("")
	_exit_car()


## Sortie de voiture sans coupure : la caméra glisse du siège jusqu'à Théo debout.
func _exit_car() -> void:
	var seat := car.seat_transform()
	Sound.play_at("car_door", car.global_position, -2.0)
	var stand := house.to_global(PARK_LOCAL + Vector3(-1.45, 0, 0.6))
	spawn_player(stand, rad_to_deg(house.rotation.y) + 3.0)
	player.has_flashlight = false
	player.control_enabled = false
	player.set_cinematic(seat, 1.0)
	player.cam.current = true
	if is_instance_valid(roof_rain):
		Sound.fade(roof_rain, -60.0, 0.8, true)
	var tw := create_tween()
	tw.tween_method(func(w: float) -> void: player.set_cinematic(seat, w), 1.0, 0.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await wait(0.9)
	Sound.play_at("car_door", car.global_position + Vector3(0, 0.5, 0), -4.0, 1.1)
	await wait(0.6)
	player.control_enabled = true
	_start_walk()


func _start_parked() -> void:
	car_dist = car_path_len
	_place_car(0.0)
	car.speed = 0.0
	car.engine_on = false
	car.set_headlights(false)
	arrived = true
	figure_done = true
	creature.deactivate()
	Game.set_clock(23, 47, 50, 14)
	Game.hud.show_hud(true)
	Game.hud.set_battery(4)
	var stand := house.to_global(PARK_LOCAL + Vector3(-1.45, 0, 0.6))
	spawn_player(stand, rad_to_deg(house.rotation.y) + 3.0)
	player.has_flashlight = false
	player.cam.current = true
	# test : --hwarp=x,z (repère de la maison) --hyaw=deg --pitch=deg
	if Game.args.has("hwarp"):
		var w := str(Game.args["hwarp"]).split(",")
		player.global_position = house.inside.to_global(Vector3(float(w[0]), 0.05, float(w[1])))
		player.set_look(house.rotation.y + deg_to_rad(float(Game.args.get("hyaw", 0.0))), deg_to_rad(float(Game.args.get("pitch", 0.0))))
	Game.ui.fade_rect.color.a = 1.0
	_start_walk()
	await Game.ui.fade_to(0.0, 1.5)
	if Game.args.get("autotest", "") == "house":
		_autotest()
	if Game.args.has("doctest"):
		_doctest()
	if Game.args.has("stairtest"):
		_stairtest()
	if Game.args.has("tvtest"):
		_tvtest()
	# test : --officetest (avec --hwarp=6.0,-3.9 --hyaw=-20) → le bureau s'ouvre, la scène des écrans se lance
	if Game.args.has("officetest"):
		await wait(1.0)
		_office_opens()


## Test --stairtest (sans --shots) : Théo marche vers la porte depuis l'allée et monte le perron.
func _stairtest() -> void:
	await wait(1.5)
	player.global_position = house.to_global(Vector3(-2.5, 0.05, 10.2))
	player.set_look(house.rotation.y, 0.0)
	await wait(0.5)
	Input.action_press("move_forward")
	var last_y := player.global_position.y
	var max_jump := 0.0
	var t := 0.0
	while t < 3.0:
		await ticked
		t += get_process_delta_time()
		var y := player.global_position.y
		max_jump = maxf(max_jump, absf(y - last_y))
		last_y = y
	Input.action_release("move_forward")
	var lp := house.to_local(player.global_position)
	print("STAIRTEST arrivé z=%.2f y=%.2f (terrasse à %.2f) · plus gros saut en une image : %.3f m" % [lp.z, lp.y, HouseBuilder.FLOOR_Y, max_jump])


## Test --tvtest : la télé éteinte, puis elle s'allume (captures --shots=1.5,3.2,6).
func _tvtest() -> void:
	await wait(2.0)
	_tv_power_on(true)


## Test --doctest : E pour lire la liste du frigo, E pour la refermer — elle ne doit pas se rouvrir.
func _doctest() -> void:
	await wait(2.0)
	var note: Interactable = null
	for it in house.inside.find_children("*", "Interactable", true, false):
		if (it as Interactable).prompt == "Lire la liste":
			note = it
	player.global_position = note.global_position + house.global_basis * Vector3(0, -1.32, 0.9)
	player.global_position.y = house.inside.global_position.y
	await wait(0.3)
	var to := note.global_position - player.head.global_position
	player.set_look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	var press := func() -> void:
		var ev := InputEventAction.new()
		ev.action = "interact"
		ev.pressed = true
		Input.parse_input_event(ev)
		await get_tree().create_timer(0.08).timeout
		var up := InputEventAction.new()
		up.action = "interact"
		up.pressed = false
		Input.parse_input_event(up)
	await wait(1.0)
	await press.call()
	await wait(1.0)
	print("DOCTEST après 1er E : document ouvert = ", Game.ui.document_open)
	await press.call()
	await wait(1.0)
	print("DOCTEST après 2e E : document ouvert = ", Game.ui.document_open)


# ================================================================== acte II : la maison
func _start_walk() -> void:
	phase = "walk"
	# à pied : éclairage global en temps réel (rebonds de lumière dans la maison) + auto-exposition
	env.sdfgi_enabled = true
	env.ambient_light_energy = 0.3
	env.tonemap_exposure = 1.25
	cam_attr.auto_exposure_enabled = true
	for c in house.cams:
		c.target = player
	rain_out = Sound.loop("rain_loop", -6.0)
	rain_in = Sound.loop("rain_inside_loop", -60.0)
	drone = Sound.loop("drone_house", -60.0)
	Sound.set_reverb(0.35, 0.12, 0.6)
	await wait(0.8)
	Game.hud.objective("Rejoindre la soirée")
	add_trigger(house.to_global(Vector3(-2.5, 0, 4.6)), 1.4, _on_enter)


func get_surface(pos: Vector3) -> String:
	var lp := house.to_local(pos)
	var r := house.room_of(lp)
	if r == "dehors":
		if lp.y > 0.2 and lp.z > 5.9 and lp.z < 8.4:
			return "wood"
		var c := curve.get_closest_point(pos)
		if Vector2(c.x - pos.x, c.z - pos.z).length() < ROAD_W * 0.5:
			return "concrete"
		if (absf(lp.x + 3.5) < 5.0 and lp.z > 9.5 and lp.z < 17.5) or (absf(lp.x + 1.6) < 1.8 and lp.z > 17.0):
			return "gravel"
		return "grass"
	if r == "cuisine" or r == "sdb":
		return "concrete"
	return "wood"


func _open_front_door() -> void:
	var fd := house.inside.find_child("FrontDoor", false, false) as Interactable
	fd.disable()
	Sound.play_at("door_creak", house.inside.to_global(Vector3(-2.5, 1.2, 6.0)), -2.0)
	house.swing_door(house.front_door, 100.0, 1.6)
	house.front_door_body.collision_layer = 0
	await wait(0.4)
	Game.hud.say("Max ? C'est moi !", 2.0)


func _on_enter() -> void:
	if entered:
		return
	entered = true
	_entered_time = _time
	await wait(1.0)
	Game.hud.say("Les gars ? ...Il y a quelqu'un ?", 3.0)
	await wait(3.4)
	Game.hud.say("Toutes les lumières allumées, la musique... et personne.", 3.5)
	await wait(3.0)
	Game.hud.objective("Trouver Max, Inès et Karim")
	add_trigger(house.inside.to_global(Vector3(-5.6, 0, 0.9)), 2.2, func() -> void: _tv_power_on(true))
	_clue_hints()


## Tout ce que Théo doit avoir vu avant que le courant saute.
const HOUSE_CLUES := ["note", "tv", "laptop", "phones", "office_door", "back_door"]
## Ce que Théo se dit pour orienter le joueur quand il tourne en rond.
const CLUE_HINTS := {
	"note": "Il y a un papier sur le frigo...",
	"tv": "La télé est allumée dans le salon... sur quelle chaîne ?",
	"laptop": "L'ordi de Max, dans la chambre... Il est resté allumé ?",
	"phones": "Des téléphones, sur la table basse du salon ?",
	"office_door": "Et le bureau de Max, au fond du couloir ?",
	"back_door": "La porte de derrière, dans la cuisine... Ils sont peut-être sortis par là ?",
}
var _last_clue_time := 0.0


func _clue(id: String) -> void:
	if not clues.has(id):
		_last_clue_time = _time
	clues[id] = true
	if blackout:
		return
	for c in HOUSE_CLUES:
		if not clues.has(c):
			return
	await wait(3.0)
	_blackout()


## Pistes restantes : si le joueur ne trouve plus rien pendant un moment, Théo y pense tout haut.
func _clue_hints() -> void:
	while not blackout:
		await wait(5.0)
		if not entered or _phones_busy or Game.ui.document_open:
			continue
		if _time - maxf(_last_clue_time, _entered_time) < 50.0:
			continue
		for c in HOUSE_CLUES:
			if not clues.has(c):
				Game.hud.say(CLUE_HINTS[c], 3.5)
				_last_clue_time = _time
				break


## Les téléphones des trois amis, alignés sur la table basse. Théo se penche (gros plan),
## les écrans s'allument : appels manqués d'un numéro masqué... puis ça sonne, l'un après
## l'autre, et les trois se taisent d'un coup sur le même message.
func _clue_phones() -> void:
	if clues.has("phones") or _phones_busy:
		if clues.has("phones"):
			Game.hud.say("Leurs trois téléphones. Alignés.", 2.5)
		return
	_phones_busy = true
	player.control_enabled = false
	player.look_enabled = false
	var start := player.head.global_transform
	var center := house.inside.to_global(Vector3(-5.32, 0.4, 1.3))
	var eye := center + house.global_basis * Vector3(0.0, 0.27, 0.16)
	var close := Transform3D(Basis.looking_at(center - eye, house.global_basis.z * -1.0), eye)
	var tw := create_tween()
	tw.tween_method(func(w: float) -> void: player.set_cinematic(start.interpolate_with(close, w), 1.0), 0.0, 1.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await wait(1.0)
	Sound.play("phone_tap", -14.0, 1.0, "UI")
	for ph in house.phones:
		var m := ph.get_meta("screen") as StandardMaterial3D
		m.emission_texture = load("res://assets/gen/phone_lock_%d.png" % house.phones.find(ph))
		create_tween().tween_property(m, "emission_energy_multiplier", 0.11, 0.25)
		await wait(0.25)
	Game.hud.say("Les téléphones de Max, Inès et Karim... Ils seraient jamais partis sans.", 3.6)
	await wait(3.8)
	Game.hud.say("Trois appels manqués. Numéro masqué. Sur les trois.", 3.2)
	await wait(3.0)
	# ça sonne : un, puis deux, puis trois
	var rings: Array[AudioStreamPlayer3D] = []
	for i in house.phones.size():
		var m := house.phones[i].get_meta("screen") as StandardMaterial3D
		m.emission_texture = load("res://assets/gen/phone_call.png")
		m.emission_energy_multiplier = 0.12
		rings.append(Sound.loop_at("ringtone_%d" % i, house.phones[i], -4.0, 2.0, 18.0))
		Game.shake(0.15)
		await wait(0.9)
	Game.glitch(0.2)
	await wait(2.0)
	# ...et tout s'arrête en même temps
	for r in rings:
		if is_instance_valid(r):
			r.queue_free()
	Game.glitch(0.35)
	for ph in house.phones:
		var m2 := ph.get_meta("screen") as StandardMaterial3D
		m2.emission_texture = load("res://assets/gen/phone_watch.png")
	Sound.play("stinger_soft", -8.0)
	await wait(1.6)
	Game.hud.say("« Souris, Théo »...? Sur LEURS téléphones ?", 2.8)
	await wait(3.0)
	Game.hud.say("C'est quoi ce délire... Les gars ? C'est une blague, c'est ça ?", 3.2)
	await wait(3.4)
	var back := player.head.global_transform
	var tw2 := create_tween()
	tw2.tween_method(func(w: float) -> void: player.set_cinematic(close.interpolate_with(back, w), 1.0 - w), 0.0, 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	await wait(0.9)
	player.set_cinematic(Transform3D(), 0.0)
	player.control_enabled = true
	player.look_enabled = true
	for ph in house.phones:
		create_tween().tween_property(ph.get_meta("screen") as StandardMaterial3D, "emission_energy_multiplier", 0.0, 3.0).set_delay(3.0)
	_phones_busy = false
	_clue("phones")


var tv_on := false


## La télé s'allume d'elle-même (ou parce qu'on appuie sur le bouton) : neige, puis le direct.
func _tv_power_on(by_itself: bool) -> void:
	if tv_on:
		return
	tv_on = true
	var tv := house.inside.to_global(Vector3(-5.6, 0.9, -0.7))
	Sound.play_at("flicker", tv, -6.0, 1.3, 2.0, 15.0)
	var snow := Sound.loop_at("static_loop", house.tv_light, -12.0, 2.0, 12.0)
	house.tv_light.visible = true
	var m := house.tv_material
	m.set_shader_parameter("static_mix", 1.0)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("power", v), 0.0, 1.0, 0.25)
	tw.tween_interval(0.6)
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("static_mix", v), 1.0, 0.0, 0.9)
	await tw.finished
	if is_instance_valid(snow):
		snow.queue_free()
	var use := house.inside.find_child("TVUse", false, false) as Interactable
	if use != null:
		use.prompt = "Regarder la télé"
	if by_itself:
		await wait(0.4)
		Game.hud.say("...Elle s'est allumée toute seule ?", 2.6)


func _clue_tv() -> void:
	if not tv_on:
		await _tv_power_on(false)
		await wait(0.5)
	if clues.has("tv"):
		Game.hud.say("Elle filme le salon. Elle me filme, moi.", 2.5)
		return
	Game.hud.say("C'est quoi cette chaîne... C'est le salon. C'est... moi ?", 3.6)
	await wait(1.5)
	for c in house.cams:
		c.tracking = true
	Sound.play("stinger_soft", -10.0)
	await wait(2.5)
	Game.hud.say("Il y a des caméras partout...", 3.0)
	_clue("tv")


func _clue_note() -> void:
	await read_document("La liste du frigo", "[b]LISTE[/b]\n\nMaxime   ✓\nInès   ✓\nKarim   ✓\nThéo   ☐\n\n[i]« Le public a choisi. »[/i]", "paper")
	if not clues.has("note"):
		Game.hud.say("C'est une blague ? C'est leur écriture, ça ?", 3.0)
		_clue("note")


func _clue_laptop() -> void:
	await read_document("L'écran de l'ordinateur",
		"[b]FLUX — SESSION 14[/b]\n\n" +
		"SUJET 1   M. DUBREUIL     [color=#c33]RÉCUPÉRÉ[/color]\n" +
		"SUJET 2   I. FERRAND      [color=#c33]RÉCUPÉRÉ[/color]\n" +
		"SUJET 3   K. HADDAD       [color=#c33]RÉCUPÉRÉ[/color]\n" +
		"SUJET 4   T. MARCHAND     [color=#3a3]EN DIRECT[/color]\n\n" +
		"Spectateurs connectés : 1 892\nProchaine étape : [i]descente[/i]", "typed")
	if not clues.has("laptop"):
		Game.hud.say("« Sujet 4 »... C'est moi. Qu'est-ce que c'est que ce délire ?!", 3.5)
		_clue("laptop")


func inventory() -> Array:
	var items := [{"id": "phone", "name": "Téléphone", "desc": "Le tien. Plus de réseau depuis que tu es entré dans la maison."}]
	if player != null and player.has_flashlight:
		items.append({"id": "flashlight", "name": "Lampe torche", "desc": "Celle de ton service, toujours à la ceinture. [F] pour l'allumer."})
	return items


func _blackout() -> void:
	if blackout:
		return
	blackout = true
	# Théo doit être bien à l'intérieur (pas dehors, pas dans l'embrasure) : la porte va claquer
	await wait_until(_player_well_inside)
	var bb := house.boombox.find_child("Boombox", false, false) as Interactable
	if bb != null:
		bb.disable()
	if is_instance_valid(music) and not music.stream_paused:
		Sound.play("tape_stop", 0.0, 1.0, "Music")
	Sound.fade(music, -60.0, 0.05, true)
	await wait(0.6)
	Sound.play("power_down", 0.0)
	# la porte d'entrée claque dans le noir, aussitôt : impossible de ressortir
	Sound.play_at("door_slam", house.inside.to_global(Vector3(-2.5, 1.2, 6.0)), 6.0, 1.0, 10.0, 60.0)
	house.swing_door(house.front_door, 0.0, 0.18)
	house.front_door_body.collision_layer = 1
	var fd := house.inside.find_child("FrontDoor", false, false) as Interactable
	fd.prompt = "Ouvrir"
	fd.on_use = _try_front_door
	fd.enabled = true
	fd.collision_layer = 4
	Game.shake(0.6)
	for l in house.room_lights:
		if not l.has_meta("candle"):
			l.visible = false
	for g in house.lamp_glows:
		g.visible = false
	for g in house.window_glows:
		g.visible = false
	Game.glitch(0.4)
	Sound.fade(drone, -12.0, 4.0)
	for c in house.cams:
		c.tracking = true
	await wait(2.5)
	Game.hud.say("...Okay. C'est pas drôle, les gars.", 3.0)
	await wait(2.5)
	player.has_flashlight = true
	Game.hud.pickup("Lampe torche")
	Game.hud.objective("Allumer la lampe torche")
	Game.hud.hint("[F] Lampe torche", 5.0)
	await wait_until(func() -> bool: return player.flashlight_on)
	await wait(2.0)
	# un grand coup contre le mur du bureau fermé, le rocking-chair se met à bouger
	Sound.play_at("thud_wall", house.inside.to_global(Vector3(5.0, 1.3, -1.6)), 6.0, 1.0, 8.0, 50.0)
	Game.shake(0.8)
	Game.glitch(0.3)
	_rock_chair()
	await wait(0.6)
	Game.hud.say("HÉ ! Qui est là ?!", 2.0)
	await wait(2.5)
	Game.hud.objective("Sortir de la maison")
	await wait(4.0)
	Sound.play_at("knock_sequence", house.inside.to_global(Vector3(5.0, 1.2, -2.5)), 0.0)


## Bien dans la maison, à distance de la porte d'entrée (dont le battant balaie ~1,5 m).
func _player_well_inside() -> bool:
	var lp := house.to_local(player.global_position)
	return house.room_of(lp) != "dehors" and Vector2(lp.x + 2.5, lp.z - 6.0).length() > 1.9


func _rock_chair() -> void:
	var rc := house.rocking_chair
	var t := 0.0
	while is_instance_valid(rc) and t < 40.0:
		await ticked
		t += get_process_delta_time()
		rc.rotation.x = sin(t * 2.4) * 0.12 * maxf(0.0, 1.0 - t / 40.0)
		if fmod(t, 2.62) < get_process_delta_time():
			Sound.play_at("door_creak", rc.global_position, -16.0, 1.6)


func _try_front_door() -> void:
	Sound.play_at("door_locked", house.inside.to_global(Vector3(-2.5, 1.0, 6.0)), -2.0)
	Game.hud.say("Verrouillée... de l'extérieur ?!", 2.5)
	_door_tried()


func _try_back_door() -> void:
	Sound.play_at("door_locked", house.inside.to_global(Vector3(8.0, 1.0, 0.5)), -2.0)
	if blackout:
		Game.hud.say("Fermée aussi. Putain...", 2.0)
		_door_tried()
	else:
		Game.hud.say("Fermée à clé. Ils ne sont pas sortis par là.", 2.5)
		_clue("back_door")


func _door_tried() -> void:
	if not office_open:
		await wait(2.5)
		_office_opens()


func _office_opens() -> void:
	if office_open:
		return
	office_open = true
	var od := house.inside.find_child("OfficeDoor", false, false)
	if od != null:
		od.queue_free()
	Sound.play_at("door_creak_slow", house.inside.to_global(Vector3(5.05, 1.2, -1.0)), 0.0)
	house.swing_door(house.office_door, 70.0, 4.0)
	house.office_door_body.collision_layer = 0
	house.feed.source = house.office_cam
	house.feed.cam_label = "CAM 06 — BUREAU"
	await wait(3.0)
	Game.hud.say("Le bureau... Il était fermé à clé, il y a une minute.", 3.5)
	Game.hud.objective("Le bureau")
	add_trigger(house.inside.to_global(Vector3(6.0, 0, -3.9)), 1.6, _office_scene)


func _office_scene() -> void:
	var monitors := house.inside.to_global(Vector3(6.7, 1.0, -5.6))
	var t := 0.0
	while t < 1.6:
		await ticked
		var fwd := -player.head.global_basis.z
		var to := (monitors - player.head.global_position).normalized()
		if fwd.dot(to) > 0.85:
			t += get_process_delta_time()
	Game.hud.say("C'est moi... en direct.", 2.5)
	await wait(2.0)
	# l'homme au masque apparaît dans l'encadrement, derrière (visible à l'écran)
	if is_instance_valid(_kidnapper_ready):
		kidnapper = _kidnapper_ready
		kidnapper.process_mode = Node.PROCESS_MODE_INHERIT
		kidnapper.visible = true
	else:
		kidnapper = _make_kidnapper()
		house.inside.add_child(kidnapper)
	kidnapper.position = Vector3(5.05, 0, -1.3)
	kidnapper.rotation.y = 0.0
	kidnapper.play("idle", 0.0, 0.6)
	var mask_breath := Sound.loop_at("gasmask_breath_loop", kidnapper, -3.0, 2.0, 16.0)
	mask_breath.position.y = 1.6
	Sound.play("stinger_soft", -4.0)
	Game.glitch(0.2, false)
	var waited := 0.0
	while waited < 6.0:
		await ticked
		var dt := get_process_delta_time()
		waited += dt
		var to_k := (kidnapper.global_position + Vector3(0, 1.5, 0) - player.head.global_position).normalized()
		if (-player.head.global_basis.z).dot(to_k) > 0.5 and waited > 0.6:
			break
		if waited > 2.0:
			var tgt := house.inside.to_local(player.global_position)
			var step := (Vector3(tgt.x, 0, tgt.z) - kidnapper.position)
			if step.length() > 1.4:
				kidnapper.position += step.normalized() * 0.55 * dt
				kidnapper.rotation.y = atan2(-step.x, -step.z)
				kidnapper.locomote("walk", 0.55, "idle")
	_abduction()


func prewarm_extras() -> Array:
	var out: Array = []
	if house != null and not abducted and not is_instance_valid(_kidnapper_ready):
		_kidnapper_ready = _make_kidnapper()
		house.inside.add_child(_kidnapper_ready)
		_kidnapper_ready.visible = false
		_kidnapper_ready.process_mode = Node.PROCESS_MODE_DISABLED
		out.append(_kidnapper_ready)
	if creature != null:
		out.append(creature)
	return out


func _make_kidnapper() -> Actor:
	var k := Actor.new()
	k.character = "kidnapper"
	k.ready.connect(func() -> void:
		k.tint("", Color(0.22, 0.22, 0.24), 0.8)
		k.hide_material("helmet")
		var mask := Node3D.new()
		B.model(mask, "sf:gasmask_gp5", Vector3.ZERO, 180.0, {"remove": ["Icosphere"], "height": 0.43})
		k.attach("Head", mask, Vector3(0, -0.2, -0.1)), CONNECT_ONE_SHOT)
	return k


func _abduction() -> void:
	if abducted:
		return
	abducted = true
	player.control_enabled = false
	player.look_enabled = false
	# une demi-seconde de silence complet (on n'entend plus que son souffle dans le masque)...
	Sound.muffle_master(250.0, 0.15)
	if is_instance_valid(drone):
		Sound.fade(drone, -60.0, 0.15)
	await wait(0.45)
	Sound.reset_effects()
	# ...puis le choc
	player.flicker(1.4)
	Sound.play("jumpscare", 4.0)
	Game.glitch(0.9, false)
	Game.shake(1.6)
	var fov0 := player.cam.fov
	create_tween().tween_property(player.cam, "fov", fov0 * 0.68, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	var eye := player.head.global_transform
	# Théo se tourne vers lui ; l'homme au masque fonce
	var t := 0.0
	while true:
		await ticked
		var dt := get_process_delta_time()
		t += dt
		var to_p := player.global_position - kidnapper.global_position
		to_p.y = 0.0
		var face := kidnapper.bone_position("Head")
		var look := Transform3D(Basis.looking_at((face - eye.origin).normalized(), Vector3.UP), eye.origin)
		player.set_cinematic(eye.interpolate_with(look, clampf(t / 0.18, 0.0, 1.0)), 1.0)
		if to_p.length() <= 0.75 or t > 3.0:
			break
		kidnapper.global_rotation.y = atan2(-to_p.x, -to_p.z)
		var spd := minf(6.0, 2.5 + t * 14.0)
		kidnapper.global_position += to_p.normalized() * minf(spd * dt, to_p.length() - 0.7)
		kidnapper.locomote("run", spd, "idle", 0.1)
	# face à face : le masque emplit l'image, un instant figé
	kidnapper.play("idle", 0.05, 0.0)
	var mask_t := Transform3D(Basis.looking_at((kidnapper.bone_position("Head") - eye.origin).normalized(), Vector3.UP), eye.origin)
	player.set_cinematic(mask_t, 1.0)
	Game.glitch(1.0, false)
	Sound.play("glitch_%d" % (randi() % 3), 2.0, 0.8, "UI")
	await wait(0.32)
	# le coup : poing en avant, impact sur la caméra
	var strike_speed := 1.25
	kidnapper.play("strike", 0.06, strike_speed)
	var face_now := kidnapper.bone_position("Head")
	var look_now := Transform3D(Basis.looking_at((face_now - eye.origin).normalized(), Vector3.UP), eye.origin)
	player.set_cinematic(look_now, 1.0)
	await wait(0.85 / strike_speed - 0.08)
	Sound.play("hit_impact", 2.0)
	Game.flash(0.9)
	Game.glitch(1.0, false)
	Game.shake(3.0)
	player.set_flashlight(false, true)
	player.cam.fov = fov0
	# chute en arrière : la caméra finit au sol, tournée vers lui
	var back := (player.global_position - kidnapper.global_position)
	back.y = 0.0
	back = back.normalized()
	var floor_pos := player.global_position + back * 0.35 + Vector3(0, 0.16, 0)
	var floor_t := Transform3D(Basis.looking_at((kidnapper.bone_position("Head") - floor_pos).normalized(), Vector3.UP) * Basis(Vector3.FORWARD, 0.35), floor_pos)
	var tw := create_tween()
	tw.tween_method(func(w: float) -> void: player.set_cinematic(look_now.interpolate_with(floor_t, w), 1.0), 0.0, 1.0, 0.45).set_ease(Tween.EASE_IN)
	await wait(0.45)
	Sound.play("body_fall", 0.0)
	Sound.play("tinnitus", -4.0)
	Sound.muffle_master(700.0, 0.4)
	Game.shake(1.0)
	var dropped := B.spot(self, player.global_position + back * 0.6 + Vector3(0.3, 0.08, 0.0), kidnapper.global_position + Vector3(0, 1.4, 0), Color(1, 0.95, 0.85), 4.0, 10.0, 26.0, true)
	dropped.light_volumetric_fog_energy = 1.5
	# il reste au-dessus de Théo, puis se penche pour l'attraper
	kidnapper.play("idle", 0.4, 0.5)
	await wait(2.0)
	Game.glitch(0.4, false)
	kidnapper.play("pickup", 0.3, 1.1)
	await wait(1.3)
	Sound.play("body_fall", -6.0, 1.3)
	Game.shake(1.5)
	await wait(1.0)
	# il le traîne vers la porte, à reculons, sans le quitter des yeux
	Game.glitch(0.6, false)
	var drag := Sound.loop("drag_loop", -6.0, "World")
	kidnapper.play("drag", 0.4, 1.3)
	var door_local := Vector3(5.05, 0, -0.6)
	var dragged := 0.0
	while dragged < 4.5:
		await ticked
		var dt2 := get_process_delta_time()
		dragged += dt2
		var to_door := house.inside.to_global(door_local) - kidnapper.global_position
		to_door.y = 0.0
		if to_door.length() > 0.1:
			kidnapper.global_position += to_door.normalized() * minf(0.45 * dt2, to_door.length())
			kidnapper.global_rotation.y = lerp_angle(kidnapper.global_rotation.y, atan2(to_door.x, to_door.z), 1.0 - exp(-4.0 * dt2))
		var fwd := -kidnapper.global_basis.z
		var cam_pos := kidnapper.global_position + fwd * 1.05 + Vector3(0, 0.2 + sin(dragged * 9.0) * 0.012, 0)
		var head_pos := kidnapper.bone_position("Head")
		var cam_t := Transform3D(Basis.looking_at((head_pos - cam_pos).normalized(), Vector3.UP) * Basis(Vector3.FORWARD, 0.3 + sin(dragged * 4.5) * 0.04), cam_pos)
		player.set_cinematic(cam_t, 1.0)
		if absf(dragged - 2.6) < dt2:
			Game.glitch(1.0, false)
	Game.set_blackout(true)
	if is_instance_valid(drag):
		drag.queue_free()
	Sound.play("signal_lost", -2.0, 1.0, "UI")
	Game.hud.show_hud(false)
	await wait(1.5)
	Sound.reset_effects()
	Game.clock_running = false
	await Game.ui.show_card([
		{"text": "SIGNAL PERDU", "style": "red"},
		{"text": "00:31:12 → 03:12:44", "style": "small"},
	], 1.4, 2.0, 1.0)
	Game.start_level("sewer")


## Test automatique : indices → coupure → porte → bureau → enlèvement.
func _autotest() -> void:
	await wait(1.0)
	player.global_position = house.inside.to_global(Vector3(-2.5, 0, 4.0))
	_open_front_door()
	_on_enter()
	await wait(1.0)
	player.global_position = house.inside.to_global(Vector3(-5.0, 0, 2.4))
	await _clue_phones()
	_clue_tv()
	await wait(5.0)
	_clue("note")
	_clue("laptop")
	_clue("office_door")
	print("AUTOTEST coupure avant la dernière piste ? ", blackout)
	_try_back_door()
	await wait(6.0)
	print("AUTOTEST coupure après toutes les pistes : ", blackout)
	player.set_flashlight(true)
	await wait(6.0)
	_try_front_door()
	await wait(6.0)
	player.global_position = house.inside.to_global(Vector3(6.1, 0, -3.9))
	player.set_look(house.rotation.y, -0.2)


## Pour l'éditeur de carte intégré.
func editor_map() -> Dictionary:
	return {"id": "maison", "root": house, "nom": "Maison de Max"}


# ================================================================== boucle
func _process(delta: float) -> void:
	super._process(delta)
	_time += delta
	if phase == "drive":
		_drive_update(delta)
	var listener_pos := car.cam_rig.global_position if phase == "drive" else player.global_position
	var lp := house.to_local(listener_pos)
	var inside_house := house.room_of(lp) != "dehors" and lp.y > 0.2
	_inside_smooth = move_toward(_inside_smooth, 1.0 if inside_house else 0.0, delta * 1.5)
	if phase == "walk":
		if is_instance_valid(rain_out):
			rain_out.volume_db = lerpf(-6.0, -30.0, _inside_smooth)
			rain_in.volume_db = lerpf(-40.0, -10.0, _inside_smooth)
		if is_instance_valid(drone) and not blackout:
			drone.volume_db = lerpf(-60.0, -22.0, _inside_smooth)
		Sound.muffle_music(lerpf(700.0, 18000.0, _inside_smooth))
		rain_fx.global_position = player.global_position + Vector3(0, 10.0, 0)
		_update_feed()
	else:
		rain_fx.global_position = car.global_transform * Vector3(0, 10.0, -14.0)
	for l in house.room_lights:
		if l.has_meta("candle"):
			l.light_energy = 0.22 + randf() * 0.08
	_lightning_cd -= delta
	if _lightning_cd <= 0.0:
		_lightning_cd = randf_range(16.0, 38.0)
		_strike()


func _drive_update(delta: float) -> void:
	if not arrived:
		var remaining := car_path_len - car_dist
		var turn_at := car_path_len - 48.0
		var target := CRUISE
		if car_dist > turn_at - 110.0:
			target = lerpf(CRUISE, 4.5, clampf((car_dist - (turn_at - 110.0)) / 110.0, 0.0, 1.0))
		if car_dist > turn_at:
			target = 4.0
		target = minf(target, sqrt(2.0 * 1.6 * maxf(remaining, 0.0)))
		car.speed = lerpf(car.speed, target, 1.0 - exp(-1.2 * delta))
		car.speed = minf(car.speed, sqrt(2.0 * 1.6 * maxf(remaining, 0.0)) + 0.05)
		car_dist = minf(car_dist + car.speed * delta, car_path_len)
		_place_car(delta)
		if remaining < 0.05:
			_arrive()
		if not figure_done and car_dist > figure_dist - 150.0 and creature.state == Creature.State.DORMANT:
			_figure_sequence()
		if is_instance_valid(engine):
			engine.pitch_scale = lerpf(0.75, 1.05, car.speed / CRUISE)
	# la musique : étouffée par l'habitacle et les murs, de plus en plus forte en approchant
	Sound.muffle_music(320.0)


func _update_feed() -> void:
	if office_open:
		return
	var room := house.room_of(house.to_local(player.global_position))
	# on garde la caméra en cours tant qu'elle filme la pièce où est Théo (le salon en a deux :
	# sans ça le flux basculait de l'une à l'autre à chaque image)
	if house.feed.source != null and house.cam_rooms.get(house.feed.source, "") == room:
		return
	for c in house.cams:
		if house.cam_rooms[c] == room:
			house.feed.source = c
			house.feed.cam_label = "CAM %02d — %s" % [house.cams.find(c) + 1, room.to_upper()]
			break


func _strike() -> void:
	for k in 2:
		lightning.light_energy = randf_range(1.5, 3.0)
		await wait(randf_range(0.05, 0.1))
		lightning.light_energy = 0.0
		await wait(randf_range(0.06, 0.14))
	await wait(randf_range(1.0, 3.0))
	Sound.play(Sound.variant("thunder", 2), lerpf(-2.0, -12.0, _inside_smooth))
