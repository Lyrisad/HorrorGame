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
	"aberration": 0.035,
	"grain": 0.075,
	"gain": 0.0,
	"vignette": 0.85,
	"saturation": 0.8,
	"exposure": 1.0,
	"sharpen": 0.45,
	"tint": Color(1, 1, 1),
}


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
	for k in fx_base.keys():
		post_mat.set_shader_parameter(k, fx_base[k])


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
	post_mat.set_shader_parameter("exposure", float(fx_base.get("exposure", 1.0)) * float(settings["brightness"]))
	post_mat.set_shader_parameter("shake_x", (randf() - 0.5) * 0.004 * _shake)
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
