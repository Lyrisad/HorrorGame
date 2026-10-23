class_name BreathModifier
extends SkeletonModifier3D
## Respiration procédurale par-dessus une pose figée (un blessé adossé au mur) :
## la poitrine se soulève par à-coups, la tête dodeline ou retombe sur la poitrine.

var chest := -1
var head := -1
var forward_ref: Node3D = null  ## nœud dont le -Z donne « devant » (l'Actor)
var rate := 0.32  ## respirations par seconde
var depth := 1.0  ## 0 = ne respire plus
var droop := 0.0  ## 0..1 : la tête tombe en avant
var _t := 0.0


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or chest < 0:
		return
	_t += delta * rate * TAU
	# souffle court et irrégulier
	var b := maxf(0.0, sin(_t)) * (0.75 + 0.25 * sin(_t * 0.37)) * depth
	var right := forward_ref.global_basis.x if forward_ref != null else Vector3.RIGHT
	_rotate_world(sk, chest, right, b * 0.045)
	if head >= 0:
		_rotate_world(sk, head, right, -droop * 0.6 + b * 0.025)


## Tourne un os autour d'un axe donné dans le repère du monde.
func _rotate_world(sk: Skeleton3D, bone: int, axis_world: Vector3, angle: float) -> void:
	if absf(angle) < 0.0001:
		return
	var parent := sk.get_bone_parent(bone)
	var pb := (sk.global_transform.basis * (sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis())).orthonormalized()
	var axis_local := (pb.inverse() * axis_world).normalized()
	sk.set_bone_pose_rotation(bone, Quaternion(axis_local, angle) * sk.get_bone_pose_rotation(bone))
