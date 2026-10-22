extends Node
## Diagnostic du micro (niveaux seulement, rien n'est enregistré) : périphériques, données reçues, niveaux.
## godot --path . res://tools/mic_diag.tscn

func _ready() -> void:
	print("MICDIAG entrée activée (projet) : ", ProjectSettings.get_setting("audio/driver/enable_input", false))
	print("MICDIAG périphériques d'entrée : ", AudioServer.get_input_device_list())
	print("MICDIAG périphérique choisi : ", AudioServer.input_device, " · pilote audio : ", AudioServer.get_driver_name() if AudioServer.has_method("get_driver_name") else "?")
	print("MICDIAG Sound.mic_active() = ", Sound.mic_active())
	var dbs := []
	var frames := 0
	var t := 0.0
	var cap: AudioEffectCapture = Sound._mic_capture
	while t < 5.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		dbs.append(Sound.mic_db)
	frames = cap.get_frames_available() if cap != null else -1
	dbs.sort()
	print("MICDIAG niveaux sur 5 s : min %.1f dB · médiane %.1f dB · max %.1f dB · fond %.1f dB · voix max %.2f" % [dbs[0], dbs[dbs.size() / 2], dbs[-1], Sound.mic_floor, Sound.mic_voice])
	print("MICDIAG lecteur micro actif : ", Sound._mic_player.playing if Sound._mic_player != null else "aucun", " · trames en attente : ", frames)
	print("MICDIAG bus Mic : index ", AudioServer.get_bus_index("Mic"), " volume ", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Mic")), " dB, effets ", AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Mic")))
	get_tree().quit()
