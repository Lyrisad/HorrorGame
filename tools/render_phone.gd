extends Node
## Outil : captures de l'écran du téléphone pendant une réponse tapée (barre de saisie, clavier).
## godot --path . res://tools/render_phone.tscn -- --out=<dossier>

var out_dir := "user://phone_renders"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	_run.call_deferred()


func _shot(ph: PhoneUI, name: String) -> void:
	await RenderingServer.frame_post_draw
	ph.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var ph := PhoneUI.new()
	add_child(ph)
	await get_tree().process_frame
	ph.set_time("23:41")
	ph._add_to_thread("Max", "t'es où ?? 🍕", false)
	ph._add_to_thread("Max", "on t'attend pour lancer le film", false)
	ph.open_chat("Max")
	for i in 10:
		await get_tree().process_frame
	await _shot(ph, "0_idle")
	ph.type_reply("j'arrive, j'arrive… 10 min")
	await get_tree().create_timer(0.2).timeout
	await _shot(ph, "1_tap")
	await get_tree().create_timer(0.6).timeout
	await _shot(ph, "2_kb_up")
	await get_tree().create_timer(1.6).timeout
	await _shot(ph, "3_typing")
	await get_tree().create_timer(2.4).timeout
	await _shot(ph, "4_sent")
	await get_tree().create_timer(1.6).timeout
	await _shot(ph, "5_closed")
	ph.call_contact("Karim")
	await get_tree().create_timer(0.5).timeout
	await _shot(ph, "6_call")
	get_tree().quit()
