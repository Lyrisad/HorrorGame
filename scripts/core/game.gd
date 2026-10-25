extends Node
## Chef d'orchestre (autoload "Game") : enchaînement des niveaux, interface, réglages,
## pause, horloge de la caméra, effets de post-traitement et points de reprise.

const LEVELS := {
	"drive": "res://scripts/levels/night.gd",
	"house": "res://scripts/levels/night.gd",
	"sewer": "res://scripts/levels/sewer.gd",
	"ending": "res://scripts/levels/ending.gd",
}
const SAVE_PATH := "user://sauvegarde.cfg"

var hud: HUD
var ui: ScreenUI
var editor: MapEditor
var inventory: InventoryUI
var post: ColorRect
var post_mat: ShaderMaterial
var world: Node = null
var level: Level = null
var level_name := ""
var level_params := {}
var settings := {"sensitivity": 1.0, "volume": 0.8, "music": 1.0, "fullscreen": true, "brightness": 1.0, "mic": true, "mic_sens": 1.0, "mic_device": "Default"}
var unlocked: Array = ["drive"]
var playing := false
var args := {}

# horloge affichée par la caméra
var clock := 0.0
var clock_day := 14
var clock_running := false

# post-traitement : valeurs de base (par niveau) + effets passagers
var fx_base := {}
var _glitch := 0.0
var _flash := 0.0
var _blackout := 0.0
var _blackout_target := 0.0
var _shake := 0.0
var _shot_times: Array = []
var _shot_index := 0
var _level_time := 0.0

const FX_DEFAULTS := {
	"distortion": 0.30,
	"aberration": 0.012,
	"grain": 0.04,
	"gain": 0.0,
	"vignette": 0.85,
	"saturation": 0.8,
	"exposure": 1.0,
	"sharpen": 0.45,
	"tint": Color(1, 1, 1),
	"compress": 1.0,
	"flare": 1.0,
}

# objectif : buée (humidité) et gouttes (éclaboussure), qui s'évaporent / sèchent toutes seules
var _lens_fog := 0.0
var _lens_fog_target := 0.0
var _lens_drops := 0.0
## Lampes qui font des reflets dans l'objectif quand on les regarde : [lumière, force, couleur]
var _flares: Array = []
var _flare_smooth := {}
## Exposition automatique de la caméra : en retard, elle dépasse un peu puis se stabilise (ressort amorti)
var _ae := 1.0
var _ae_vel := 0.0
var _scene_bright := 0.0
var _dark_t := 0.0
## Mise au point : quand ce qui est au centre de l'image saute de loin à tout près (ou l'inverse)
var _focus := 0.0
var _focus_t := -1.0
var _focus_cd := 0.0
var _focus_dist := 5.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_args()
	_setup_input()
	_load_save()

	var post_layer := CanvasLayer.new()
	post_layer.layer = 1
	add_child(post_layer)
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/bodycam.gdshader")
	post_mat.set_shader_parameter("drops_tex", load("res://assets/gen/lens_drops.png"))
	post.material = post_mat
	post_layer.add_child(post)

	hud = HUD.new()
	add_child(hud)
	ui = ScreenUI.new()
	add_child(ui)
	editor = MapEditor.new()
	editor.name = "MapEditor"
	add_child(editor)
	inventory = InventoryUI.new()
	inventory.name = "Inventory"
	add_child(inventory)
	reset_fx()
	_apply_settings()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("shots"):
		for s in str(args["shots"]).split(","):
			_shot_times.append(float(s))


func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("run", [KEY_SHIFT])
	_bind("crouch", [KEY_C])
	_bind("flashlight", [KEY_F])
	_bind("interact", [KEY_E])
	_bind("objective", [KEY_TAB])
	_bind("pause", [KEY_ESCAPE, KEY_P])
	_bind("fullscreen", [KEY_F11])
	_bind("throw", [KEY_G])
	_bind("inventory", [KEY_I])
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("throw", rmb)


## Touches physiques : "W" = touche en haut à gauche, donc Z sur un clavier AZERTY.
func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


# ------------------------------------------------------------------ sauvegarde
func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	unlocked = cfg.get_value("progression", "chapitres", ["drive"])
	for k in settings.keys():
		settings[k] = cfg.get_value("reglages", k, settings[k])


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progression", "chapitres", unlocked)
	for k in settings.keys():
		cfg.set_value("reglages", k, settings[k])
	cfg.save(SAVE_PATH)


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	_apply_settings()
	_save()


func _apply_settings() -> void:
	Sound.set_master_volume(float(settings["volume"]))
	Sound.set_music_volume(float(settings["music"]))
	Sound.set_mic_device(str(settings["mic_device"]))
	Sound.set_mic_enabled(bool(settings["mic"]))
	if args.has("windowed"):
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if settings["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


# ------------------------------------------------------------------ déroulé
func boot(world_node: Node) -> void:
	world = world_node
	if args.has("level"):
		ui.hide_menus()
		var p := {"debug": true}
		if args.has("checkpoint"):
			p["checkpoint"] = args["checkpoint"]
		if args.has("editor") or args.has("edtest") or args.has("edclick") or args.has("edcam") or args.has("edlap"):
			p["editor"] = true
		start_level(str(args["level"]), p)
	else:
		ui.show_main_menu()
		capture_mouse(false)


func new_game() -> void:
	ui.hide_menus()
	capture_mouse(true)
	ui.fade_rect.color.a = 1.0
	Sound.play("ui_beep", -6.0, 1.0, "UI")
	await ui.show_card([
		{"text": "PIÈCE À CONVICTION N° 47", "style": "red"},
		{"text": "Enregistrement caméra-piéton · modèle BWC-7 · n° de série 0417"},
		{"text": "Porteur : Théo Marchand, agent de sécurité"},
		{"text": "Début : 14/11/2026 — 23:41    Durée : 6 h 03 min"},
		{"text": "Le contenu suivant n'a pas été modifié.", "style": "small"},
	], 1.4, 2.6, 1.2)
	start_level("drive")


func start_chapter(chapter: String) -> void:
	ui.hide_menus()
	start_level(chapter)


func start_level(lname: String, params := {}) -> void:
	if editor != null and editor.active:
		editor.close()
	ui.hide_menus()
	ui.show_pause(false)
	get_tree().paused = false
	playing = true
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	hud.reset()
	hud.show_hud(false)
	reset_fx()
	Sound.reset_effects()
	ui.fade_rect.color.a = 1.0
	ui.set_loading(true)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if lname in ["drive", "house"]:
		params = params.duplicate()
		params["start"] = lname
	var lvl: Level = load(LEVELS[lname]).new()
	lvl.name = lname.capitalize()
	lvl.params = params
	level = lvl
	level_name = lname
	level_params = params
	world.add_child(lvl)
	# laisse passer quelques images (compilation des shaders) avant de démarrer le chrono
	await get_tree().process_frame
	await get_tree().process_frame
	# anti micro-freezes : tout ce qui apparaîtra plus tard est dessiné une fois, jeu en pause, derrière un écran noir
	if not params.get("editor", false) and not args.has("noprewarm") and is_instance_valid(lvl):
		ui.set_cover(true)
		get_tree().paused = true
		var t0 := Time.get_ticks_msec()
		await lvl.prewarm()
		if args.has("hitch"):
			print("PRÉCHAUFFAGE %d → %d ms" % [t0, Time.get_ticks_msec()])
		get_tree().paused = false
		ui.set_cover(false)
	ui.set_loading(false)
	_level_time = 0.0
	if not unlocked.has(lname):
		unlocked.append(lname)
		_save()
	capture_mouse(true)
	# lancé depuis « Éditeur de cartes » : on ouvre l'éditeur dès que la carte est prête
	if params.get("editor", false):
		await get_tree().process_frame
		editor.open()


func restart_level() -> void:
	start_level(level_name, level_params)


func retry_from_checkpoint() -> void:
	start_level(level_name, level_params)


func quit_to_menu() -> void:
	if editor != null and editor.active:
		editor.close()
	get_tree().paused = false
	playing = false
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	hud.show_hud(false)
	clock_running = false
	reset_fx()
	Sound.reset_effects()
	ui.show_main_menu()
	capture_mouse(false)


## Mort du joueur : écran de fin d'enregistrement, reprise au dernier point de contrôle.
func player_died(checkpoint_params: Dictionary) -> void:
	level_params = checkpoint_params
	capture_mouse(false)
	hud.show_hud(false)
	ui.show_death("Signal perdu à %s" % clock_text().substr(12))


func pause() -> void:
	if not playing or get_tree().paused:
		return
	get_tree().paused = true
	ui.show_pause(true)
	capture_mouse(false)


func resume() -> void:
	get_tree().paused = false
	ui.show_pause(false)
	capture_mouse(true)


func capture_mouse(on: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if editor != null and editor.active:
		return
	if event.is_action_pressed("fullscreen"):
		set_setting("fullscreen", not settings["fullscreen"])
	if event.is_action_pressed("pause") and playing and not ui.document_open and not ui.death_menu.visible:
		if get_tree().paused:
			resume()
		else:
			pause()
	if event.is_action_pressed("objective") and playing:
		hud.recall_objective()
	if event.is_action_pressed("inventory") and not args.has("shots"):
		inventory.toggle()
	if event is InputEventMouseButton and event.pressed and playing and not get_tree().paused:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not ui.death_menu.visible:
			capture_mouse(true)


func _exit_tree() -> void:
	B.clear_templates()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and playing and not args.has("windowed"):
		pause()


# ------------------------------------------------------------------ horloge
func set_clock(h: int, m: int, s: int, day := 14) -> void:
	clock = h * 3600.0 + m * 60.0 + s
	clock_day = day
	clock_running = true


func clock_text() -> String:
	var t := int(clock)
	var day := clock_day + t / 86400
	t = t % 86400
	return "2026-11-%02d  %02d:%02d:%02d" % [day, t / 3600, (t / 60) % 60, t % 60]


# ------------------------------------------------------------------ post-traitement
func reset_fx() -> void:
	fx_base = FX_DEFAULTS.duplicate()
	_glitch = 0.0
	_flash = 0.0
	_blackout = 0.0
	_blackout_target = 0.0
	_shake = 0.0
	_lens_fog = 0.0
	_lens_fog_target = 0.0
	_lens_drops = 0.0
	_ae = 1.0
	_ae_vel = 0.0
	_scene_bright = 0.0
	_focus = 0.0
	_focus_t = -1.0
	post_mat.set_shader_parameter("rewind", 0.0)
	_flares.clear()
	_flare_smooth.clear()
	for k in fx_base.keys():
		post_mat.set_shader_parameter(k, fx_base[k])
	_push_flares([])


## Lecture rembobinée (après la mort) : l'horloge de la caméra recule à toute vitesse.
func set_rewind(amount: float) -> void:
	post_mat.set_shader_parameter("rewind", amount)


## La mise au point de la caméra cherche une fraction de seconde (quelque chose surgit tout près...).
func focus_hunt(amount := 1.0) -> void:
	if _focus_cd > 0.0:
		return
	_focus_cd = 1.5
	_focus_t = 0.0
	_focus = maxf(_focus, amount)


func _update_camera_auto(delta: float) -> void:
	# --- exposition : ce que la caméra « voit » de lumineux (lampes visibles, mur tout près sous la lampe)
	var bright := _scene_bright
	var p: Player = level.player if level != null else null
	if p != null and p.flashlight_on and p.flashlight.light_energy > 0.5:
		bright += clampf((1.6 - p.aim_raw) / 1.6, 0.0, 1.0) * 1.2
	# noir complet (lampe éteinte, aucune lampe en vue) : au bout d'un moment, la caméra pousse le gain
	if bright < 0.05 and (p == null or not p.flashlight_on):
		_dark_t += delta
	else:
		_dark_t = 0.0
	var target := clampf(1.0 / (1.0 + bright * 0.9), 0.55, 1.0)
	if _dark_t > 1.5:
		target = 1.0 + minf((_dark_t - 1.5) * 0.15, 0.25)
	# ressort un peu mou : elle réagit avec retard et dépasse légèrement avant de se stabiliser
	var k := 9.0
	var damp := 3.2
	_ae_vel += ((target - _ae) * k - _ae_vel * damp) * delta
	_ae += _ae_vel * delta
	post_mat.set_shader_parameter("ae_gain", clampf((_ae - 1.0) * 2.0, 0.0, 0.5))
	# --- mise au point : saut brusque de distance au centre de l'image
	_focus_cd = maxf(0.0, _focus_cd - delta)
	if p != null:
		var d := maxf(p.aim_raw, 0.05)
		var near := minf(d, _focus_dist)
		var far := maxf(d, _focus_dist)
		if near < 1.3 and far / near > 3.0:
			focus_hunt(0.8)
		_focus_dist = lerpf(_focus_dist, d, 1.0 - exp(-3.0 * delta))
	var df := 0.0
	if _focus_t >= 0.0:
		_focus_t += delta
		# flou qui monte vite, revient, ressaute un peu (elle cherche), puis net
		var t := _focus_t
		df = _focus * (smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.12, 0.38, t)) + 0.35 * smoothstep(0.38, 0.46, t) * (1.0 - smoothstep(0.46, 0.65, t)))
		if t > 0.7:
			_focus_t = -1.0
			_focus = 0.0
	post_mat.set_shader_parameter("defocus", df)


## Une lampe visible (avec son luminaire) : quand Théo la regarde, elle fait des reflets dans l'objectif.
func add_flare(light: Light3D, strength := 1.0, size := 1.0) -> void:
	_flares.append([light, strength, size])


## Buée sur l'objectif : monte vers `amount` (0..1) puis se dissipe d'elle-même.
func lens_fog(amount: float) -> void:
	_lens_fog_target = maxf(_lens_fog_target, amount)


## Gouttes d'eau projetées sur la vitre de la caméra (éclaboussure).
func lens_splash(amount := 1.0) -> void:
	_lens_drops = maxf(_lens_drops, amount)


func _update_lens(delta: float) -> void:
	# la buée se forme en 2 s puis s'évapore lentement (≈ 20 s), en commençant par le centre
	if _lens_fog_target > _lens_fog:
		_lens_fog = move_toward(_lens_fog, _lens_fog_target, delta * 0.5)
		if _lens_fog >= _lens_fog_target - 0.01:
			_lens_fog_target = 0.0
	else:
		_lens_fog = maxf(0.0, _lens_fog - delta * 0.045)
	_lens_drops = maxf(0.0, _lens_drops - delta * 0.12)
	post_mat.set_shader_parameter("lens_fog", _lens_fog)
	post_mat.set_shader_parameter("lens_drops", _lens_drops)


func _update_flares(delta: float) -> void:
	_scene_bright = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null or _flares.is_empty() or level == null:
		_push_flares([])
		return
	var vp := get_viewport().get_visible_rect().size
	var cam_pos := cam.global_position
	var cam_fwd := -cam.global_basis.z
	var cands: Array = []
	for f in _flares:
		var l := f[0] as Light3D
		if not is_instance_valid(l) or not l.is_visible_in_tree() or l.light_energy <= 0.02:
			continue
		var p := l.global_position
		var to := p - cam_pos
		var dist := to.length()
		if dist > 28.0 or dist < 0.3 or cam.is_position_behind(p):
			continue
		var facing := cam_fwd.dot(to / dist)
		if facing < 0.55:
			continue
		var uv := cam.unproject_position(p) / vp
		if uv.x < -0.05 or uv.x > 1.05 or uv.y < -0.05 or uv.y > 1.05:
			continue
		var k := float(f[1]) * l.light_energy / (1.0 + dist * dist * 0.06)
		# un spot ne se voit que dans son cône
		if l is SpotLight3D:
			var sp := l as SpotLight3D
			var cone := (-sp.global_basis.z).dot(-to / dist)
			k *= smoothstep(cos(deg_to_rad(sp.spot_angle)), 1.0, cone)
		# plus fort quand la lampe est près du centre de l'image
		k *= smoothstep(0.55, 0.95, facing)
		if k > 0.01:
			cands.append([k, uv, l, float(f[2]), dist])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var space := cam.get_world_3d().direct_space_state
	var out: Array = []
	var seen := {}
	for c in cands:
		if out.size() >= 4:
			break
		var l2 := c[2] as Light3D
		# masquée par un mur ou un objet ?
		var q := PhysicsRayQueryParameters3D.create(cam_pos, l2.global_position - (l2.global_position - cam_pos).normalized() * 0.35, 1)
		if level.player != null:
			q.exclude = [level.player.get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue
		var id := l2.get_instance_id()
		seen[id] = true
		var sm := lerpf(float(_flare_smooth.get(id, 0.0)), float(c[0]), 1.0 - exp(-10.0 * delta))
		_flare_smooth[id] = sm
		out.append([c[1], sm, float(c[3]) * clampf(4.0 / maxf(float(c[4]), 1.0), 0.5, 1.6), l2.light_color])
		_scene_bright += sm
	for id in _flare_smooth.keys():
		if not seen.has(id):
			_flare_smooth.erase(id)
	_push_flares(out)


func _push_flares(list: Array) -> void:
	var src: Array[Vector4] = []
	var col: Array[Vector4] = []
	for i in 4:
		if i < list.size():
			var e: Array = list[i]
			var uv: Vector2 = e[0]
			var c: Color = e[3]
			src.append(Vector4(uv.x, uv.y, minf(float(e[1]), 1.5), float(e[2])))
			col.append(Vector4(c.r, c.g, c.b, 1.0))
		else:
			src.append(Vector4.ZERO)
			col.append(Vector4.ZERO)
	post_mat.set_shader_parameter("flare_src", src)
	post_mat.set_shader_parameter("flare_col", col)


func set_fx(key: String, value: Variant) -> void:
	fx_base[key] = value
	post_mat.set_shader_parameter(key, value)


func tween_fx(key: String, value: float, duration: float) -> void:
	var from: float = fx_base.get(key, 0.0)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: set_fx(key, v), from, value, duration)


func glitch(amount := 0.6, with_sound := true) -> void:
	_glitch = maxf(_glitch, amount)
	if with_sound:
		Sound.play(Sound.variant("glitch", 3), -10.0 + amount * 8.0, 1.0, "UI")


func flash(amount := 1.0) -> void:
	_flash = maxf(_flash, amount)


func shake(amount := 1.0) -> void:
	_shake = maxf(_shake, amount)


func set_blackout(on: bool, instant := false) -> void:
	_blackout_target = 1.0 if on else 0.0
	if instant:
		_blackout = _blackout_target


func shake_amount() -> float:
	return _shake


var _voice_cd := 0.0


## Ta vraie voix (micro) : dans les égouts, parler ou crier fait du bruit que la créature entend.
func _voice_noise(delta: float) -> void:
	_voice_cd -= delta
	if Sound.mic_voice < 0.12 or _voice_cd > 0.0 or get_tree().paused or level == null:
		return
	if not level.has_method("on_noise") or level.player == null or not level.player.control_enabled:
		return
	_voice_cd = 0.35
	# chuchoter : 3 m · parler : ~8 m · crier : jusqu'à 24 m
	level.on_noise(level.player.global_position, lerpf(3.0, 24.0, Sound.mic_voice))


func _process(delta: float) -> void:
	# test : --hitch → signale chaque image trop longue (micro-freeze)
	if args.has("hitch"):
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		if delta > 0.04:
			var vp := get_viewport().get_viewport_rid()
			print("HITCH %4.0f ms  t=%5.1f  (%d ms)  process=%.0f physique=%.0f rendu_cpu=%.0f rendu_gpu=%.0f prépa=%.0f" % [delta * 1000.0, _level_time, Time.get_ticks_msec(),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp), RenderingServer.get_frame_setup_time_cpu()])
	_voice_noise(delta)
	# (les captures de test continuent pendant l'inventaire, qui met le jeu en pause)
	if not get_tree().paused or (inventory != null and inventory.is_open):
		_level_time += delta
	if not get_tree().paused:
		if clock_running and playing:
			clock += delta
			hud.set_clock(clock_text())
		_glitch = maxf(0.0, _glitch - delta * 1.6)
		_flash = maxf(0.0, _flash - delta * 3.0)
		_shake = maxf(0.0, _shake - delta * 1.5)
	_blackout = move_toward(_blackout, _blackout_target, delta * 4.0)
	post_mat.set_shader_parameter("glitch", _glitch)
	post_mat.set_shader_parameter("flash", _flash)
	post_mat.set_shader_parameter("blackout", _blackout)
	post_mat.set_shader_parameter("exposure", float(fx_base.get("exposure", 1.0)) * float(settings["brightness"]) * _ae)
	post_mat.set_shader_parameter("shake_x", (randf() - 0.5) * 0.004 * _shake)
	if not get_tree().paused:
		_update_lens(delta)
		_update_flares(delta)
		_update_camera_auto(delta)
	_debug_screenshots()
	if args.has("timeout") and Time.get_ticks_msec() / 1000.0 > float(args["timeout"]):
		print("TIMEOUT")
		get_tree().quit()


## Captures d'écran automatiques (tests) : --shots=3,8 --shot=chemin_prefixe
func _debug_screenshots() -> void:
	if _shot_index >= _shot_times.size():
		return
	if _level_time >= float(_shot_times[_shot_index]):
		var img := get_viewport().get_texture().get_image()
		var path := "%s_%d.png" % [str(args.get("shot", "user://shot")), _shot_index]
		img.save_png(path)
		print("CAPTURE ", path, "  fps=", Engine.get_frames_per_second())
		_shot_index += 1
		if _shot_index >= _shot_times.size() and args.has("quit"):
			get_tree().quit()
