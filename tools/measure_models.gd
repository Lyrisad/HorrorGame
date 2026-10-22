extends SceneTree
## Outil : taille (après mise à l'échelle) des modèles tels que la maison les pose.
## godot --headless --path . --script res://tools/measure_models.gd


func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var specs := []
	for slug in ["sf:toilet", "sf:sink_vanity", "sf:pizza_box", "sf:pizza_open", "sf:beer_bottle", "sf:beer_can", "sf:sneakers", "sf:sneakers_brown", "sf:towel_rail", "sf:towel_folded", "sf:coat_shelf", "sf:toilet_paper", "sf:flat_tv",
			"ClassicConsole_01", "ornate_mirror_01", "gaming_console", "gamepad", "vintage_electric_kettle", "pot_enamel_01", "potted_plant_02", "potted_plant_04", "hanging_picture_frame_01", "hanging_picture_frame_02", "hanging_picture_frame_03",
			"standing_picture_frame_01", "standing_picture_frame_02", "vintage_suitcase", "wicker_basket_02", "rubber_duck_toy", "plunger", "multi_cleaner_bottle", "bleach_bottle", "antique_ceramic_vase_01", "brass_candleholders", "jug_01",
			"wooden_cutting_board", "lemon", "plastic_broom", "throw_pillows_01", "electric_stove", "strawberry_chocolate_cake", "boombox", "wooden_ladder", "plastic_jerrycan", "industrial_caged_sconce", "utility_box_02",
			"modular_electric_cables", "korean_fire_extinguisher_01", "old_military_crate", "metal_toolbox", "rusted_wheel_rim_01", "pipe_wrench", "propane_tank", "plastic_crate_03", "wooden_military_crate", "hand_truck", "caged_hanging_light"]:
		specs.append([slug, {}])
	for s in specs:
		var h := B.model(root, s[0], Vector3.ZERO, 0.0, s[1])
		var sz: Vector3 = h.get_meta("size", Vector3.ZERO)
		print("%-30s size=(%.3f, %.3f, %.3f)" % [s[0], sz.x, sz.y, sz.z])
	return
	for pack in ["res://assets/sketchfab/flat_tv/flat_tv.glb", "res://assets/sketchfab/kitchen_cabinets/kitchen_cabinets.glb", "res://assets/sketchfab/coat_shelf/coat_shelf.glb", "res://assets/sketchfab/sneakers/sneakers.glb", "res://assets/sketchfab/pizza_open/pizza_open.glb"]:
		var inst: Node3D = (load(pack) as PackedScene).instantiate()
		print("== ", pack)
		var n: Node = inst
		while n.get_child_count() == 1 and not (n.get_child(0) is MeshInstance3D):
			n = n.get_child(0)
		for c in n.get_children():
			if not (c is Node3D):
				continue
			var holder := Node3D.new()
			var dup: Node3D = c.duplicate()
			holder.add_child(dup)
			dup.transform = B._relative_xform(inst, c)
			var bb := B.local_aabb(holder)
			print("   %-40s min=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f)" % [c.name, bb.position.x, bb.position.y, bb.position.z, bb.size.x, bb.size.y, bb.size.z])
			holder.free()
		inst.free()
	quit()
