extends SceneTree
## Outil : gros plan de la tête du kidnappeur (masque à gaz) de face et de profil.
## godot --path . --script res://tools/render_kidnapper.gd -- --out=<dossier> --off=x,y,z --h=0.34 --pitch=0


var out_dir := "user://kid"
var off := Vector3(0, 0.1, -0.04)
var h := 0.34
var pitch := 0.0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--off="):
			var p := a.substr(6).split(",")
			off = Vector3(float(p[0]), float(p[1]), float(p[2]))
		elif a.begins_with("--h="):
			h = float(a.substr(4))
		elif a.begins_with("--pitch="):
			pitch = float(a.substr(8))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.37, 0.4)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 35
	vp.add_child(cam)
	cam.current = true
	var k := Actor.create(vp, "kidnapper")
	k.play("idle", 0.0, 0.0)
	k.hide_material("helmet")
	await process_frame
	var mask := Node3D.new()
	B.model(mask, "sf:gasmask_gp5", Vector3.ZERO, 180.0, {"remove": ["Icosphere"], "height": h, "rot": Vector3(pitch, 0, 0)})
	k.attach("Head", mask, off)
	await process_frame
	var head := k.bone_position("Head")
	for view in ["front", "side", "full"]:
		match view:
			"front":
				cam.look_at_from_position(head + Vector3(0, 0.05, -1.2), head + Vector3(0, 0.05, 0))
			"side":
				cam.look_at_from_position(head + Vector3(1.2, 0.05, 0), head + Vector3(0, 0.05, 0))
			"full":
				cam.look_at_from_position(Vector3(0.8, 1.2, -4.0), Vector3(0, 1.0, 0))
		await process_frame
		await process_frame
		await process_frame
		vp.get_texture().get_image().save_png("%s/kid_%s.png" % [out_dir, view])
	print("rendus terminés")
	quit()
