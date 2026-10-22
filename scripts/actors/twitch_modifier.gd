class_name TwitchModifier
extends SkeletonModifier3D
## Surcouche procédurale appliquée APRÈS l'animation de capture :
## secousses brusques de la tête et du cou, tête penchée, mâchoire, et regard vers une cible.
## C'est ce qui rend la créature "pas naturelle".

var bones := {}  ## nom logique → index
var target: Node3D = null  ## si défini, la tête se tourne vers lui
var forward_ref: Node3D = null  ## nœud dont le -Z donne "devant" (l'Actor)
var look_weight := 0.0
var twitch_amount := 1.0
var tilt := 0.0  ## inclinaison de tête permanente (rad)
var _jerk := Quaternion.IDENTITY
var _jerk_target := Quaternion.IDENTITY
var _t := 0.0
var _next := 0.5
var _spasm := 0.0


func spasm(duration := 0.6) -> void:
	_spasm = maxf(_spasm, duration)


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or int(bones.get("head", -1)) < 0:
		return
	_t += delta
	_spasm = maxf(0.0, _spasm - delta)
	_next -= delta
	if _next <= 0.0:
		var mag := (0.25 + (0.6 if _spasm > 0.0 else 0.0)) * twitch_amount
		_jerk_target = Quaternion.from_euler(Vector3(randf_range(-mag, mag) * 0.5, randf_range(-mag, mag), randf_range(-mag, mag) * 0.8))
		_next = randf_range(0.04, 0.12) if _spasm > 0.0 else randf_range(0.25, 1.6)
	# les secousses sont presque instantanées : c'est le côté "image qui saute"
	_jerk = _jerk.slerp(_jerk_target, 1.0 - exp(-28.0 * delta))
	var head: int = bones["head"]
	var q := sk.get_bone_pose_rotation(head)
	var extra := _jerk * Quaternion(Vector3(0, 0, 1), tilt)
	if target != null and is_instance_valid(target) and look_weight > 0.0:
		# rotation monde de la tête → orientation vers la cible
		var gp := sk.global_transform * sk.get_bone_global_pose(head)
		var to := (target.global_position - gp.origin).normalized()
		var fwd := -forward_ref.global_basis.z if forward_ref != null else Vector3.FORWARD
		var look := Quaternion(fwd.normalized(), to)
		# exprimée dans le repère local de l'os
		var parent := sk.get_bone_parent(head)
		var parent_basis := (sk.global_transform.basis * (sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis())).orthonormalized()
		var local_look := Quaternion(parent_basis.inverse() * Basis(look) * parent_basis)
		extra = Quaternion.IDENTITY.slerp(local_look, clampf(look_weight, 0.0, 1.0) * 0.8) * extra
	sk.set_bone_pose_rotation(head, extra * q)
	if int(bones.get("neck", -1)) >= 0:
		var n: int = bones["neck"]
		sk.set_bone_pose_rotation(n, Quaternion.IDENTITY.slerp(_jerk, 0.5) * sk.get_bone_pose_rotation(n))
