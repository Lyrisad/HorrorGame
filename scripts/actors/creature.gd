class_name Creature
extends Node3D
## « Le Rôdeur » : créature aveugle des égouts qui chasse au son.
## Modèle « The Rake » et ses animations d'origine (marche à quatre pattes, galop, cri dressé,
## fouille en reniflant) + tics procéduraux de la tête (TwitchModifier).
## IA à états : ronde → enquête sur un bruit → fouille → poursuite → attaque.

signal caught_player
signal script_done
signal lost_track(distance: float)  ## il a perdu la trace du joueur pendant une poursuite

enum State { DORMANT, STAND, SCRIPTED, PATROL, INVESTIGATE, SEARCH, CHASE, ATTACK }

const PATROL_SPEED := 1.1
const INVESTIGATE_SPEED := 1.9
const ALERT_SPEED := 2.7
const CHASE_SPEED := 3.6
const CATCH_DIST := 1.25
## Il ne galope pas indéfiniment : après une course il s'essouffle quelques secondes
## (c'est le moment de le semer : tourner à un angle, puis avancer sans bruit).
const CHASE_BURST := 8.0
const WINDED_TIME := 3.2
const WINDED_SPEED := 1.7
const BODY_RADIUS := 0.55  ## encombrement du corps autour de l'origine (piliers)

var nav: Node = null  ## niveau fournissant nav_path(), random_point(), has_los()
var player: Player = null
var state := State.DORMANT
var path: PackedVector3Array = PackedVector3Array()
var speed := 0.0
var target_speed := 0.0
var heading := 0.0
var look_target: Node3D = null
var actor: Actor
var twitch: TwitchModifier
var breath: AudioStreamPlayer3D
var _state_t := 0.0
var _last_heard := 99.0
var _last_known := Vector3.ZERO
var _vocal_cd := 4.0
var _step_accum := 0.0
var _repath_cd := 0.0
var _stuck_from := Vector3.ZERO
var _stuck_check := 0.0
var _stuck_t := 0.0  ## depuis combien de temps elle n'avance plus alors qu'elle a un chemin à suivre
var _search_dur := 5.0
var _patrol_wait := 0.0
var _stand_anim := "listen"
var _stand_speed := 0.6
var _rear := 0.0  ## se dresse en hurlant avant de charger (secondes restantes)
var _chase_run := 0.0
var _winded := 0.0
## 0..3 : fusibles ramassés par Théo — elle s'agite (+5 % de vitesse et +12 % d'ouïe par fusible)
var aggression := 0
var _move_speed := 0.0  ## vitesse réellement parcourue (l'animation de marche suit celle-ci)
var _contacts: Array[int] = []  ## os qui touchent le sol (mains, doigts, pieds, orteils)
var _contact_hist: Array = []  ## [temps, hauteur la plus basse] sur le dernier pas
var _clock := 0.0


func _ready() -> void:
	actor = Actor.create(self, "creature")
	twitch = TwitchModifier.new()
	twitch.forward_ref = actor
	actor.skeleton.add_child(twitch)
	twitch.bones = {"head": actor.bone("Head"), "neck": actor.bone("Neck"), "hips": actor.bone("Hips")}
	_wet_skin()
	for nm in ["hand.L", "hand.R", "middle2.L", "middle2.R", "foot.L", "foot.R", "toe.L", "toe.R"]:
		for i in actor.skeleton.get_bone_count():
			if actor.skeleton.get_bone_name(i).begins_with(nm):
				_contacts.append(i)
				break
	breath = Sound.loop_at("creature_breath_loop", self, -4.0, 3.0, 22.0, "Creature")
	breath.position.y = 1.5
	if state == State.DORMANT:
		visible = false
		breath.stop()


## Peau humide et blafarde ; les yeux laiteux accrochent la lumière de la lampe.
func _wet_skin() -> void:
	for mi in actor.model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var eyes := String(m.name).begins_with("eyes")
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s) as StandardMaterial3D
			if mat == null:
				continue
			var nm := mat.duplicate() as StandardMaterial3D
			nm.metallic = 0.0
			nm.metallic_texture = null
			nm.roughness_texture = null
			if eyes:
				nm.roughness = 0.08
				nm.metallic_specular = 0.9
				nm.albedo_color = Color(0.85, 0.86, 0.8)
			else:
				nm.roughness = 0.5
				nm.metallic_specular = 0.4
				nm.rim_enabled = true
				nm.rim = 0.08
				nm.rim_tint = 0.6
				# peau grise et sale plutôt que blanche
				nm.albedo_color = Color(0.4, 0.38, 0.36)
			m.set_surface_override_material(s, nm)


# ------------------------------------------------------------------ contrôle
func activate(start_state := State.PATROL) -> void:
	visible = true
	_breathe()
	_set_state(start_state)


## Endormie, elle ne respire pas : on ARRÊTE le son (une simple pause serait relancée par Godot à la fin de
## n'importe quelle pause du jeu — chargement, menu, inventaire — et on l'entendrait sous la plaque d'égout).
func _breathe() -> void:
	if not breath.playing:
		breath.play(randf() * maxf(breath.stream.get_length() - 0.1, 0.0) if breath.stream != null else 0.0)


## Il a entendu exactement où est Théo : il hurle et fonce sur lui, en le « suivant à l'oreille »
## pendant `seconds` même s'il se tait (ensuite il faut que Théo fasse du bruit pour être pisté).
func charge(seconds := 6.0) -> void:
	activate(State.CHASE)
	_last_heard = -seconds + 2.6
	if player != null:
		_last_known = player.global_position


func deactivate() -> void:
	visible = false
	breath.stop()
	state = State.DORMANT


## Immobile, tête tournée vers `who` (apparition au bord de la route).
func stand_and_watch(who: Node3D, anim_name := "listen", anim_speed := 0.6) -> void:
	_stand_speed = anim_speed
	visible = true
	_breathe()
	look_target = who
	twitch.target = who
	twitch.look_weight = 1.0
	state = State.STAND
	path.clear()
	target_speed = 0.0
	_stand_anim = anim_name


## Marche scénarisée le long de points, puis signal `script_done`.
func script_walk(points: PackedVector3Array, walk_speed: float) -> void:
	visible = true
	_breathe()
	path = points
	target_speed = walk_speed
	state = State.SCRIPTED


func _set_state(s: State) -> void:
	state = s
	_state_t = 0.0
	twitch.look_weight = 0.0
	match s:
		State.PATROL:
			target_speed = PATROL_SPEED
			_pick_patrol()
		State.SEARCH:
			target_speed = 0.0
			path.clear()
			_search_dur = randf_range(4.0, 7.0)
			_click()
			twitch.spasm(0.8)
		State.CHASE:
			target_speed = CHASE_SPEED
			_last_heard = 0.0
			_repath_cd = 0.0
			if player != null:
				_last_known = player.global_position
			Sound.play_at("creature_shriek", head_position(), 4.0, randf_range(0.95, 1.05), 10.0, 70.0, null, "Creature")
			Game.glitch(0.35)
			twitch.spasm(1.2)
			_vocal_cd = 2.0
			# elle se dresse et hurle vers le bruit, puis part au galop
			_rear = 0.9
			actor.play("screech", 0.15, 1.3)
			actor.anim.seek(0.6, true)
		State.ATTACK:
			target_speed = 0.0
			path.clear()
			# dressée au-dessus de Théo, bouche grande ouverte
			actor.play("screech", 0.1, 1.6)
			actor.anim.seek(0.7, true)


## Elle a un chemin mais n'a pas bougé de 30 cm en 1,5 s : chemin recalculé ; au bout de 6 s, le niveau la
## replace (s'il sait le faire, hors de la vue du joueur).
func _watch_stuck(delta: float) -> void:
	if target_speed < 0.3 or state in [State.STAND, State.ATTACK]:
		_stuck_check = 0.0
		_stuck_t = 0.0
		return
	_stuck_check += delta
	if _stuck_check < 1.5:
		return
	_stuck_check = 0.0
	var moved := Vector2(global_position.x - _stuck_from.x, global_position.z - _stuck_from.z).length()
	_stuck_from = global_position
	if moved > 0.3:
		_stuck_t = 0.0
		return
	_stuck_t += 1.5
	if nav != null and path.size() > 0:
		path = nav.nav_path(global_position, path[path.size() - 1])
	if _stuck_t >= 6.0 and nav != null and nav.has_method("unstick") and nav.unstick(self):
		_stuck_t = 0.0


func _pick_patrol() -> void:
	if nav == null:
		return
	var near := player.global_position if (player != null and randf() < 0.6) else global_position
	var goal: Vector3 = nav.random_point(near, 4 if near != global_position else 9)
	path = nav.nav_path(global_position, goal)


## Un bruit a été émis à `pos`, audible jusqu'à `radius` mètres.
## `lure` : bruit d'objet (bouteille lancée) — il fonce voir, sans se mettre à pister Théo.
func hear(pos: Vector3, radius: float, lure := false) -> void:
	if state in [State.DORMANT, State.STAND, State.SCRIPTED, State.ATTACK]:
		return
	radius *= 1.0 + 0.12 * aggression
	var d := global_position.distance_to(pos)
	# un bruit derrière un mur porte moins loin : tourner à un angle aide à le semer
	if d > radius * 0.55 and nav != null and not nav.has_los(global_position + Vector3(0, 1.0, 0), pos + Vector3(0, 0.6, 0)):
		radius *= 0.55
	if d > radius:
		return
	if lure:
		# en pleine poursuite, il ne lâche que si Théo n'est pas déjà sous son nez
		if state == State.CHASE and player != null and global_position.distance_to(player.global_position) < 4.5:
			return
		var was_chasing := state == State.CHASE
		_last_known = pos
		_last_heard = 99.0
		path = nav.nav_path(global_position, pos)
		state = State.INVESTIGATE
		_state_t = 0.0
		target_speed = ALERT_SPEED + 0.4
		twitch.spasm(0.8)
		_click()
		if was_chasing and player != null:
			lost_track.emit(global_position.distance_to(player.global_position))
		return
	_last_heard = 0.0
	_last_known = pos
	if state == State.CHASE:
		return
	if (d < 6.0 and radius >= 5.0) or (d < 9.0 and radius >= 12.0):
		_set_state(State.CHASE)
		return
	var offset := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * d * 0.12
	path = nav.nav_path(global_position, pos + offset)
	state = State.INVESTIGATE
	_state_t = 0.0
	target_speed = ALERT_SPEED if (radius >= 15.0 or d < radius * 0.5) else INVESTIGATE_SPEED
	twitch.spasm(0.5)
	if randf() < 0.7:
		_click()


## Va fouiner du côté de `pos`, à pas lents, en cliquant (sans avoir entendu le joueur).
func wander_to(pos: Vector3) -> void:
	if nav == null or state in [State.DORMANT, State.STAND, State.SCRIPTED, State.ATTACK, State.CHASE]:
		return
	path = nav.nav_path(global_position, pos)
	state = State.INVESTIGATE
	_state_t = 0.0
	target_speed = PATROL_SPEED * 1.25
	_click()


func _click() -> void:
	Sound.play_at(Sound.variant("creature_click", 3), head_position(), 0.0, randf_range(0.9, 1.1), 7.0, 50.0, null, "Creature")
	twitch.spasm(0.5)


# ------------------------------------------------------------------ boucle
func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if state == State.DORMANT:
		return
	_state_t += delta
	_last_heard += delta
	if state == State.CHASE and speed > 2.0:
		_chase_run += delta
		if _chase_run > CHASE_BURST and _winded <= 0.0:
			_winded = WINDED_TIME
			_chase_run = 0.0
			Sound.play_at(Sound.variant("creature_growl", 3), head_position(), 0.0, randf_range(0.7, 0.8), 7.0, 45.0, null, "Creature")
	elif state != State.CHASE:
		_chase_run = maxf(0.0, _chase_run - delta * 0.5)
	_winded = maxf(0.0, _winded - delta)
	_think(delta)
	_locomote(delta)
	_animate()
	_vocalize(delta)
	_ground(delta)


## Recale le corps pour que ses appuis touchent vraiment le sol : l'animation de galop d'origine bondit,
## mains et pieds à 30-50 cm du sol presque tout le cycle. On mesure l'appui le plus bas à chaque image
## et on écrase 75 % de ce bond : il reste une courte suspension, mais les pattes frappent le sol.
func _ground(delta: float) -> void:
	if _contacts.is_empty() or actor.skeleton == null:
		return
	_clock += delta
	var sk := actor.skeleton
	var low := INF
	for b in _contacts:
		low = minf(low, (sk.global_transform * sk.get_bone_global_pose(b)).origin.y)
	# hauteur de l'appui par rapport à l'origine du modèle (sans le recalage déjà appliqué)
	var rel := low - global_position.y - actor.position.y
	_contact_hist.append([_clock, rel])
	while _contact_hist.size() > 1 and _clock - float(_contact_hist[0][0]) > 0.7:
		_contact_hist.pop_front()
	var plant := INF  # hauteur au moment où une patte se pose (le plus bas du dernier cycle)
	for e in _contact_hist:
		plant = minf(plant, float(e[1]))
	var want := clampf(0.02 - (plant + 0.25 * maxf(rel - plant, 0.0)), -0.6, 0.25)
	actor.position.y = lerpf(actor.position.y, want, 1.0 - exp(-30.0 * delta))


func _think(delta: float) -> void:
	var pd := 999.0
	if player != null:
		pd = global_position.distance_to(player.global_position)
	match state:
		State.STAND:
			if look_target != null and is_instance_valid(look_target):
				var to := look_target.global_position - global_position
				heading = lerp_angle(heading, atan2(-to.x, -to.z), 1.0 - exp(-1.2 * delta))
				rotation.y = heading
			return
		State.SCRIPTED:
			if path.is_empty():
				target_speed = 0.0
				if speed < 0.05:
					state = State.STAND
					script_done.emit()
			return
		State.PATROL:
			if path.is_empty():
				_patrol_wait -= delta
				target_speed = 0.0
				if _patrol_wait <= 0.0:
					_patrol_wait = randf_range(2.0, 5.0)
					target_speed = PATROL_SPEED
					_pick_patrol()
		State.INVESTIGATE:
			if path.is_empty():
				_set_state(State.SEARCH)
		State.SEARCH:
			if _state_t > _search_dur:
				_set_state(State.PATROL)
		State.CHASE:
			_repath_cd -= delta
			var tracking := _last_heard < 2.6 or pd < 4.5
			if tracking:
				_last_known = player.global_position
				if _repath_cd <= 0.0:
					_repath_cd = 0.35
					if pd < 3.5 and nav.has_los(global_position + Vector3(0, 1.0, 0), player.global_position + Vector3(0, 1.0, 0)):
						path = PackedVector3Array([player.global_position])
					else:
						path = nav.nav_path(global_position, player.global_position)
				target_speed = CHASE_SPEED if pd > 3.0 else CHASE_SPEED + 0.3
				if player.exhausted:
					# il entend Théo haleter : il fonce, sans jamais s'essouffler
					target_speed = CHASE_SPEED + 1.1
					_winded = 0.0
				elif _winded > 0.0:
					target_speed = WINDED_SPEED
			else:
				path = nav.nav_path(global_position, _last_known)
				state = State.INVESTIGATE
				target_speed = ALERT_SPEED
				lost_track.emit(pd)
			if pd < CATCH_DIST:
				_set_state(State.ATTACK)
				caught_player.emit()
		State.ATTACK:
			if player != null:
				var tp := player.global_position - global_position
				heading = lerp_angle(heading, atan2(-tp.x, -tp.z), 1.0 - exp(-10.0 * delta))
				rotation.y = heading
			return
	# proximité : il sent la présence du joueur
	if state in [State.PATROL, State.INVESTIGATE, State.SEARCH] and player != null:
		var still_crouched := player.crouching and not player.moving
		if pd < 1.3 or (pd < 2.6 and not still_crouched):
			_set_state(State.CHASE)
		# Théo halète, à bout de souffle : à portée d'oreille, il fonce droit sur lui
		elif player.exhausted and pd < 13.0 and _last_heard < 1.0:
			_set_state(State.CHASE)


func _locomote(delta: float) -> void:
	if _rear > 0.0:
		_rear -= delta
		speed = 0.0
		_move_speed = 0.0
		return
	var agit := 1.0 + 0.05 * aggression if state != State.SCRIPTED else 1.0
	if path.is_empty():
		# arrivée : elle s'arrête vraiment (plus de pas sur place pendant qu'elle « freine »)
		speed = lerpf(speed, 0.0, 1.0 - exp(-10.0 * delta))
		_move_speed = lerpf(_move_speed, 0.0, 1.0 - exp(-14.0 * delta))
		return
	speed = lerpf(speed, target_speed * agit, 1.0 - exp(-4.0 * delta))
	_watch_stuck(delta)
	if path.is_empty():
		return
	var target := path[0]
	var to := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	var dist := to.length()
	if dist < 0.35:
		path.remove_at(0)
		return
	var want := atan2(-to.x, -to.z)
	heading = lerp_angle(heading, want, 1.0 - exp(-6.0 * delta))
	var fwd := Vector3(-sin(heading), 0, -cos(heading))
	var facing := absf(wrapf(want - heading, -PI, PI))
	# elle ralentit sur le dernier mètre au lieu de piler
	var arrive := 1.0 if path.size() > 1 else clampf(dist / 1.0, 0.3, 1.0)
	var mv := speed * delta * clampf(1.2 - facing, 0.2, 1.0) * arrive
	global_position += fwd * minf(mv, dist)
	_move_speed = lerpf(_move_speed, minf(mv, dist) / maxf(delta, 0.001), 1.0 - exp(-14.0 * delta))
	if nav != null and nav.has_method("obstacles"):
		for o in nav.obstacles():
			var c: Vector3 = o[0]
			var r: float = float(o[1]) + BODY_RADIUS
			var off := Vector3(global_position.x - c.x, 0, global_position.z - c.z)
			if off.length() < r:
				# glisse le long du pilier (du côté où il se trouve déjà)
				if off.length() < 0.01:
					off = Vector3(fwd.z, 0, -fwd.x)
				var out := off.normalized() * r
				global_position.x = c.x + out.x
				global_position.z = c.z + out.z
	rotation.y = heading
	# les pieds suivent le sol réel (cunette, citerne)
	if nav != null and nav.has_method("floor_y"):
		global_position.y = lerpf(global_position.y, nav.floor_y(global_position), 1.0 - exp(-10.0 * delta))
	_step_accum += mv
	var stride := 1.4 if state == State.CHASE else 0.9
	if _step_accum > stride:
		_step_accum = 0.0
		var vol := -10.0 + clampf(speed / CHASE_SPEED, 0.0, 1.0) * 10.0
		Sound.play_at(Sound.variant("creature_step", 3), global_position, vol, randf_range(0.85, 1.05), 5.0, 40.0, null, "Creature")
		if nav != null and nav.has_method("splash"):
			nav.splash(global_position + fwd * 0.4, 1.4 if state == State.CHASE else 0.9)


func _animate() -> void:
	match state:
		State.CHASE:
			if _rear <= 0.0:
				actor.locomote("run", _move_speed, "crouch", 0.25)
		State.ATTACK:
			pass
		State.STAND:
			actor.play(_stand_anim, 0.4, _stand_speed)
		State.SEARCH:
			actor.play("search", 0.5, 1.0)
		State.SCRIPTED:
			actor.locomote("run" if target_speed > 2.0 else "stalk", _move_speed, "crouch", 0.25)
		_:
			actor.locomote("stalk", _move_speed, "crouch", 0.35)


func _vocalize(delta: float) -> void:
	if state in [State.STAND, State.ATTACK, State.SCRIPTED]:
		return
	_vocal_cd -= delta
	if _vocal_cd > 0.0:
		return
	match state:
		State.CHASE:
			_vocal_cd = randf_range(1.2, 2.2)
			Sound.play_at(Sound.variant("creature_growl", 3), head_position(), 2.0, randf_range(1.0, 1.2), 8.0, 50.0, null, "Creature")
		State.INVESTIGATE, State.SEARCH:
			_vocal_cd = randf_range(1.8, 3.5)
			_click()
		_:
			_vocal_cd = randf_range(4.0, 9.0)
			if randf() < 0.5:
				_click()
			else:
				Sound.play_at(Sound.variant("creature_growl", 3), head_position(), -4.0, randf_range(0.85, 1.0), 6.0, 40.0, null, "Creature")


func is_hunting() -> bool:
	return state == State.CHASE


func head_position() -> Vector3:
	if actor == null or actor.skeleton == null:
		return global_position + Vector3(0, 1.8, 0)
	return actor.bone_position("Head")
