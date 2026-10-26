class_name Actor
extends Node3D
## Personnage animé réaliste (assets/characters/<nom>/<nom>.glb) :
## maillage riggé + animations de capture de mouvement (CMU) converties par tools/blender_scripts.
## Convention : l'Actor regarde vers -Z (comme les caméras Godot).

const NON_LOOP := ["grab", "dead", "strike", "pickup", "screech"]
## vitesse au sol (m/s) d'un cycle de marche lu à vitesse 1 ; remplacée par la vitesse mesurée
## à la conversion (<nom>.anims.json) quand elle existe
const NOMINAL_SPEED := {"walk": 1.18, "run": 2.9, "crouch_walk": 0.55, "drag": 0.34}

var character := ""
var model: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
var current := ""
var speed_scale := 1.0
var _clip_speed := {}


static func create(parent: Node, char_name: String, pos := Vector3.ZERO, yaw := 0.0) -> Actor:
	var a := Actor.new()
	a.character = char_name
	a.name = char_name.capitalize()
	a.position = pos
	a.rotation.y = yaw
	parent.add_child(a)
	return a


func _ready() -> void:
	var ps: PackedScene = load("res://assets/characters/%s/%s.glb" % [character, character])
	model = ps.instantiate()
	add_child(model)
	model.rotation.y = PI  # les .glb regardent vers +Z
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = model.find_child("*", true, false) as Skeleton3D
	for n in model.find_children("*", "Skeleton3D", true, false):
		skeleton = n
		break
	if anim != null:
		for a in anim.get_animation_list():
			var res := anim.get_animation(a)
			res.loop_mode = Animation.LOOP_NONE if a in NON_LOOP else Animation.LOOP_LINEAR
		anim.playback_default_blend_time = 0.25
	var info := "res://assets/characters/%s/%s.anims.json" % [character, character]
	if FileAccess.file_exists(info):
		var clips: Variant = JSON.parse_string(FileAccess.get_file_as_string(info))
		if clips is Array:
			for c in clips:
				if float(c.get("speed", 0.0)) > 0.2:
					_clip_speed[str(c["name"])] = float(c["speed"])
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func has_anim(a: String) -> bool:
	return anim != null and anim.has_animation(a)


## Joue une animation (fondu enchaîné).
func play(a: String, blend := 0.3, speed := 1.0) -> void:
	if anim == null or not anim.has_animation(a):
		return
	speed_scale = speed
	anim.speed_scale = speed
	if current != a or not anim.is_playing():
		anim.play(a, blend)
		current = a


## Choisit et cadence un cycle de marche d'après la vitesse réelle (m/s).
## `max_scale` évite les jambes qui s'agitent trop vite ; `reverse` = marche à reculons.
func locomote(cycle: String, ground_speed: float, idle := "idle", blend := 0.3, max_scale := 2.5, reverse := false) -> void:
	if ground_speed < 0.08:
		play(idle, blend)
		return
	var nominal: float = _clip_speed.get(cycle, NOMINAL_SPEED.get(cycle, 1.0))
	var k := clampf(ground_speed / nominal, 0.4, max_scale)
	play(cycle, blend, -k if reverse else k)


## Index d'os par nom "simplifié" (ignore 'Bip01 ', 'mixamorig:' et suffixes numériques).
func bone(core: String) -> int:
	if skeleton == null:
		return -1
	for i in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(i)
		var c := n.get_slice(":", n.get_slice_count(":") - 1)
		if c.begins_with("Bip01 "):
			c = c.substr(6)
		var parts := c.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			c = parts[0]
		# l'import glTF remplace "mixamorig:" par "mixamorig_"
		if c.begins_with("mixamorig_"):
			c = c.substr(10)
		elif c.begins_with("mixamorig"):
			c = c.substr(9)
		if c == core:
			return i
	return -1


## Position monde d'un os.
func bone_position(core: String) -> Vector3:
	var b := bone(core)
	if b < 0:
		return global_position + Vector3(0, 1.6, 0)
	return skeleton.global_transform * skeleton.get_bone_global_pose(b).origin


## Hauteur (monde) du point le plus bas du maillage dans la pose actuelle, skinning calculé
## sur le CPU : sert à poser exactement un corps au sol (les os sont à l'intérieur du corps).
## `percentile` > 0 : hauteur sous laquelle se trouve cette part des sommets (ex. 0,06) — pour un
## corps allongé, c'est le dos / le ventre qui touche le sol, pas une main qui dépasse dessous.
func lowest_point(percentile := 0.0) -> float:
	if anim != null:
		anim.advance(0.0)
	var low := INF
	var heights := PackedFloat32Array()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if mi.skin == null or skel == null or arr[Mesh.ARRAY_BONES] == null:
				for i in range(0, verts.size(), 3):
					var y0 := (mi.global_transform * verts[i]).y
					low = minf(low, y0)
					heights.append(y0)
				continue
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(verts.size(), 1)
			var mats: Array[Transform3D] = []
			for b in mi.skin.get_bind_count():
				var bone := mi.skin.get_bind_bone(b)
				if bone < 0:
					bone = skel.find_bone(mi.skin.get_bind_name(b))
				mats.append(skel.global_transform * skel.get_bone_global_pose(maxi(bone, 0)) * mi.skin.get_bind_pose(b))
			for i in range(0, verts.size(), 2):
				var p := Vector3.ZERO
				for k in per:
					var w := weights[i * per + k]
					if w > 0.0:
						p += (mats[bones[i * per + k]] * verts[i]) * w
				low = minf(low, p.y)
				heights.append(p.y)
	if percentile > 0.0 and heights.size() > 10:
		heights.sort()
		return heights[int(heights.size() * percentile)]
	return low


## Attache un objet à un os en le plaçant dans le repère du personnage
## (offset = position relative à l'os, exprimée dans le repère "Actor" : -Z devant, +Y haut).
func attach(core: String, node: Node3D, offset := Vector3.ZERO, extra_basis := Basis()) -> BoneAttachment3D:
	var b := bone(core)
	if b < 0:
		push_warning("os introuvable : " + core)
		add_child(node)
		return null
	var att := BoneAttachment3D.new()
	att.bone_idx = b
	skeleton.add_child(att)
	att.add_child(node)
	# repère de l'os au repos, exprimé dans le repère de l'Actor
	var rest_in_skel := skeleton.get_bone_global_rest(b)
	var skel_in_actor := B._relative_xform(self, skeleton)
	var rest_in_actor := skel_in_actor * rest_in_skel
	var desired := Transform3D(extra_basis, rest_in_actor.origin + offset)
	node.transform = rest_in_actor.affine_inverse() * desired
	return att


## Assombrit / teinte les matériaux dont le nom contient `match`.
func tint(match: String, color: Color, roughness := -1.0) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s)
			if mat == null or not (mat is StandardMaterial3D):
				continue
			if match != "" and not (mat.resource_name.to_lower().contains(match) or m.name.to_lower().contains(match)):
				continue
			var nm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			nm.albedo_color = nm.albedo_color * color
			if roughness >= 0.0:
				nm.roughness = roughness
			m.set_surface_override_material(s, nm)


## Remplace la texture des matériaux dont le nom contient `match` (une autre tenue sur le même modèle).
func retexture(match: String, texture: Texture2D, roughness := -1.0) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s)
			if mat == null or not (mat is StandardMaterial3D) or not mat.resource_name.to_lower().contains(match):
				continue
			var nm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			nm.albedo_texture = texture
			nm.albedo_color = Color.WHITE
			if roughness >= 0.0:
				nm.roughness = roughness
			m.set_surface_override_material(s, nm)


## Rend invisibles les surfaces dont le matériau contient `match` (ex. casque).
func hide_material(match: String) -> void:
	var invisible := StandardMaterial3D.new()
	invisible.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	invisible.albedo_color = Color(0, 0, 0, 0)
	invisible.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			if mat != null and mat.resource_name.to_lower().contains(match):
				m.set_surface_override_material(s, invisible)


func set_layers(mask: int) -> void:
	B.set_layers(self, mask)


func set_shadows(on: bool) -> void:
	B.set_shadows(self, on)
