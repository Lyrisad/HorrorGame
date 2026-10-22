extends Node
## Outil : vues de contrôle de la voiture (extérieur éclairé + intérieur), balais au repos et en course.
## godot --path . res://tools/render_car.tscn -- --out=<dossier> [--b=0,0.5,1]

var out_dir := "user://car_renders"
var bs: PackedFloat32Array = [0.0, 0.5, 1.0]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--b="):
			bs = PackedFloat32Array()
			for t in a.substr(4).split(","):
				bs.append(float(t))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var vp := SubViewport.new()
	vp.size = Vector2i(900, 600)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.5, 0.55)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.8)
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	vp.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	floor_mi.mesh = pm
	vp.add_child(floor_mi)
	var car := CarRig.new()
	vp.add_child(car)
	car.set_process(false)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	var views := {
		"side": [Vector3(-4.2, 1.6, -0.6), Vector3(0, 1.0, -0.6)],
		"front": [Vector3(-2.2, 2.4, -4.2), Vector3(0, 1.0, -0.8)],
		"top": [Vector3(0, 3.6, -1.8), Vector3(0, 1.0, -0.85)],
		"inside": [CarRig.SEAT, CarRig.SEAT + Vector3(0.12, -0.08, -1.0)],
		"close": [Vector3(-1.3, 1.9, -2.7), Vector3(-0.1, 0.95, -1.1)],
		"closeside": [Vector3(-1.6, 1.2, -1.5), Vector3(-0.3, 0.95, -1.1)],
	}
	for b in bs:
		car._place_wipers(b)
		car.windshield_mat.set_shader_parameter("wipe_t", 3.0)
		for v in views:
			var p: Array = views[v]
			cam.fov = 70.0 if v != "inside" else 78.0
			cam.near = 0.02
			cam.look_at_from_position(p[0], p[1])
			for i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("%s/%s_b%d.png" % [out_dir, v, int(b * 100)])
	get_tree().quit()
