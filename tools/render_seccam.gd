extends Node
## Outil : caméra de surveillance vissée à un mur, la tête tournée vers plusieurs points (contrôle visuel).
## godot --path . res://tools/render_seccam.tscn -- --out=<dossier>

func _ready() -> void:
	var out := "user://seccam"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var vp := SubViewport.new()
	vp.size = Vector2i(700, 520)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.22, 0.25)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.5)
	we.environment = e
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 40, 0)
	vp.add_child(sun)
	# mur (face +Z) à z = 0
	var wall := B.box(vp, Vector3(3, 2, 0.2), Vector3(0, 2, -0.1), B.color_mat(Color(0.45, 0.42, 0.4), 0.9), false)
	var c := SecurityCamera.create(vp, Vector3(0, 2.4, 0.3), Vector3(0, -0.4, 1))
	await get_tree().process_frame
	c.attach_wall(Vector3(0, 2.4, 0), Vector3(0, 0, 1))
	var target := Node3D.new()
	vp.add_child(target)
	c.target = target
	c.tracking = true
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	cam.fov = 40
	var k := 0
	for t in [Vector3(0, 0, 4), Vector3(3, 0, 3), Vector3(-3, 0, 2), Vector3(0, 3.5, 4)]:
		target.global_position = t
		for i in 90:
			await get_tree().process_frame
		for view in [Vector3(1.6, 2.6, 1.6), Vector3(0.05, 2.5, 2.2)]:
			cam.look_at_from_position(view, Vector3(0, 2.4, 0.15))
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s/seccam_%d.png" % [out, k])
			k += 1
	get_tree().quit()
