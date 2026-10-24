class_name Player
extends CharacterBody3D
## Joueur vu à travers une caméra-piéton fixée sur le torse :
## caméra légèrement en retard sur la souris, balancement à chaque pas,
## lampe torche tenue à la main (qui suit avec son propre retard),
## endurance limitée, bruit des pas transmis au niveau (la créature écoute).

const WALK_SPEED := 1.95
const RUN_SPEED := 4.7
const CROUCH_SPEED := 1.15
const STAND_HEIGHT := 1.38
const CROUCH_HEIGHT := 0.86
const GRAVITY := 18.0
const MOUSE_SENS := 0.0021

var control_enabled := true
var look_enabled := true
var has_flashlight := true
var flashlight_on := false
var crouching := false
var running := false
var moving := false
var stamina := 1.0
var exhausted := false
var noise_mul := 1.0

var yaw := 0.0
var pitch := 0.0
var _cam_yaw := 0.0
var _cam_pitch := 0.0
var _hand_basis := Basis()
var _height := STAND_HEIGHT
var _step_accum := 0.0
var _bob := 0.0
var _bob_amp := 0.0
var _breath_t := 0.0
var _turn_speed := 0.0
var _hold := 0.0
var _focus: Interactable = null
var _flicker_t := 0.0
var _flash_energy := 3.0
var _lamp_off := false  ## coupure franche (faux contact violent)
var _dim_t := 0.0  ## baisse de tension : la lampe faiblit puis revient
var _dim_level := 1.0
var _body_yaw := 0.0
var _aim_dist := 6.0  ## distance où le faisceau croise le centre de l'image
var _tremble := 0.0  ## mains qui tremblent après une poursuite (secondes restantes)
var _tremble_t := 0.0
var _scared := false
var _glitch_cd := 90.0  ## faux contact de la lampe, de temps en temps

var head: Node3D
var cam: Camera3D
var hand: Node3D
var flashlight: SpotLight3D
var flash_fill: OmniLight3D
var ray: RayCast3D
var aim_ray: RayCast3D
var body: Actor
var breath_player: AudioStreamPlayer
var heart_player: AudioStreamPlayer
## Décalage de caméra piloté par les cinématiques (chute, traîné au sol...).
var cine_offset := Transform3D.IDENTITY
var cine_weight := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.75
	shape.shape = capsule
	shape.position.y = 0.875
	add_child(shape)

	head = Node3D.new()
	head.top_level = true
	add_child(head)
	cam = Camera3D.new()
	cam.fov = 78.0
	cam.near = 0.04
	cam.far = 250.0
	cam.cull_mask = 0xFFFFF & ~2  # le corps du joueur (calque 2) n'est vu que par les caméras de surveillance
	head.add_child(cam)
	cam.current = true

	hand = Node3D.new()
	hand.top_level = true
	add_child(hand)
	flashlight = SpotLight3D.new()
	flashlight.light_color = Color(1.0, 0.95, 0.86)
	flashlight.light_energy = _flash_energy
	flashlight.spot_range = 22.0
	flashlight.spot_angle = 27.0
	flashlight.spot_angle_attenuation = 0.9
	flashlight.spot_attenuation = 1.4
	flashlight.shadow_enabled = true
	flashlight.shadow_bias = 0.03
	flashlight.shadow_normal_bias = 1.0
	flashlight.shadow_blur = 1.2
	flashlight.light_volumetric_fog_energy = 1.0
	flashlight.light_size = 0.03
	flashlight.light_specular = 0.8
	var cookie: Texture2D = load("res://assets/gen/flashlight_cookie.png")
	flashlight.light_projector = cookie
	flashlight.visible = false
	hand.add_child(flashlight)
	# léger halo autour du joueur quand la lampe est allumée (lumière réfléchie)
	flash_fill = OmniLight3D.new()
	flash_fill.light_energy = 0.0
	flash_fill.omni_range = 3.5
	flash_fill.light_color = Color(1.0, 0.95, 0.88)
	flash_fill.shadow_enabled = false
	flash_fill.light_volumetric_fog_energy = 0.0
	hand.add_child(flash_fill)
	flash_fill.position = Vector3(0, 0, -1.2)

	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -2.3)
	ray.collision_mask = 1 | 4
	ray.collide_with_areas = true
	ray.exclude_parent = true
	cam.add_child(ray)
	ray.add_exception(self)
	# visée de la lampe : elle est tenue à droite, Théo la braque vers ce qu'il regarde
	aim_ray = RayCast3D.new()
	aim_ray.target_position = Vector3(0, 0, -14.0)
	aim_ray.collision_mask = 1
	cam.add_child(aim_ray)
	aim_ray.add_exception(self)
	_glitch_cd = randf_range(70.0, 160.0)

	# corps de Théo (agent de sécurité) : visible seulement par les caméras de surveillance
	body = Actor.create(self, "theo")
	body.set_layers(2)
	body.set_shadows(false)

	breath_player = Sound.loop("breath_heavy_loop", -60.0, "World", self)
	heart_player = Sound.loop("heartbeat_loop", -60.0, "World", self)
	_snap_camera()


func set_look(new_yaw: float, new_pitch: float) -> void:
	yaw = new_yaw
	pitch = new_pitch
	_cam_yaw = yaw
	_cam_pitch = pitch
	_snap_camera()


func _snap_camera() -> void:
	if head == null:
		return
	head.global_position = global_position + Vector3(0, _height, 0)
	head.global_basis = Basis.from_euler(Vector3(_cam_pitch, _cam_yaw, 0))
	hand.global_transform = head.global_transform
	_hand_basis = head.global_basis


func _unhandled_input(event: InputEvent) -> void:
	if Game.args.has("shots"):
		return  # captures automatiques : on ignore souris et clavier
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and look_enabled and not Game.ui.document_open:
		var sens := MOUSE_SENS * float(Game.settings.get("sensitivity", 1.0))
		yaw -= event.relative.x * sens
		pitch = clampf(pitch - event.relative.y * sens, deg_to_rad(-72.0), deg_to_rad(65.0))
	if event.is_action_pressed("flashlight") and control_enabled and has_flashlight and not Game.ui.document_open:
		set_flashlight(not flashlight_on)


func set_flashlight(on: bool, silent := false) -> void:
	flashlight_on = on
	flashlight.visible = on
	if not silent:
		Sound.play("flashlight_click", -6.0, randf_range(0.95, 1.05))
		emit_noise(1.5)


## Fait vaciller la lampe pendant `duration` secondes.
func flicker(duration: float) -> void:
	_flicker_t = maxf(_flicker_t, duration)


func can_act() -> bool:
	return control_enabled and not Game.ui.document_open and not Game.args.has("shots")


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_move(delta)
	_update_camera(delta)
	_update_interaction(delta)
	_update_audio(delta)


# ------------------------------------------------------------------ déplacement
func _move(delta: float) -> void:
	var input := Vector2.ZERO
	if can_act():
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	crouching = can_act() and Input.is_action_pressed("crouch")
	var wants_run := can_act() and Input.is_action_pressed("run") and input.y < -0.3 and not crouching
	running = wants_run and not exhausted and stamina > 0.0
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif running:
		speed = RUN_SPEED
	var dir := (Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y))
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target := dir * speed
	var accel := 10.0 if target.length() > 0.1 else 12.0
	velocity.x = lerpf(velocity.x, target.x, 1.0 - exp(-accel * delta))
	velocity.z = lerpf(velocity.z, target.z, 1.0 - exp(-accel * delta))
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	var pre := global_position
	var wanted := Vector3(velocity.x, 0, velocity.z) * delta
	move_and_slide()
	# marches, seuils de porte, trottoirs : on "monte" l'obstacle s'il est assez bas
	var moved := Vector3(global_position.x - pre.x, 0, global_position.z - pre.z)
	if wanted.length() > 0.0005 and moved.length() < wanted.length() * 0.6 and is_on_wall():
		_try_step(pre, wanted)

	var hspeed := Vector2(velocity.x, velocity.z).length()
	moving = hspeed > 0.35
	# endurance
	if running and moving:
		stamina -= delta / 6.5
		if stamina <= 0.0:
			stamina = 0.0
			exhausted = true
			Game.hud.hint("Vous êtes à bout de souffle.", 2.5)
	else:
		stamina = minf(1.0, stamina + delta / (9.0 if exhausted else 6.0))
		if exhausted and stamina > 0.45:
			exhausted = false
	# pas : un pas à chaque point bas du balancement
	var stride := 0.62 if crouching else (0.95 if running else 0.74)
	var before := floorf(_bob / PI)
	_bob += hspeed * delta / stride * PI
	if is_on_floor() and moving and floorf(_bob / PI) != before:
		_footstep()
	# corps vu par les caméras : il se tourne vers où il va, et recule pour de vrai
	var cycle := "crouch_walk" if crouching else ("run" if running else "walk")
	var rel := 0.0
	var backwards := false
	if moving:
		rel = wrapf(atan2(-velocity.x, -velocity.z) - yaw, -PI, PI)
		if absf(rel) > deg_to_rad(110.0):
			backwards = true
			rel = wrapf(rel + PI, -PI, PI)
	_body_yaw = lerp_angle(_body_yaw, yaw + rel, 1.0 - exp(-8.0 * delta))
	body.rotation.y = _body_yaw
	body.locomote(cycle, hspeed if moving else 0.0, "idle", 0.25, 1.7 if running else 1.4, backwards)


const STEP_HEIGHT := 0.36
var _step_offset := 0.0


func _try_step(from_pos: Vector3, motion: Vector3) -> void:
	var t := Transform3D(global_basis, from_pos)
	var up := Vector3(0, STEP_HEIGHT, 0)
	if test_move(t, up):
		return
	var t_up := t.translated(up)
	var fwd := motion.normalized() * maxf(motion.length(), 0.08)
	if test_move(t_up, fwd):
		return
	var t_fwd := t_up.translated(fwd)
	var col := KinematicCollision3D.new()
	if not test_move(t_fwd, -up - Vector3(0, 0.05, 0), col):
		return
	if col.get_normal().angle_to(Vector3.UP) > deg_to_rad(45.0):
		return
	var land := t_fwd.origin + col.get_travel()
	var rise := land.y - from_pos.y
	if rise < 0.01:
		return
	global_position = land
	_step_offset += rise


func _footstep() -> void:
	var surface := "concrete"
	if Game.level != null:
		surface = Game.level.get_surface(global_position)
	var vol := -14.0
	var radius := 5.0
	if crouching:
		vol = -24.0
		radius = 1.4
	elif running:
		vol = -7.0
		radius = 13.0
	if surface == "water":
		radius *= 1.6
		vol += 1.0
	elif surface == "glass":
		# des éclats de verre : impossible de les écraser sans bruit, même accroupi
		radius = maxf(radius * 1.3, 7.5)
		vol = maxf(vol, -9.0)
	Sound.play_at(Sound.variant("step_" + surface, 4), global_position + Vector3(0, 0.05, 0), vol, randf_range(0.92, 1.08), 3.0, 30.0)
	emit_noise(radius)
	if Game.level != null and Game.level.has_method("on_footstep"):
		Game.level.on_footstep(surface)
	_bob_kick()


func emit_noise(radius: float) -> void:
	if Game.level != null:
		Game.level.on_noise(global_position, radius * noise_mul)


func _bob_kick() -> void:
	pass


# ------------------------------------------------------------------ caméra
func _update_camera(delta: float) -> void:
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var target_h := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	_height = lerpf(_height, target_h, 1.0 - exp(-8.0 * delta))
	# lissage de la caméra quand on monte une marche
	_step_offset = lerpf(_step_offset, 0.0, 1.0 - exp(-10.0 * delta))
	# la caméra suit la souris avec un léger retard (fixée au torse)
	var prev_yaw := _cam_yaw
	_cam_yaw = lerp_angle(_cam_yaw, yaw, 1.0 - exp(-16.0 * delta))
	_cam_pitch = lerpf(_cam_pitch, pitch, 1.0 - exp(-16.0 * delta))
	_turn_speed = lerpf(_turn_speed, wrapf(_cam_yaw - prev_yaw, -PI, PI) / maxf(delta, 0.001), 1.0 - exp(-10.0 * delta))
	Game.post_mat.set_shader_parameter("shutter", clampf(_turn_speed * 0.0035, -0.03, 0.03))

	# balancement de marche, discret : la caméra décrit un « U » doux (au plus bas à chaque pas,
	# au plus haut quand le poids passe sur une jambe), un peu plus ample en courant
	var amp_target := 0.0
	if moving and is_on_floor():
		amp_target = 0.55 if crouching else (1.45 if running else 1.0)
	_bob_amp = lerpf(_bob_amp, amp_target, 1.0 - exp(-6.0 * delta))
	_breath_t += delta * (2.6 if exhausted else 1.1)
	var sb := sin(_bob)
	var bob_y := (sb * sb - 0.5) * 0.014 * _bob_amp
	var bob_x := sb * 0.011 * _bob_amp
	var roll := sb * deg_to_rad(0.45) * _bob_amp
	var sway_yaw := sb * deg_to_rad(0.5) * _bob_amp
	var breath := sin(_breath_t) * (0.006 if not exhausted else 0.016)
	var shake := Game.shake_amount()
	var shake_rot := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.02 * shake

	var basis := Basis.from_euler(Vector3(_cam_pitch + breath * 0.6 + shake_rot.x, _cam_yaw + sway_yaw + shake_rot.y, roll + shake_rot.z))
	var origin := global_position + Vector3(0, _height + bob_y + breath - _step_offset, 0) + Basis(Vector3.UP, _cam_yaw) * Vector3(bob_x, 0, 0)
	var t := Transform3D(basis.orthonormalized(), origin)
	if cine_weight > 0.0:
		t = t.interpolate_with(cine_offset, cine_weight)
	head.global_transform = t

	# la main (lampe) suit avec son propre retard, un peu à droite et en bas, et vise ce que
	# Théo regarde : le centre du faisceau tombe au centre de l'image
	var hand_pos := head.global_position + head.global_basis * Vector3(0.24, -0.28, -0.25)
	aim_ray.force_raycast_update()
	var want_dist := 14.0
	if aim_ray.is_colliding():
		want_dist = clampf(cam.global_position.distance_to(aim_ray.get_collision_point()), 0.9, 14.0)
	_aim_dist = lerpf(_aim_dist, want_dist, 1.0 - exp(-8.0 * delta))
	var aim_at := head.global_position - head.global_basis.z * _aim_dist
	var aim_basis := Basis.looking_at(aim_at - hand_pos, head.global_basis.y)
	_hand_basis = _hand_basis.slerp(aim_basis, 1.0 - exp(-9.0 * delta)).orthonormalized()
	var hb := _hand_basis
	# mains qui tremblent (après une poursuite) : le faisceau tremblote quelques secondes
	_update_tremble(delta)
	if _tremble > 0.0:
		_tremble_t += delta
		var a := minf(_tremble / 2.0, 1.0) * deg_to_rad(1.1)
		hb = hb * Basis.from_euler(Vector3(
			(sin(_tremble_t * 23.0) + sin(_tremble_t * 37.3) * 0.6) * a,
			(sin(_tremble_t * 19.7 + 1.3) + sin(_tremble_t * 41.0) * 0.5) * a, 0.0))
	hand.global_transform = Transform3D(hb, hand_pos)

	# lampe : faux contact de temps en temps (elle grésille, Théo tape dessus)
	if flashlight_on and has_flashlight:
		_glitch_cd -= delta
		if _glitch_cd <= 0.0 and _flicker_t <= 0.0 and cine_weight <= 0.0:
			_glitch_cd = randf_range(80.0, 170.0)
			_flashlight_glitch()
	# lampe : vacillement + rendu
	if flashlight_on:
		var e := _flash_energy
		if _dim_t > 0.0:
			_dim_t -= delta
			e *= _dim_level * (0.85 + 0.15 * sin(_tremble_t * 31.0 + _dim_t * 17.0))
		if _flicker_t > 0.0:
			_flicker_t -= delta
			e = _flash_energy * (0.0 if randf() < 0.45 else randf_range(0.2, 1.0))
		if _lamp_off:
			e = 0.0
		flashlight.light_energy = e
		flash_fill.light_energy = e * 0.03
	else:
		flash_fill.light_energy = 0.0


# ------------------------------------------------------------------ interaction
func _update_interaction(delta: float) -> void:
	var focus: Interactable = null
	if can_act() and not Game.ui.blocks_interaction():
		ray.force_raycast_update()
		if ray.is_colliding():
			var c := ray.get_collider()
			if c is Interactable and (c as Interactable).enabled:
				focus = c
	if focus != _focus:
		_hold = 0.0
		_focus = focus
	if _focus == null:
		Game.hud.prompt("")
		Game.hud.hold(0.0)
		return
	Game.hud.prompt(_focus.prompt)
	if _focus.hold_time > 0.0:
		if Input.is_action_pressed("interact"):
			_hold += delta
			Game.hud.hold(_hold / _focus.hold_time)
			if _hold >= _focus.hold_time:
				_hold = 0.0
				Game.hud.hold(0.0)
				var f := _focus
				_focus = null
				f.trigger()
		else:
			_hold = maxf(0.0, _hold - delta * 2.0)
			Game.hud.hold(_hold / _focus.hold_time)
	elif Input.is_action_just_pressed("interact"):
		var f2 := _focus
		_focus = null
		Game.hud.prompt("")
		f2.trigger()


func is_holding_interact() -> bool:
	return _hold > 0.0


# ------------------------------------------------------------------ son du corps
var danger := 0.0  ## 0..1, fourni par le niveau (proximité de la créature)
var _pant_cd := 0.0


func _update_audio(_delta: float) -> void:
	var breath_target := -60.0
	if exhausted:
		breath_target = -8.0
	elif stamina < 0.6:
		breath_target = lerpf(-30.0, -14.0, 1.0 - stamina / 0.6)
	breath_player.volume_db = lerpf(breath_player.volume_db, breath_target, 0.05)
	# cœur en fond, discret : il accélère avec le danger et ralentit quand il retombe
	var heart_target := -60.0 if danger < 0.05 else lerpf(-30.0, -13.0, danger)
	heart_player.volume_db = lerpf(heart_player.volume_db, heart_target, 0.03)
	heart_player.pitch_scale = lerpf(heart_player.pitch_scale, lerpf(0.95, 1.75, danger), 0.02)
	# à bout de souffle : Théo halète, et ça s'entend de loin (la créature en profite)
	if exhausted:
		_pant_cd -= _delta
		if _pant_cd <= 0.0:
			_pant_cd = 0.7
			emit_noise(9.0)


## Après une grosse frayeur (la créature tout près, une poursuite), les mains tremblent
## quelques secondes une fois le danger passé.
func _update_tremble(delta: float) -> void:
	if danger > 0.65:
		_scared = true
	elif _scared and danger < 0.35:
		_scared = false
		_tremble = 6.0
	_tremble = maxf(0.0, _tremble - delta)


## Faux contacts de la lampe, jamais deux fois pareils :
## grésillement bref · baisse de tension · un ou deux clignements · coupure violente d'une seconde.
func _flashlight_glitch() -> void:
	var tree := get_tree()
	var roll := randf()
	if roll < 0.3:
		# grésillement : quelques dixièmes de seconde
		var fail := randf_range(0.25, 0.7)
		flicker(fail)
		Sound.play_at("flicker", hand.global_position, -18.0, 1.6, 2.0, 8.0)
		await tree.create_timer(fail + 0.15, false).timeout
	elif roll < 0.55:
		# baisse de tension : le faisceau jaunit, faiblit et ondule, puis revient
		_dim_level = randf_range(0.25, 0.45)
		_dim_t = randf_range(1.2, 2.6)
		await tree.create_timer(_dim_t + 0.1, false).timeout
	elif roll < 0.78:
		# un ou deux clignements secs
		for k in (1 if randf() < 0.5 else 2):
			_lamp_off = true
			await tree.create_timer(randf_range(0.06, 0.12), false).timeout
			_lamp_off = false
			await tree.create_timer(randf_range(0.12, 0.25), false).timeout
	else:
		# coupure violente : ça grésille fort, noir complet une seconde, puis elle se rallume
		flicker(0.35)
		Sound.play_at("flicker", hand.global_position, -12.0, 1.1, 2.0, 10.0)
		await tree.create_timer(0.35, false).timeout
		_lamp_off = true
		await tree.create_timer(randf_range(0.9, 1.3), false).timeout
		_lamp_off = false
		Sound.play("flashlight_click", -10.0, 1.1)
		Game.shake(0.08)
	if randf() < 0.6 and flashlight_on:
		# deux petits coups du plat de la main sur la lampe
		Sound.play(Sound.variant("flashlight_tap", 2), -10.0, randf_range(0.95, 1.05))
		Game.shake(0.05)


## Fixe des caméras de cinématique : poids 0 = caméra normale, 1 = transform imposé.
func set_cinematic(t: Transform3D, weight: float) -> void:
	cine_offset = Transform3D(t.basis.orthonormalized(), t.origin)
	cine_weight = clampf(weight, 0.0, 1.0)


func eye_position() -> Vector3:
	return head.global_position
