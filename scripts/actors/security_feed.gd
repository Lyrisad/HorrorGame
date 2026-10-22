class_name SecurityFeed
extends Node
## Retransmission en direct d'une caméra de surveillance (SubViewport → texture d'écran).
## Les écrans sont sur le calque 3 (valeur 4) pour ne pas se filmer eux-mêmes.

const SCREEN_LAYER := 4

var viewport: SubViewport
var cam: Camera3D
var source: SecurityCamera
var overlay: Label
var cam_label := "CAM 01"
var active := true
var fps := 15.0
var _screens: Array[ShaderMaterial] = []
var _acc := 0.0
var _env_sync := 0.0


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(480, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.audio_listener_enable_3d = false
	add_child(viewport)
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.near = 0.05
	cam.far = 60.0
	cam.cull_mask = 1 | 2
	viewport.add_child(cam)
	overlay = Label.new()
	var ls := LabelSettings.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "Courier New", "Monospace"])
	f.font_weight = 700
	ls.font = f
	ls.font_size = 18
	ls.font_color = Color(1, 1, 1, 0.9)
	ls.outline_size = 3
	ls.outline_color = Color(0, 0, 0)
	overlay.label_settings = ls
	overlay.position = Vector2(12, 10)
	viewport.add_child(overlay)


func set_active(on: bool) -> void:
	active = on


func _process(delta: float) -> void:
	if not active:
		return
	# environnement allégé pour la caméra (pas d'éclairage global ni de brouillard volumétrique),
	# recopié régulièrement depuis celui du niveau (coupure de courant, exposition...)
	_env_sync -= delta
	if _env_sync <= 0.0 and Game.level != null and Game.level.get("env") != null:
		_env_sync = 1.5
		var e := (Game.level.env as Environment).duplicate() as Environment
		e.sdfgi_enabled = false
		e.volumetric_fog_enabled = false
		e.ssao_enabled = false
		e.ssil_enabled = false
		e.ssr_enabled = false
		cam.environment = e
	# une vraie caméra de surveillance saccade (et ça coûte bien moins cher)
	_acc += delta
	if _acc < 1.0 / fps:
		return
	_acc = 0.0
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if source != null and is_instance_valid(source):
		cam.global_transform = source.view_transform()
	var dot := "●" if fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6 else " "
	overlay.text = "%s  %s REC\n%s" % [cam_label, dot, Game.clock_text()]


## Matériau d'écran affichant ce flux (ou de la neige si `static_mix` = 1).
func screen_material(static_mix := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/security_screen.gdshader")
	m.set_shader_parameter("feed", viewport.get_texture())
	m.set_shader_parameter("static_mix", static_mix)
	_screens.append(m)
	return m


static func static_material(amount := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/security_screen.gdshader")
	m.set_shader_parameter("has_feed", false)
	m.set_shader_parameter("static_mix", amount)
	return m


## Crée un écran (quad face +Z) sur le calque des écrans.
static func screen(parent: Node, size: Vector2, pos: Vector3, rot_deg: Vector3, material: Material) -> MeshInstance3D:
	var q := B.quad(parent, size, pos, material, rot_deg)
	q.layers = SCREEN_LAYER
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return q
