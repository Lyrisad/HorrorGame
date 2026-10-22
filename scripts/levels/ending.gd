extends Level
## Épilogue — Surface.
## Théo sort par une bouche d'égout au petit matin, dans la forêt. Il croit s'en être sorti.
## Une caméra sur un poteau se tourne vers lui : depuis le début, tout est diffusé en direct.

var pole_cam: SecurityCamera
var revealed := false
var wind: AudioStreamPlayer


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
		"fog_density": 0.022,
		"vfog": true,
		"vfog_density": 0.012,
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
	Game.set_fx("grain", 0.09)
	Game.set_fx("gain", 0.4)
	Game.set_fx("saturation", 0.6)
	Game.set_fx("tint", Color(0.92, 0.96, 1.05))
	Sound.set_reverb(0.2, 0.05, 0.8)
	Game.set_clock(5, 47, 12, 15)

	Nature.ground(self, 400.0, "brown_mud_leaves_01", 3.0, Vector3(0, -0.01, -20), Color(0.6, 0.6, 0.55))
	Nature.scatter_forest(self, Rect2(-120, -150, 240, 260), 1100, func(p: Vector3) -> bool:
		return (absf(p.x) < 9.0 and p.z > -46.0 and p.z < 8.0) or absf(p.z + 52.0) < 6.0, 33)
	# bouche d'égout ouverte
	B.model(self, "water_manhole_cover", Vector3(0.9, 0.0, 0.6), 30.0, {"width": 0.8})
	var hole := B.cylinder(self, 0.36, 0.36, 0.02, Vector3(0, 0.005, 0), B.color_mat(Color(0, 0, 0), 1.0), false, 20)
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# route au loin
	var asphalt := B.mat("asphalt_02", 4.0, {"color": Color(0.5, 0.5, 0.5), "roughness": 0.6})
	B.box(self, Vector3(300, 0.04, 7.0), Vector3(0, 0.0, -52.0), asphalt, false)
	B.box(self, Vector3(300, 0.045, 0.12), Vector3(0, 0.0, -52.0), B.color_mat(Color(0.8, 0.8, 0.75), 0.5), false)
	# poteau avec caméra et lampadaire au sodium
	var pole_pos := Vector3(3.5, 0, -47.5)
	B.cylinder(self, 0.11, 0.14, 7.5, pole_pos + Vector3(0, 3.75, 0), B.mat("bark_willow", 1.0, {"color": Color(0.35, 0.3, 0.25)}), true, 10)
	B.box(self, Vector3(0.08, 0.08, 1.6), pole_pos + Vector3(0, 7.0, 0.6), B.color_mat(Color(0.25, 0.25, 0.25), 0.5, 0.8), false)
	B.box(self, Vector3(0.3, 0.1, 0.5), pole_pos + Vector3(0, 6.95, 1.35), B.color_mat(Color(0.2, 0.2, 0.2), 0.5, 0.8), false)
	var sodium := B.spot(self, pole_pos + Vector3(0, 6.85, 1.35), pole_pos + Vector3(0, 0, 4.0), Color(1.0, 0.62, 0.3), 3.0, 18.0, 55.0, true)
	sodium.light_volumetric_fog_energy = 2.0
	# caméra vissée sur la face du poteau tournée vers le chemin (côté bouche d'égout),
	# support tenu par deux colliers d'acier ; au début elle surveille la route, puis se tourne vers Théo
	var mount_y := 4.6
	var r := lerpf(0.14, 0.11, mount_y / 7.5)  # rayon du poteau (conique) à cette hauteur
	var steel := B.color_mat(Color(0.22, 0.22, 0.23), 0.45, 0.85)
	for dy in [-0.075, -0.01]:
		B.cylinder(self, r + 0.008, r + 0.008, 0.022, pole_pos + Vector3(0, mount_y + dy, 0), steel, false, 16)
	var face := Vector3(0, 0, 1)
	var watch_path := (Vector3(0, 1.0, -30.0) - (pole_pos + Vector3(0, mount_y, r))).normalized()
	pole_cam = SecurityCamera.create(self, pole_pos + Vector3(0, mount_y, r) + face * SecurityCamera.ARM, watch_path)
	pole_cam.attach_wall(pole_pos + Vector3(0, mount_y, r), face)
	pole_cam.pivot.global_basis = Basis.looking_at(Vector3(-1.0, -0.15, -0.35).normalized(), Vector3.UP)

	player = spawn_player(Vector3(0, 0, 0.9), 0.0)
	player.has_flashlight = true
	pole_cam.target = player
	add_trigger(Vector3(0.0, 0, -36.0), 10.0, _reveal)
	_play()
	# test : --freecam=x,y,z --freelook=x,y,z → caméra libre (inspection d'un détail)
	if Game.args.has("freecam"):
		var fc := Camera3D.new()
		fc.fov = float(Game.args.get("freefov", 50.0))
		add_child(fc)
		var a3 := str(Game.args["freecam"]).split(",")
		var b3 := str(Game.args.get("freelook", "0,0,0")).split(",")
		fc.look_at_from_position(Vector3(float(a3[0]), float(a3[1]), float(a3[2])), Vector3(float(b3[0]), float(b3[1]), float(b3[2])))
		fc.current = true


func _play() -> void:
	Game.hud.show_hud(true)
	Game.hud.set_battery(1)
	Game.ui.fade_rect.color = Color(1, 1, 1, 1)
	wind = Sound.loop("wind_loop", -10.0)
	var tw := create_tween()
	tw.tween_property(Game.ui.fade_rect, "color:a", 0.0, 2.5)
	await tw.finished
	Game.ui.fade_rect.color = Color(0, 0, 0, 0)
	Game.hud.say("J'suis sorti... J'suis sorti !", 3.0)
	await wait(3.5)
	Game.hud.say("Une route. Il faut que je trouve quelqu'un.", 3.0)
	Game.hud.objective("Rejoindre la route")


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
	Game.hud.live_overlay(true, 2341, "")
	Sound.play("stinger_soft", -4.0)
	var viewers := 2341
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
		{"text": "Animations : CMU Motion Capture Database  ·  Sons : générés par code  ·  Moteur : Godot", "style": "small"},
	], 1.2, 4.0, 1.5)
	Game.quit_to_menu()


func get_surface(_pos: Vector3) -> String:
	return "grass"
