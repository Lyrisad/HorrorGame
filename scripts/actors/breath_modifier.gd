class_name BreathModifier
extends SkeletonModifier3D
## Respiration procédurale par-dessus une pose figée (un blessé adossé au mur) :
## la poitrine se soulève par à-coups, la tête dodeline ou retombe sur la poitrine,
## et les mains restent posées à plat au sol de chaque côté des hanches (IK à deux os).

var chest := -1
var head := -1
var forward_ref: Node3D = null  ## nœud dont le -Z donne « devant » (l'Actor)
var rate := 0.32  ## respirations par seconde
var depth := 1.0  ## 0 = ne respire plus
var droop := 0.0  ## 0..1 : la tête tombe en avant
## Bras posés au sol : [épaule (bras), avant-bras, main, côté (-1 gauche, +1 droite)]
var arms: Array = []
var pelvis := -1
var ground_y := 0.0
var _t := 0.0


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or chest < 0:
		return
	_t += delta * rate * TAU
	# souffle court et irrégulier
	var b := maxf(0.0, sin(_t)) * (0.75 + 0.25 * sin(_t * 0.37)) * depth
	var right := forward_ref.global_basis.x if forward_ref != null else Vector3.RIGHT
	var fwd := -forward_ref.global_basis.z if forward_ref != null else Vector3.FORWARD
	_rotate_world(sk, chest, right, b * 0.045)
	if head >= 0:
		_rotate_world(sk, head, right, -droop * 0.6 + b * 0.025)
	if pelvis < 0:
		return
	var hip := sk.global_transform * sk.get_bone_global_pose(pelvis).origin
	for a in arms:
		var side := float(a[3])
		var target := hip + right * side * 0.27 + fwd * 0.06
		target.y = ground_y + 0.035
		_two_bone(sk, int(a[0]), int(a[1]), int(a[2]), target, (-fwd * 0.8 + right * side * 0.6).normalized())


## IK analytique : l'épaule et le coude tournent pour que la main atteigne `target`,
## le coude part vers `pole`.
func _two_bone(sk: Skeleton3D, up: int, lo: int, hand: int, target: Vector3, pole: Vector3) -> void:
	if up < 0 or lo < 0 or hand < 0:
		return
	var g := sk.global_transform
	var s := g * sk.get_bone_global_pose(up).origin
	var e := g * sk.get_bone_global_pose(lo).origin
	var h := g * sk.get_bone_global_pose(hand).origin
	var la := s.distance_to(e)
	var lb := e.distance_to(h)
	var to := target - s
	var d := clampf(to.length(), 0.05, la + lb - 0.002)
	var dir := to.normalized()
	var ca := clampf((la * la + d * d - lb * lb) / (2.0 * la * d), -1.0, 1.0)
	var axis := dir.cross(pole)
	if axis.length() < 0.001:
		return
	var elbow := s + dir.rotated(axis.normalized(), acos(ca)) * la
	_rotate_world_to(sk, up, e - s, elbow - s)
	e = g * sk.get_bone_global_pose(lo).origin
	h = g * sk.get_bone_global_pose(hand).origin
	_rotate_world_to(sk, lo, h - e, s + dir * d - e)


## Tourne un os autour d'un axe donné dans le repère du monde.
func _rotate_world(sk: Skeleton3D, bone: int, axis_world: Vector3, angle: float) -> void:
	if absf(angle) < 0.0001:
		return
	var pb := _parent_basis(sk, bone)
	var axis_local := (pb.inverse() * axis_world).normalized()
	sk.set_bone_pose_rotation(bone, Quaternion(axis_local, angle) * sk.get_bone_pose_rotation(bone))


## Tourne un os pour que la direction `from` (monde) devienne `to`.
func _rotate_world_to(sk: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	if from.length() < 0.0001 or to.length() < 0.0001:
		return
	var q := Quaternion(from.normalized(), to.normalized())
	var pb := _parent_basis(sk, bone)
	var local_q := Quaternion(pb.inverse() * Basis(q) * pb)
	sk.set_bone_pose_rotation(bone, local_q * sk.get_bone_pose_rotation(bone))


func _parent_basis(sk: Skeleton3D, bone: int) -> Basis:
	var parent := sk.get_bone_parent(bone)
	return (sk.global_transform.basis * (sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis())).orthonormalized()
