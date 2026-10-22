extends Node
## Gestion du son : charge les .wav générés (assets/audio), joue des sons 2D / 3D,
## des boucles d'ambiance, et pilote les bus d'effets (réverbération, étouffement).

const DIR := "res://assets/audio/"

var _cache := {}
var _reverb: AudioEffectReverb
var _world_lowpass: AudioEffectLowPassFilter
var _amb_lowpass: AudioEffectLowPassFilter
var _master_lowpass: AudioEffectLowPassFilter
var _music_lowpass: AudioEffectLowPassFilter

# --- micro du joueur : seul son NIVEAU est mesuré (rien n'est enregistré ni envoyé)
var mic_db := -90.0  ## niveau actuel de la voix (dBFS)
var mic_voice := 0.0  ## 0..1 : au-dessus du bruit de fond de la pièce = Théo « parle »
var mic_floor := -60.0  ## bruit de fond de la pièce, suivi lentement
var debug_mic_db := -999.0  ## tests : niveau imposé à la place du vrai micro
var _mic_capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	# --nomic : jamais de micro pendant les tests automatiques
	if not "--nomic" in OS.get_cmdline_user_args():
		_setup_mic()


func _setup_mic() -> void:
	_add_bus("Mic")
	var i := _idx("Mic")
	_mic_capture = AudioEffectCapture.new()
	_mic_capture.buffer_length = 0.2
	AudioServer.add_bus_effect(i, _mic_capture)
	# on ne doit pas s'entendre soi-même : le bus est réduit au silence après la mesure
	AudioServer.set_bus_volume_db(i, -80.0)
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "Mic"
	add_child(_mic_player)


## Choisit le micro (nom tel que listé par AudioServer.get_input_device_list()).
func set_mic_device(device_name: String) -> void:
	if _mic_player == null:
		return
	if not device_name in AudioServer.get_input_device_list():
		device_name = "Default"
	if AudioServer.input_device != device_name:
		AudioServer.input_device = device_name
		if _mic_player.playing:
			_mic_player.stop()
			_mic_player.play()
		mic_floor = -60.0


## Niveau du micro pour les vumètres (0..1, -60 dB → 0, -10 dB → 1).
func mic_level01() -> float:
	return clampf((mic_db + 60.0) / 50.0, 0.0, 1.0)


## Allume / coupe l'écoute du micro (réglage « Micro »).
func set_mic_enabled(on: bool) -> void:
	if _mic_player == null:
		return
	if on and not _mic_player.playing:
		_mic_player.play()
	elif not on and _mic_player.playing:
		_mic_player.stop()
		mic_db = -90.0
		mic_voice = 0.0


func mic_active() -> bool:
	return debug_mic_db > -999.0 or (_mic_player != null and _mic_player.playing)


func _process(delta: float) -> void:
	var db := -90.0
	if debug_mic_db > -999.0:
		db = debug_mic_db
	elif _mic_capture != null and _mic_player.playing:
		var n := _mic_capture.get_frames_available()
		if n <= 0:
			return
		var buf := _mic_capture.get_buffer(n)
		# un échantillon sur 4 suffit pour un niveau (et ça coûte 4 fois moins)
		var sum := 0.0
		var count := 0
		for i in range(0, buf.size(), 4):
			var f := buf[i]
			sum += f.x * f.x + f.y * f.y
			count += 1
		db = linear_to_db(sqrt(sum / (2.0 * maxf(count, 1))) + 1e-6)
	else:
		mic_voice = 0.0
		return
	mic_db = lerpf(mic_db, db, 1.0 - exp(-20.0 * delta)) if db < mic_db else db
	# bruit de fond : descend vite vers les silences, remonte très lentement (une voix ne le relève pas)
	if mic_db < mic_floor:
		mic_floor = lerpf(mic_floor, mic_db, 1.0 - exp(-2.0 * delta))
	else:
		mic_floor = minf(mic_floor + delta * 0.4, -20.0)
	# avec des haut-parleurs le micro capte aussi le jeu : plus le jeu est fort, plus il faut parler fort
	var duck := maxf(0.0, master_level() - 0.7) * 25.0
	var above := mic_db - maxf(mic_floor, -62.0) - 10.0 - duck
	var sens := float(Game.settings.get("mic_sens", 1.0)) if Game.has_method("set_setting") else 1.0
	mic_voice = clampf(above * sens / 30.0, 0.0, 1.0) if mic_db > -58.0 else 0.0


func _setup_buses() -> void:
	# Master : filtre global (quand on est assommé) + limiteur (saturation du micro de la caméra).
	_master_lowpass = AudioEffectLowPassFilter.new()
	_master_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(0, _master_lowpass)
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.3
	limiter.pre_gain_db = 1.5
	AudioServer.add_bus_effect(0, limiter)

	_add_bus("World")
	_reverb = AudioEffectReverb.new()
	_reverb.room_size = 0.4
	_reverb.damping = 0.6
	_reverb.spread = 0.8
	_reverb.dry = 1.0
	_reverb.wet = 0.12
	AudioServer.add_bus_effect(_idx("World"), _reverb)
	_world_lowpass = AudioEffectLowPassFilter.new()
	_world_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(_idx("World"), _world_lowpass)

	_add_bus("Ambience")
	_amb_lowpass = AudioEffectLowPassFilter.new()
	_amb_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(_idx("Ambience"), _amb_lowpass)

	_add_bus("Music")
	_music_lowpass = AudioEffectLowPassFilter.new()
	_music_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(_idx("Music"), _music_lowpass)

	_add_bus("UI")


func _add_bus(bus_name: String) -> void:
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")


func _idx(bus_name: String) -> int:
	return AudioServer.get_bus_index(bus_name)


# ------------------------------------------------------------------ flux
func stream(sound_name: String, looped := false) -> AudioStream:
	var key := sound_name + ("#loop" if looped else "")
	if _cache.has(key):
		return _cache[key]
	var path := DIR + sound_name + ".wav"
	if not ResourceLoader.exists(path):
		push_warning("Son introuvable : " + sound_name)
		return null
	var s: AudioStream = load(path)
	if looped and s is AudioStreamWAV:
		var w: AudioStreamWAV = s.duplicate()
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate) - 1
		s = w
	_cache[key] = s
	return s


func variant(prefix: String, count: int) -> String:
	return "%s_%d" % [prefix, randi() % count]


func _parent_for(parent: Node) -> Node:
	if parent != null:
		return parent
	if Game.level != null and is_instance_valid(Game.level):
		return Game.level
	return self


# ------------------------------------------------------------------ lecture
## Son non spatialisé (souffle, voix intérieure, interface, jumpscares).
func play(sound_name: String, volume_db := 0.0, pitch := 1.0, bus := "World", parent: Node = null) -> AudioStreamPlayer:
	var s := stream(sound_name)
	if s == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = bus
	_parent_for(parent).add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	return p


## Son spatialisé ponctuel à une position du monde.
func play_at(sound_name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, unit_size := 4.0, max_distance := 60.0, parent: Node = null) -> AudioStreamPlayer3D:
	var s := stream(sound_name)
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = unit_size
	p.max_distance = max_distance
	p.attenuation_filter_cutoff_hz = 7000.0
	p.attenuation_filter_db = -18.0
	p.bus = "World"
	_parent_for(parent).add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
	return p


## Boucle non spatialisée (pluie, nappes). À arrêter / libérer soi-même (ou libérée avec le niveau).
func loop(sound_name: String, volume_db := 0.0, bus := "Ambience", parent: Node = null) -> AudioStreamPlayer:
	var s := stream(sound_name, true)
	if s == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	p.bus = bus
	_parent_for(parent).add_child(p)
	p.play()
	return p


## Boucle spatialisée attachée à un objet (enceinte, néon qui grésille, souffle de la créature...).
func loop_at(sound_name: String, target: Node3D, volume_db := 0.0, unit_size := 4.0, max_distance := 40.0, bus := "World") -> AudioStreamPlayer3D:
	var s := stream(sound_name, true)
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.max_distance = max_distance
	p.attenuation_filter_cutoff_hz = 6000.0
	p.attenuation_filter_db = -20.0
	p.bus = bus
	target.add_child(p)
	p.play(randf() * maxf(s.get_length() - 0.1, 0.0))
	return p


func fade(p: Node, to_db: float, duration: float, free_after := false) -> void:
	if p == null or not is_instance_valid(p):
		return
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", to_db, duration)
	if free_after:
		tw.tween_callback(p.queue_free)


# ------------------------------------------------------------------ bus
func set_reverb(room_size: float, wet: float, damping := 0.5) -> void:
	_reverb.room_size = room_size
	_reverb.wet = wet
	_reverb.damping = damping


func muffle_world(cutoff_hz: float, duration := 0.0) -> void:
	_tween_cutoff(_world_lowpass, cutoff_hz, duration)


func muffle_ambience(cutoff_hz: float, duration := 0.0) -> void:
	_tween_cutoff(_amb_lowpass, cutoff_hz, duration)


func muffle_master(cutoff_hz: float, duration := 0.0) -> void:
	_tween_cutoff(_master_lowpass, cutoff_hz, duration)


func muffle_music(cutoff_hz: float, duration := 0.0) -> void:
	_tween_cutoff(_music_lowpass, cutoff_hz, duration)


func _tween_cutoff(fx: AudioEffectLowPassFilter, cutoff_hz: float, duration: float) -> void:
	if duration <= 0.0:
		fx.cutoff_hz = cutoff_hz
		return
	var tw := create_tween()
	tw.tween_property(fx, "cutoff_hz", cutoff_hz, duration)


func reset_effects() -> void:
	muffle_world(20000.0)
	muffle_ambience(20000.0)
	muffle_master(20000.0)
	muffle_music(20000.0)
	set_reverb(0.4, 0.12)


func set_master_volume(v: float) -> void:
	AudioServer.set_bus_volume_linear(0, clampf(v, 0.0, 1.0))


## Volume de la musique (enceinte de la soirée, autoradio) : 0 = coupée.
func set_music_volume(v: float) -> void:
	AudioServer.set_bus_volume_linear(_idx("Music"), clampf(v, 0.0, 1.0))
	AudioServer.set_bus_mute(_idx("Music"), v <= 0.001)


## Niveau sonore actuel du bus principal (0..1) : alimente le vumètre "MIC" de la caméra.
func master_level() -> float:
	var db := maxf(AudioServer.get_bus_peak_volume_left_db(0, 0), AudioServer.get_bus_peak_volume_right_db(0, 0))
	return clampf((db + 48.0) / 48.0, 0.0, 1.0)
