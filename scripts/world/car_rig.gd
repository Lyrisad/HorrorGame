class_name CarRig
extends Node3D
## La voiture de Théo (Toyota Corolla E180, Sketchfab CC-BY) vue de l'intérieur :
## caméra-piéton au torse du conducteur, volant qui tourne, téléphone qui s'allume
## et que Théo lève pour lire ses messages, autoradio, phares, pluie sur le pare-brise.
## Convention : la voiture regarde vers -Z (le modèle d'origine regarde vers +Z).

const SEAT := Vector3(-0.37, 1.04, -0.02)  ## caméra-piéton (torse du conducteur), repère voiture
const WHEEL_CENTER := Vector3(-0.36, 0.83, -0.57)

var model: Node3D
var wheel_pivot: Node3D
var cam_rig: Node3D
var cam: Camera3D
var look_yaw := 0.0
var look_pitch := -0.12
var _cy := 0.0
var _cp := -0.12
var steer := 0.0
var engine_on := true
var speed := 0.0
var headlights: Array[SpotLight3D] = []
var phone: Node3D
var phone_ui: PhoneUI
var phone_mat: StandardMaterial3D
var phone_light: OmniLight3D
var radio_label: Label3D
var windshield_mat: ShaderMaterial
var wipers: Array[Node3D] = []
var interior_enabled := true
var _wiper_snd: AudioStreamPlayer3D = null
var _wipe_prev := 0.0
var _bump := 0.0
var _phone_raise := 0.0
var _phone_target := 0.0
var _time := 0.0
var _clock_t := 0.0


func _ready() -> void:
	model = B.model(self, "sf:corolla", Vector3.ZERO, 180.0, {"center": false, "remove": ["Cube_002", "Cube_003"]})
	_paint(Color(0.16, 0.18, 0.2))
	_setup_wheel()
	_setup_lights()
	_setup_windshield()
	_setup_phone()
	_setup_radio()
	cam_rig = Node3D.new()
	cam_rig.top_level = true
	add_child(cam_rig)
	cam = Camera3D.new()
	cam.fov = 78.0
	cam.near = 0.02
	cam.far = 400.0
	cam_rig.add_child(cam)
	# test : --caryaw=deg --carpitch=deg
	if Game.args.has("caryaw"):
		look_yaw = deg_to_rad(float(Game.args["caryaw"]))
		_cy = look_yaw
	if Game.args.has("carpitch"):
		look_pitch = deg_to_rad(float(Game.args["carpitch"]))
		_cp = look_pitch
	# collision simple pour quand on est dehors
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 1.4, 4.3)
	cs.shape = bs
	cs.position = Vector3(0, 0.75, 0)
	sb.add_child(cs)
	add_child(sb)


## Couleur de carrosserie (matériau "main_paint").
func _paint(c: Color) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s)
			if mat is StandardMaterial3D and mat.resource_name.begins_with("main_paint"):
				var nm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				nm.albedo_color = c
				nm.metallic = 0.7
				nm.roughness = 0.3
				nm.clearcoat_enabled = true
				nm.clearcoat = 1.0
				nm.clearcoat_roughness = 0.08
				m.set_surface_override_material(s, nm)


func set_paint(c: Color) -> void:
	_paint(c)


func _setup_wheel() -> void:
	var steering := model.find_child("corolla_e180_steering*", true, false) as Node3D
	if steering == null:
		return
	wheel_pivot = Node3D.new()
	add_child(wheel_pivot)
	wheel_pivot.position = WHEEL_CENTER
	# axe de la colonne de direction : vers l'avant et vers le bas
	wheel_pivot.basis = Basis.looking_at(Vector3(0, -0.45, -1).normalized(), Vector3.UP)
	steering.reparent(wheel_pivot, true)


func _setup_lights() -> void:
	for side in [-1.0, 1.0]:
		var hl := SpotLight3D.new()
		hl.light_color = Color(1.0, 0.95, 0.86)
		hl.light_energy = 60.0
		hl.spot_range = 90.0
		hl.spot_angle = 32.0
		hl.spot_angle_attenuation = 1.1
		hl.spot_attenuation = 0.5
		hl.shadow_enabled = side < 0.0
		hl.light_volumetric_fog_energy = 0.5
		hl.light_specular = 0.6
		add_child(hl)
		# devant le pare-chocs, sinon le boîtier du phare projette son ombre
		hl.position = Vector3(0.6 * side, 0.7, -2.32)
		hl.rotation_degrees = Vector3(-4, 0, 0)
		headlights.append(hl)
	for side in [-1.0, 1.0]:
		var tl := B.omni(self, Vector3(0.65 * side, 0.85, 2.25), Color(1.0, 0.05, 0.03), 0.35, 3.0)
		tl.light_volumetric_fog_energy = 1.5
	var dash := B.omni(self, Vector3(-0.3, 0.98, -0.62), Color(0.4, 0.75, 1.0), 0.05, 0.9)
	dash.light_volumetric_fog_energy = 0.0
	dash.light_specular = 0.0


func set_headlights(on: bool) -> void:
	for h in headlights:
		h.visible = on


## Repère du pare-brise du modèle (mesuré avec tools/car_windshield.gd) : origine au bas du vitrage,
## au centre ; WS_UP monte le long de la vitre (22° sur l'horizontale) ; WS_OUT sort de la voiture.
const WS_ORIGIN := Vector3(0, 0.918, -1.243)
const WS_UP := Vector3(0, 0.381, 0.925)
const WS_OUT := Vector3(0, 0.925, -0.381)
## Balais (conduite à gauche) : pivot (u, v) dans le repère du pare-brise, longueur, angle de repos
## (couché vers la droite) et angle en haut de course (dressé vers le montant gauche), en degrés.
const WIPERS := [
	{"pivot": Vector2(-0.44, -0.035), "len": 0.6, "rest": 4.0, "top": 106.0},
	{"pivot": Vector2(0.17, -0.035), "len": 0.5, "rest": 4.0, "top": 95.0},
]

var _ws_tris := PackedVector3Array()
var _wiper_tips: Array[PackedFloat32Array] = []  ## hauteur de la vitre sous le bout du balai, par angle
var _wiper_piv_h: Array[float] = []
var _wipe_idle := 60.0


func _setup_windshield() -> void:
	windshield_mat = ShaderMaterial.new()
	windshield_mat.shader = load("res://shaders/windshield.gdshader")
	var glass := model.find_children("corolla_e180_windows*", "MeshInstance3D", true, false)
	if glass.is_empty():
		return
	# la pluie épouse la face extérieure du vrai pare-brise (1,5 mm au-dessus)
	var gm := glass[0] as MeshInstance3D
	var xf := B._relative_xform(self, gm)
	var arr := gm.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(WS_OUT)
	for i in range(0, idx.size(), 3):
		var a := xf * v[idx[i]]
		var b := xf * v[idx[i + 1]]
		var c := xf * v[idx[i + 2]]
		# face extérieure du vitrage avant (le verre a deux faces à 4 mm l'une de l'autre)
		if (a + b + c).z / 3.0 > -0.3 or (b - a).cross(c - a).normalized().dot(WS_OUT) > -0.8:
			continue
		for p in [a, b, c]:
			var q: Vector3 = p + WS_OUT * 0.0015
			_ws_tris.append(q)
			st.set_uv(Vector2((q - WS_ORIGIN).x, (q - WS_ORIGIN).dot(WS_UP)))
			st.add_vertex(q)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = windshield_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_setup_wipers()


func _setup_wipers() -> void:
	var arm_mat := B.color_mat(Color(0.025, 0.025, 0.028), 0.55, 0.4)
	var rubber := B.color_mat(Color(0.015, 0.015, 0.015), 0.8)
	for w in WIPERS:
		var piv: Vector2 = w["pivot"]
		var length: float = w["len"]
		var root := Node3D.new()
		add_child(root)
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(length, 0.011, 0.009)
		arm.mesh = am
		arm.material_override = arm_mat
		arm.position = Vector3(length * 0.5, 0, 0)
		root.add_child(arm)
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(length * 0.86, 0.016, 0.009)
		blade.mesh = bm
		blade.material_override = rubber
		blade.position = Vector3(length * 0.55, -0.012, 0)
		root.add_child(blade)
		B.cylinder(root, 0.014, 0.016, 0.03, Vector3(0, -0.006, 0), arm_mat, false, 12)
		for n in [arm, blade]:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wipers.append(root)
		# hauteur du verre sous le bout du balai pour chaque angle (le pare-brise est bombé)
		var tips := PackedFloat32Array()
		var last := 0.0
		for k in 41:
			var ang := deg_to_rad(lerpf(w["rest"], w["top"], k / 40.0))
			var h: Variant = _glass_height(piv + Vector2(cos(ang), sin(ang)) * length)
			last = h if h != null else last
			tips.append(last)
		_wiper_tips.append(tips)
		var hp: Variant = _glass_height(piv + Vector2(0.0, 0.06))
		_wiper_piv_h.append(hp if hp != null else 0.0)
	windshield_mat.set_shader_parameter("piv_l", Vector3(WIPERS[0]["pivot"].x, WIPERS[0]["pivot"].y, WIPERS[0]["len"]))
	windshield_mat.set_shader_parameter("ang_l", Vector2(deg_to_rad(WIPERS[0]["rest"]), deg_to_rad(WIPERS[0]["top"])))
	windshield_mat.set_shader_parameter("piv_r", Vector3(WIPERS[1]["pivot"].x, WIPERS[1]["pivot"].y, WIPERS[1]["len"]))
	windshield_mat.set_shader_parameter("ang_r", Vector2(deg_to_rad(WIPERS[1]["rest"]), deg_to_rad(WIPERS[1]["top"])))
	windshield_mat.set_shader_parameter("stroke", WIPE_STROKE)
	windshield_mat.set_shader_parameter("cycle", WIPE_CYCLE)
	_place_wipers(0.0)


## Distance (le long de WS_OUT) entre le plan de référence et la vitre au point (u, v), ou null hors vitre.
func _glass_height(uv: Vector2) -> Variant:
	var p := WS_ORIGIN + Vector3(uv.x, 0, 0) + WS_UP * uv.y
	var from := p + WS_OUT * 0.3
	for i in range(0, _ws_tris.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, -WS_OUT, _ws_tris[i], _ws_tris[i + 1], _ws_tris[i + 2])
		if hit != null:
			return ((hit as Vector3) - p).dot(WS_OUT)
	return null


## b = 0 : balais au repos en bas du pare-brise ; 1 : en haut de course.
func _place_wipers(b: float) -> void:
	for i in wipers.size():
		var w: Dictionary = WIPERS[i]
		var piv: Vector2 = w["pivot"]
		var ang := deg_to_rad(lerpf(w["rest"], w["top"], b))
		var tips: PackedFloat32Array = _wiper_tips[i]
		var f := b * 40.0
		var h_tip := lerpf(tips[int(f)], tips[mini(int(f) + 1, 40)], f - int(f))
		var tip_uv := piv + Vector2(cos(ang), sin(ang)) * float(w["len"])
		var p0 := WS_ORIGIN + Vector3(piv.x, 0, 0) + WS_UP * piv.y + WS_OUT * (_wiper_piv_h[i] + 0.02)
		var p1 := WS_ORIGIN + Vector3(tip_uv.x, 0, 0) + WS_UP * tip_uv.y + WS_OUT * (h_tip + 0.014)
		var x := (p1 - p0).normalized()
		var z := x.cross(WS_OUT).normalized()
		wipers[i].transform = Transform3D(Basis(x, z.cross(x), z), p0)


func _setup_phone() -> void:
	phone_ui = PhoneUI.new()
	add_child(phone_ui)
	phone = Node3D.new()
	add_child(phone)
	# coque à bords arrondis (capsule écrasée) + verre
	var shell := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.0765, 0.1605, 0.0085)
	shell.mesh = bm
	shell.material_override = B.color_mat(Color(0.03, 0.03, 0.035), 0.3, 0.6)
	phone.add_child(shell)
	for sx in [-1.0, 1.0]:
		var edge := B.cylinder(phone, 0.0043, 0.0043, 0.1605, Vector3(sx * 0.0382, 0, 0), B.color_mat(Color(0.25, 0.25, 0.27), 0.25, 0.9), false, 10)
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	B.box(phone, Vector3(0.022, 0.022, 0.003), Vector3(0.022, 0.06, -0.0055), B.color_mat(Color(0.05, 0.05, 0.06), 0.2, 0.5), false)
	# écran : seule l'émission compte (comme un vrai écran), verre peu réfléchissant
	phone_mat = StandardMaterial3D.new()
	phone_mat.albedo_color = Color(0.015, 0.015, 0.018)
	phone_mat.emission_enabled = true
	phone_mat.emission_texture = phone_ui.get_texture()
	phone_mat.emission_energy_multiplier = 0.15
	phone_mat.roughness = 0.5
	phone_mat.metallic_specular = 0.15
	var scr := B.quad(phone, Vector2(0.0725, 0.1525), Vector3(0, 0, 0.0044), phone_mat)
	scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	phone_light = B.omni(phone, Vector3(0, 0, 0.12), Color(0.6, 0.7, 1.0), 0.0, 1.0)
	phone_light.light_volumetric_fog_energy = 0.0
	phone_light.light_specular = 0.0
	_update_phone_pose(0.0)


## Position du téléphone : sur son support (0) ou tenu devant la caméra-piéton (1),
## un peu bas, pour qu'on lise l'écran comme Théo le lit.
func _update_phone_pose(t: float) -> void:
	var mount := global_transform * Transform3D(Basis.from_euler(Vector3(deg_to_rad(-15), deg_to_rad(-25), 0)), Vector3(0.05, 0.98, -0.62))
	if cam_rig == null:
		phone.global_transform = mount
		return
	var wobble := Vector3(sin(_time * 1.3) * 0.004, sin(_time * 1.7) * 0.003, 0)
	var held := cam_rig.global_transform * Transform3D(Basis.from_euler(Vector3(deg_to_rad(7), deg_to_rad(-3), deg_to_rad(2) + sin(_time * 0.9) * 0.01)), Vector3(0.006, -0.032, -0.18) + wobble)
	var k := smoothstep(0.0, 1.0, t)
	# arc de mouvement : le téléphone passe par en dessous du volant
	var xf := mount.interpolate_with(held, k)
	xf.origin += cam_rig.global_basis.y * -0.08 * sin(k * PI)
	phone.global_transform = xf


func _setup_radio() -> void:
	# on affiche l'autoradio directement sur l'écran du tableau de bord (matériau "screen")
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s)
			if mat != null and mat.resource_name == "screen":
				var vp := SubViewport.new()
				vp.size = Vector2i(512, 288)
				vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(vp)
				var bg := ColorRect.new()
				bg.color = Color(0.01, 0.02, 0.04)
				bg.size = Vector2(512, 288)
				vp.add_child(bg)
				var font := SystemFont.new()
				font.font_names = PackedStringArray(["Segoe UI", "Arial"])
				font.font_weight = 600
				for line in [["FM 98.4", 70, 40], ["RADIO NUIT", 44, 130], ["♪  Nocturne — lecture en cours", 26, 200]]:
					var l := Label.new()
					l.text = line[0]
					l.position = Vector2(30, line[2])
					l.add_theme_font_override("font", font)
					l.add_theme_font_size_override("font_size", line[1])
					l.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
					vp.add_child(l)
				var sm := StandardMaterial3D.new()
				sm.albedo_texture = vp.get_texture()
				sm.emission_enabled = true
				sm.emission_texture = vp.get_texture()
				sm.emission_energy_multiplier = 0.8
				sm.roughness = 0.15
				# les UV de l'écran du modèle sont retournés
				sm.uv1_scale = Vector3(1, -1, 1)
				sm.uv1_offset = Vector3(0, 1, 0)
				m.set_surface_override_material(s, sm)
				return
	radio_label = Label3D.new()
	radio_label.text = "FM 98.4   RADIO NUIT"
	radio_label.font_size = 20
	radio_label.pixel_size = 0.0007
	radio_label.modulate = Color(0.55, 0.85, 1.0)
	radio_label.shaded = false
	radio_label.outline_size = 0
	radio_label.no_depth_test = false
	add_child(radio_label)
	radio_label.position = Vector3(-0.02, 0.91, -0.66)
	radio_label.rotation_degrees = Vector3(-20, 0, 0)


## Nouveau message : le téléphone vibre sur son support, l'écran s'allume
## et la notification s'ajoute en haut de l'écran verrouillé.
func message(sender: String, text: String) -> void:
	phone_ui.show_screen("lock")
	phone_ui.notify(sender, text)
	Sound.play_at("phone_buzz", phone.global_position, -2.0, 1.0, 2.0, 10.0)
	Sound.play_at("phone_ping", phone.global_position, -8.0, 1.0, 2.0, 10.0)
	_screen_on(true)


## Théo prend le téléphone pour lire / répondre (true), ou le repose (false).
func raise_phone(on: bool) -> void:
	_phone_target = 1.0 if on else 0.0
	if on:
		_screen_on(true)
	else:
		await get_tree().create_timer(1.0, false).timeout
		if _phone_target == 0.0:
			phone_ui.show_screen("lock")
			await get_tree().create_timer(3.0, false).timeout
			if _phone_target == 0.0:
				_screen_on(false)


func _screen_on(on: bool) -> void:
	var tw := create_tween().set_parallel()
	tw.tween_property(phone_mat, "emission_energy_multiplier", 0.85 if on else 0.12, 0.3 if on else 1.5)
	tw.tween_property(phone_light, "light_energy", 0.25 if on else 0.0, 0.3 if on else 1.5)


func _unhandled_input(event: InputEvent) -> void:
	if not cam.current or Game.args.has("shots"):
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := 0.0021 * float(Game.settings.get("sensitivity", 1.0))
		look_yaw = clampf(look_yaw - event.relative.x * sens, deg_to_rad(-150), deg_to_rad(150))
		look_pitch = clampf(look_pitch - event.relative.y * sens, deg_to_rad(-60), deg_to_rad(40))


func _process(delta: float) -> void:
	# volant
	if wheel_pivot != null:
		wheel_pivot.rotation.z = lerpf(wheel_pivot.rotation.z, clampf(steer * 2.2, -2.0, 2.0), 1.0 - exp(-6.0 * delta))
	# essuie-glaces intermittents : un aller-retour toutes les 3,2 s, calé sur le son
	_update_wipers(delta)
	_time += delta
	# heure du téléphone
	_clock_t -= delta
	if _clock_t <= 0.0:
		_clock_t = 1.0
		phone_ui.set_time(Game.clock_text().substr(12, 5))
	# caméra-piéton
	if cam.current:
		_cy = lerp_angle(_cy, look_yaw, 1.0 - exp(-14.0 * delta))
		_cp = lerpf(_cp, look_pitch, 1.0 - exp(-14.0 * delta))
		_bump += delta * speed
		var k := clampf(speed / 15.0, 0.0, 1.0)
		var vib := Vector3(sin(_bump * 3.1) * 0.002, sin(_bump * 4.7) * 0.0025 + sin(_bump * 0.9) * 0.003, 0) * k
		if engine_on:
			vib += Vector3(0, sin(Time.get_ticks_msec() * 0.09) * 0.0006, 0)
		cam_rig.global_transform = global_transform * Transform3D(Basis.from_euler(Vector3(_cp, _cy, sin(_bump * 0.7) * 0.004 * k)), SEAT + vib)
	# téléphone (après la caméra : tenu devant elle)
	_phone_raise = move_toward(_phone_raise, _phone_target, delta * 1.6)
	_update_phone_pose(_phone_raise)


const WIPE_STROKE := 0.6
const WIPE_CYCLE := 3.2


func _update_wipers(_delta: float) -> void:
	var running := speed > 0.5
	if running and _wiper_snd == null:
		_wiper_snd = Sound.loop_at("wiper_cycle_loop", self, -9.0, 2.0, 8.0)
		_wiper_snd.position = Vector3(-0.2, 1.0, -1.1)
		_wiper_snd.play(0.0)
		_wipe_prev = 0.0
	var t := WIPE_CYCLE
	if _wiper_snd != null and is_instance_valid(_wiper_snd):
		t = fmod(_wiper_snd.get_playback_position() + AudioServer.get_time_since_last_mix(), WIPE_CYCLE)
		if t < _wipe_prev:
			# arrivée : on laisse finir le cycle en cours puis on coupe
			if not running:
				_wiper_snd.queue_free()
				_wiper_snd = null
				t = WIPE_CYCLE
		_wipe_prev = t
	# position de la balaie : 0 = au repos en bas, 1 = en haut de course (mouvement sinusoïdal)
	var b := 0.0
	if t < WIPE_STROKE:
		b = (1.0 - cos(PI * t / WIPE_STROKE)) * 0.5
	elif t < 2.0 * WIPE_STROKE:
		b = (1.0 + cos(PI * (t - WIPE_STROKE) / WIPE_STROKE)) * 0.5
	_place_wipers(b)
	# temps écoulé dans le cycle (au-delà du cycle quand les essuie-glaces sont arrêtés)
	if _wiper_snd != null:
		_wipe_idle = 0.0
	else:
		_wipe_idle += _delta
		t = WIPE_CYCLE + _wipe_idle
	windshield_mat.set_shader_parameter("wipe_t", t)


func seat_transform() -> Transform3D:
	return cam_rig.global_transform
