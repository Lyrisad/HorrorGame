class_name SecurityCamera
extends Node3D
## Caméra de surveillance murale (modèle Poly Haven) avec diode rouge.
## Le support (platine + bras) reste vissé au mur ; seule la tête pivote sur sa rotule.
## Quand `tracking` est vrai, elle suit une cible (le joueur) avec un bruit de moteur.

var tracking := false
var target: Node3D = null
var led_on := true
var pivot: Node3D
var lens: Marker3D
var led: MeshInstance3D
var led_light: OmniLight3D
var _was_moving := false
var _servo_cd := 0.0
var _blink := 0.0
var rest_dir := Vector3.FORWARD
var mount: Node3D
var mount_out := Vector3.ZERO  ## direction qui sort de la surface où le support est vissé (BAS = plafond)
var mounted := false  ## fixé explicitement (éditeur, disposition sauvegardée) : pas de recherche auto
const MAX_TURN := 1.05  ## ~60° de part et d'autre de sa direction de repos
const SCALE := 0.85
const SWIVEL := Vector3(0, 0.07, -0.03)  ## rotule, dans le repère du modèle
const ARM := (0.303 - 0.03) * SCALE  ## de la rotule à la platine murale
const MOUNT_MODEL := "res://assets/models/security_camera_mount/security_camera_mount.glb"
const HEAD_MODEL := "res://assets/models/security_camera_head/security_camera_head.glb"


## `wall_normal` : direction vers laquelle le mur regarde (la caméra en sort).
static func create(parent: Node, pos: Vector3, look_dir: Vector3) -> SecurityCamera:
	var c := SecurityCamera.new()
	c.rest_dir = look_dir.normalized()
	c.position = pos
	parent.add_child(c)
	return c


func _ready() -> void:
	# le modèle a son objectif vers +Z : on le tourne pour qu'il regarde -Z (convention look_at) ;
	# l'origine de ce nœud est la rotule
	var off := -Vector3(-SWIVEL.x, SWIVEL.y, -SWIVEL.z) * SCALE
	mount = Node3D.new()
	mount.name = "Mount"
	add_child(mount)
	B.model(mount, MOUNT_MODEL, off, 180.0, {"scale": SCALE, "center": false})
	pivot = Node3D.new()
	add_child(pivot)
	var m := B.model(pivot, HEAD_MODEL, off, 180.0, {"scale": SCALE, "center": false})
	m.name = "Model"
	led = B.sphere(pivot, 0.008, Vector3(0.03, 0.035, -0.235), B.emissive(Color(1, 0.05, 0.03), 6.0, true), 8)
	led_light = B.omni(pivot, Vector3(0.03, 0.035, -0.26), Color(1, 0.05, 0.03), 0.15, 0.6)
	led_light.light_volumetric_fog_energy = 0.0
	lens = Marker3D.new()
	lens.position = Vector3(0, 0.1, -0.27)
	pivot.add_child(lens)
	# direction de repos donnée dans le repère du parent
	var parent3d := get_parent() as Node3D
	if parent3d != null:
		rest_dir = (parent3d.global_basis * rest_dir).normalized()
	_orient_mount(Vector3(rest_dir.x, 0, rest_dir.z))
	_aim(global_position + rest_dir, 1.0, 1.0)
	_find_wall.call_deferred()


## Support : `out` = direction qui sort du mur (horizontale) ; vers le bas = fixé au plafond.
func _orient_mount(out: Vector3) -> void:
	if out.length() < 0.01:
		out = Vector3.FORWARD
	out = out.normalized()
	mount_out = out
	if out.y < -0.9:
		var hint := Vector3(rest_dir.x, 0, rest_dir.z)
		mount.global_basis = Basis.looking_at(out, hint.normalized() if hint.length() > 0.05 else Vector3.FORWARD)
	else:
		mount.global_basis = Basis.looking_at(out, Vector3.UP)


## Visse le support au mur touché en `point` (normale `normal`) : la platine affleure le mur.
func attach_wall(point: Vector3, normal: Vector3) -> void:
	var out := Vector3(normal.x, 0, normal.z).normalized()
	global_position = Vector3(point.x, global_position.y, point.z) + out * ARM
	_orient_mount(out)
	mounted = true


## Fixé au plafond (platine contre le plafond, bras vertical).
func attach_ceiling(point: Vector3) -> void:
	global_position = point + Vector3.DOWN * ARM
	_orient_mount(Vector3.DOWN)
	mounted = true


## Support déjà placé (disposition sauvegardée) : `pos` = rotule, `out` = sortie de la surface.
func set_mount(pos: Vector3, out: Vector3) -> void:
	global_position = pos
	_orient_mount(out)
	mounted = true


## Au chargement : cherche le mur (ou le plafond) le plus proche et y visse le support.
func _find_wall() -> void:
	if not is_inside_tree():
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree() or mounted:
		return
	var space := get_world_3d().direct_space_state
	var best := {}
	var best_d := 0.9
	var dirs: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.UP]
	var flat := Vector3(-rest_dir.x, 0, -rest_dir.z)
	if flat.length() > 0.1:
		dirs.append(flat.normalized())
	for d in dirs:
		var q := PhysicsRayQueryParameters3D.create(global_position, global_position + d * 0.9, 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var dist: float = global_position.distance_to(hit["position"])
		# un mur derrière ou sur le côté (jamais devant l'objectif)
		if d != Vector3.UP and d.dot(Vector3(rest_dir.x, 0, rest_dir.z).normalized()) > 0.5:
			continue
		if dist < best_d:
			best_d = dist
			best = hit
			best["dir"] = d
	if best.is_empty():
		return
	if best["dir"] == Vector3.UP:
		attach_ceiling(best["position"])
	else:
		attach_wall(best["position"], best["normal"])


func _aim(point: Vector3, lambda: float, delta: float) -> float:
	var dir := (point - pivot.global_position)
	if dir.length() < 0.01:
		return 0.0
	var target_basis := Basis.looking_at(dir.normalized(), Vector3.UP)
	var before := pivot.global_basis
	pivot.global_basis = before.slerp(target_basis, 1.0 - exp(-lambda * delta)).orthonormalized()
	return before.z.angle_to(pivot.global_basis.z)


func _process(delta: float) -> void:
	_blink += delta
	led.visible = led_on and fmod(_blink, 1.6) < 1.2
	led_light.visible = led.visible
	var moved := 0.0
	if tracking and target != null and is_instance_valid(target):
		# elle suit la cible, mais sans jamais se retourner vers le mur où elle est fixée
		var want := (target.global_position + Vector3(0, 1.2, 0) - pivot.global_position).normalized()
		var ang := rest_dir.angle_to(want)
		if ang > MAX_TURN:
			want = rest_dir.slerp(want, MAX_TURN / ang).normalized()
		moved = _aim(pivot.global_position + want, 3.5, delta)
	_servo_cd -= delta
	var moving := moved > delta * 0.15
	if moving and not _was_moving and _servo_cd <= 0.0:
		Sound.play_at("servo", global_position, -16.0, randf_range(0.9, 1.15), 2.0, 14.0)
		_servo_cd = 0.6
	_was_moving = moving


## Nouvelle direction de repos (monde) : la caméra s'y tourne aussitôt (éditeur de carte).
func set_rest(world_dir: Vector3) -> void:
	if world_dir.length() < 0.01:
		return
	rest_dir = world_dir.normalized()
	if pivot != null:
		pivot.global_basis = Basis.looking_at(rest_dir, Vector3.UP if absf(rest_dir.y) < 0.98 else Vector3.FORWARD)


## Point de vue de la caméra (pour les écrans de surveillance).
func view_transform() -> Transform3D:
	return lens.global_transform
