class_name ScreenUI
extends CanvasLayer
## Tout ce qui s'affiche "hors caméra" : fondus, cartons de texte, documents lus,
## menu principal, chapitres, paramètres, pause et écran de mort.

signal document_closed

const CHAPTERS := [
	["drive", "I.   La route"],
	["house", "II.  La maison"],
	["sewer", "III. Sous la ville"],
	["ending", "IV.  Surface"],
]

var mono: SystemFont
var sans: SystemFont
var hand: SystemFont
var ui_theme: Theme

var fade_rect: ColorRect
var card_root: CenterContainer
var card_box: VBoxContainer
var doc_root: Control
var doc_panel: PanelContainer
var doc_text: RichTextLabel
var main_menu: Control
var menu_buttons: VBoxContainer
var chapters_panel: VBoxContainer
var editor_panel: VBoxContainer
var settings_main: VBoxContainer
var pause_menu: Control
var pause_buttons: VBoxContainer
var settings_pause: VBoxContainer
var death_menu: Control
var death_sub: Label
var document_open := false
var loading_label: Label
var cover_rect: ColorRect
var controls_menu: Control  ## Paramètres → Touches (par-dessus le menu principal ou la pause)
var _bind_buttons := {}  ## action → bouton qui affiche sa touche
var _rebinding := ""  ## action en attente d'une nouvelle touche
var _controls_hint: Label
var _doc_close: Label
var _menu_drone: AudioStreamPlayer


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	mono = SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "Monospace"])
	mono.font_weight = 700
	sans = SystemFont.new()
	sans.font_names = PackedStringArray(["Segoe UI", "Arial", "Sans-Serif"])
	hand = SystemFont.new()
	hand.font_names = PackedStringArray(["Segoe Print", "Ink Free", "Comic Sans MS", "Sans-Serif"])
	_build_theme()

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 1)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade_rect)
	# cache noir indépendant des fondus des niveaux (préchauffage pendant le chargement)
	cover_rect = ColorRect.new()
	cover_rect.color = Color(0, 0, 0, 1)
	cover_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_rect.visible = false
	add_child(cover_rect)

	card_root = CenterContainer.new()
	card_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_root.visible = false
	add_child(card_root)
	card_box = VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 14)
	card_box.custom_minimum_size.x = 1300
	card_root.add_child(card_box)

	loading_label = _title_label("CHARGEMENT DE L'ENREGISTREMENT…", 22, Color(0.75, 0.75, 0.75))
	loading_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	loading_label.position = Vector2(-620, -90)
	loading_label.size = Vector2(560, 40)
	loading_label.anchor_left = 1.0
	loading_label.anchor_top = 1.0
	loading_label.anchor_right = 1.0
	loading_label.anchor_bottom = 1.0
	loading_label.offset_left = -640
	loading_label.offset_top = -90
	loading_label.offset_right = -60
	loading_label.offset_bottom = -50
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	loading_label.visible = false
	add_child(loading_label)

	_build_document()
	_build_main_menu()
	_build_controls_menu()
	_build_pause_menu()
	_build_death_menu()


# ------------------------------------------------------------------ thème
func _build_theme() -> void:
	ui_theme = Theme.new()
	ui_theme.default_font = mono
	ui_theme.default_font_size = 26
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.border_color = Color(1, 1, 1, 0.45)
	normal.set_border_width_all(1)
	normal.content_margin_left = 30
	normal.content_margin_right = 30
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.1)
	hover.border_color = Color(1, 1, 1, 1)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1, 0.2, 0.2, 0.25)
	ui_theme.set_stylebox("normal", "Button", normal)
	ui_theme.set_stylebox("hover", "Button", hover)
	ui_theme.set_stylebox("pressed", "Button", pressed)
	ui_theme.set_stylebox("focus", "Button", hover)
	ui_theme.set_color("font_color", "Button", Color(0.92, 0.92, 0.92))
	ui_theme.set_color("font_hover_color", "Button", Color(1, 1, 1))
	ui_theme.set_color("font_color", "Label", Color(0.85, 0.85, 0.85))


func _title_label(text: String, size: int, color := Color(0.95, 0.95, 0.95), font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font = font if font != null else mono
	ls.font_size = size
	ls.font_color = color
	l.label_settings = ls
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(560, 0)
	b.pressed.connect(func() -> void:
		Sound.play("flashlight_click", -8.0, 1.0, "UI")
		cb.call())
	return b


func _fullscreen_menu() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.theme = ui_theme
	c.visible = false
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.86)
	c.add_child(bg)
	add_child(c)
	return c


# ------------------------------------------------------------------ menu principal
func _build_main_menu() -> void:
	main_menu = _fullscreen_menu()
	(main_menu.get_child(0) as ColorRect).color = Color(0.015, 0.015, 0.018, 1)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_menu.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	col.add_child(_title_label("PIÈCE À CONVICTION N° 47", 20, Color(1, 0.23, 0.19)))
	var title := _title_label("DERNIER\nENREGISTREMENT", 92)
	title.label_settings.shadow_size = 0
	title.label_settings.shadow_color = Color(1, 0, 0.15, 0.35)
	title.label_settings.shadow_offset = Vector2(5, 0)
	col.add_child(title)
	col.add_child(Control.new())

	menu_buttons = VBoxContainer.new()
	menu_buttons.add_theme_constant_override("separation", 12)
	col.add_child(menu_buttons)
	menu_buttons.add_child(_button("▶  LIRE L'ENREGISTREMENT", func() -> void: Game.new_game()))
	menu_buttons.add_child(_button("CHAPITRES", func() -> void: _show_panel("chapters")))
	menu_buttons.add_child(_button("ÉDITEUR DE CARTES", func() -> void: _show_panel("editor")))
	menu_buttons.add_child(_button("PARAMÈTRES", func() -> void: _show_panel("settings")))
	menu_buttons.add_child(_button("QUITTER", func() -> void: get_tree().quit()))

	chapters_panel = VBoxContainer.new()
	chapters_panel.add_theme_constant_override("separation", 12)
	chapters_panel.visible = false
	col.add_child(chapters_panel)

	editor_panel = VBoxContainer.new()
	editor_panel.add_theme_constant_override("separation", 12)
	editor_panel.visible = false
	col.add_child(editor_panel)
	editor_panel.add_child(_title_label("Placez vous-même les objets du décor.
Vos modifications sont gardées pour les prochaines parties.", 18, Color(0.7, 0.7, 0.7)))
	editor_panel.add_child(_button("MAISON DE MAX", func() -> void: Game.start_level("house", {"editor": true})))
	editor_panel.add_child(_button("ÉGOUTS", func() -> void: Game.start_level("sewer", {"editor": true})))
	editor_panel.add_child(_button("FORÊT (SURFACE)", func() -> void: Game.start_level("ending", {"editor": true})))
	editor_panel.add_child(_button("RETOUR", func() -> void: _show_panel("buttons")))

	settings_main = _build_settings(func() -> void: _show_panel("buttons"))
	settings_main.visible = false
	col.add_child(settings_main)

	_controls_hint = _title_label("", 18, Color(0.6, 0.6, 0.6))
	col.add_child(_controls_hint)
	_refresh_controls_hint()
	col.add_child(_title_label("Jeu d'horreur  ·  casque fortement recommandé", 15, Color(0.45, 0.45, 0.45)))


func _refresh_controls_hint() -> void:
	var k := func(a: String) -> String: return Game.key_label(a)
	_controls_hint.text = "%s %s %s %s  se déplacer   ·   Souris  regarder   ·   %s  courir\n%s  s'accroupir   ·   %s  lampe torche   ·   %s  interagir   ·   %s  objectif   ·   F8  éditeur de carte" % [
		k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right"), k.call("run"),
		k.call("crouch"), k.call("flashlight"), k.call("interact"), k.call("objective")]


# ------------------------------------------------------------------ touches
func _build_controls_menu() -> void:
	controls_menu = _fullscreen_menu()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	controls_menu.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size.x = 640
	center.add_child(col)
	col.add_child(_title_label("TOUCHES", 34))
	col.add_child(_title_label("Clique sur une action, puis appuie sur la nouvelle touche (ou un bouton de la souris).\nÉchap : annuler. Une touche déjà prise échange sa place.", 16, Color(0.65, 0.65, 0.65)))
	for e in Game.REBINDABLE:
		var action: String = e[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		col.add_child(row)
		var name_lbl := Label.new()
		name_lbl.text = e[1]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var b := Button.new()
		b.custom_minimum_size = Vector2(240, 0)
		b.pressed.connect(func() -> void:
			Sound.play("flashlight_click", -8.0, 1.0, "UI")
			_rebinding = action
			_refresh_bindings())
		row.add_child(b)
		_bind_buttons[action] = b
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	col.add_child(bottom)
	var reset := _button("RÉINITIALISER", func() -> void:
		_rebinding = ""
		Game.reset_keys()
		_refresh_bindings())
	reset.custom_minimum_size = Vector2(312, 0)
	bottom.add_child(reset)
	var back := _button("RETOUR", func() -> void: _close_controls())
	back.custom_minimum_size = Vector2(312, 0)
	bottom.add_child(back)


func show_controls() -> void:
	_rebinding = ""
	_refresh_bindings()
	move_child(controls_menu, get_child_count() - 1)  # par-dessus le menu pause aussi
	controls_menu.visible = true


func _close_controls() -> void:
	_rebinding = ""
	controls_menu.visible = false
	_refresh_controls_hint()


func _refresh_bindings() -> void:
	for action in _bind_buttons:
		(_bind_buttons[action] as Button).text = "…  appuie sur une touche  …" if action == _rebinding else Game.key_label(action)


## Pendant l'attente d'une touche : la prochaine touche (ou bouton de souris, sauf le clic gauche et la molette)
## devient celle de l'action. Échap annule.
func _capture_binding(event: InputEvent) -> bool:
	if _rebinding == "":
		return false
	var ev: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_rebinding = ""
			_refresh_bindings()
			return true
		var k := InputEventKey.new()
		k.physical_keycode = (event as InputEventKey).physical_keycode
		ev = k
	elif event is InputEventMouseButton and event.pressed:
		var bi := (event as InputEventMouseButton).button_index
		if bi in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return false
		var mb := InputEventMouseButton.new()
		mb.button_index = bi
		ev = mb
	if ev == null:
		return false
	Game.rebind(_rebinding, ev)
	Sound.play("ui_beep", -10.0, 1.2, "UI")
	_rebinding = ""
	_refresh_bindings()
	return true


func _show_panel(which: String) -> void:
	menu_buttons.visible = which == "buttons"
	chapters_panel.visible = which == "chapters"
	editor_panel.visible = which == "editor"
	settings_main.visible = which == "settings"
	if which == "chapters":
		for ch in chapters_panel.get_children():
			ch.queue_free()
		for entry in CHAPTERS:
			var id: String = entry[0]
			var b := _button(entry[1], func() -> void: Game.start_chapter(id))
			b.disabled = not Game.unlocked.has(id)
			if b.disabled:
				b.text = entry[1] + "   (verrouillé)"
			chapters_panel.add_child(b)
		chapters_panel.add_child(_button("RETOUR", func() -> void: _show_panel("buttons")))


func _build_settings(on_back: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size.x = 560
	box.add_child(_title_label("Sensibilité de la souris", 20))
	var sens := HSlider.new()
	sens.min_value = 0.2
	sens.max_value = 3.0
	sens.step = 0.05
	sens.value = Game.settings.get("sensitivity", 1.0)
	sens.value_changed.connect(func(v: float) -> void: Game.set_setting("sensitivity", v))
	box.add_child(sens)
	box.add_child(_title_label("Volume", 20))
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.02
	vol.value = Game.settings.get("volume", 0.8)
	vol.value_changed.connect(func(v: float) -> void: Game.set_setting("volume", v))
	box.add_child(vol)
	box.add_child(_title_label("Musique", 20))
	var mus := HSlider.new()
	mus.min_value = 0.0
	mus.max_value = 1.0
	mus.step = 0.02
	mus.value = Game.settings.get("music", 1.0)
	mus.value_changed.connect(func(v: float) -> void: Game.set_setting("music", v))
	box.add_child(mus)
	box.add_child(_title_label("Luminosité", 20))
	var bright := HSlider.new()
	bright.min_value = 0.6
	bright.max_value = 1.6
	bright.step = 0.02
	bright.value = Game.settings.get("brightness", 1.0)
	bright.value_changed.connect(func(v: float) -> void: Game.set_setting("brightness", v))
	box.add_child(bright)
	var mic := CheckButton.new()
	mic.text = "Micro : la créature entend ta voix"
	mic.button_pressed = Game.settings.get("mic", true)
	mic.toggled.connect(func(on: bool) -> void: Game.set_setting("mic", on))
	box.add_child(mic)
	var dev_row := HBoxContainer.new()
	dev_row.add_theme_constant_override("separation", 12)
	box.add_child(dev_row)
	var dev_lbl := Label.new()
	dev_lbl.text = "Micro utilisé"
	dev_row.add_child(dev_lbl)
	var dev := OptionButton.new()
	dev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dev.clip_text = true
	dev_row.add_child(dev)
	var fill_devices := func() -> void:
		dev.clear()
		var cur := str(Game.settings.get("mic_device", "Default"))
		var k := 0
		for d in AudioServer.get_input_device_list():
			dev.add_item("Par défaut (Windows)" if d == "Default" else d)
			dev.set_item_metadata(k, d)
			if d == cur:
				dev.select(k)
			k += 1
	fill_devices.call()
	dev.item_selected.connect(func(i: int) -> void: Game.set_setting("mic_device", str(dev.get_item_metadata(i))))
	# test en direct : parle, la barre doit bouger (rouge = la créature t'entendrait)
	var test := ProgressBar.new()
	test.min_value = 0.0
	test.max_value = 1.0
	test.show_percentage = false
	test.custom_minimum_size = Vector2(0, 14)
	var tb := StyleBoxFlat.new()
	tb.bg_color = Color(0.9, 0.9, 0.9)
	test.add_theme_stylebox_override("fill", tb)
	box.add_child(test)
	var test_hint := Label.new()
	test_hint.text = "Test : parle, la barre doit bouger (rouge = la créature t'entendrait)."
	test_hint.add_theme_font_size_override("font_size", 16)
	box.add_child(test_hint)
	var tick := Timer.new()
	tick.wait_time = 0.05
	tick.autostart = true
	tick.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_child(tick)
	tick.timeout.connect(func() -> void:
		if not box.is_visible_in_tree():
			return
		test.value = Sound.mic_level01() if Sound.mic_active() else 0.0
		tb.bg_color = Color(1.0, 0.3, 0.25) if Sound.mic_voice >= 0.12 else Color(0.9, 0.9, 0.9))
	box.add_child(_title_label("Sensibilité du micro", 20))
	var msens := HSlider.new()
	msens.min_value = 0.3
	msens.max_value = 2.5
	msens.step = 0.05
	msens.value = Game.settings.get("mic_sens", 1.0)
	msens.value_changed.connect(func(v: float) -> void: Game.set_setting("mic_sens", v))
	box.add_child(msens)
	var fs := CheckButton.new()
	fs.text = "Plein écran (F11)"
	fs.button_pressed = Game.settings.get("fullscreen", true)
	fs.toggled.connect(func(on: bool) -> void: Game.set_setting("fullscreen", on))
	box.add_child(fs)
	box.add_child(_button("TOUCHES", func() -> void: show_controls()))
	box.add_child(_button("RETOUR", on_back))
	box.visibility_changed.connect(func() -> void:
		if box.visible:
			sens.value = Game.settings.get("sensitivity", 1.0)
			vol.value = Game.settings.get("volume", 0.8)
			mus.value = Game.settings.get("music", 1.0)
			mic.set_pressed_no_signal(Game.settings.get("mic", true))
			fill_devices.call()
			msens.value = Game.settings.get("mic_sens", 1.0)
			bright.value = Game.settings.get("brightness", 1.0)
			fs.set_pressed_no_signal(Game.settings.get("fullscreen", true)))
	return box


func show_main_menu() -> void:
	hide_menus()
	main_menu.visible = true
	_show_panel("buttons")
	fade_rect.color.a = 1.0
	if _menu_drone == null or not is_instance_valid(_menu_drone):
		_menu_drone = Sound.loop("drone_house", -10.0, "UI", self)


func _stop_menu_drone() -> void:
	if _menu_drone != null and is_instance_valid(_menu_drone):
		Sound.fade(_menu_drone, -60.0, 1.0, true)
	_menu_drone = null


# ------------------------------------------------------------------ pause
func _build_pause_menu() -> void:
	pause_menu = _fullscreen_menu()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	col.add_child(_title_label("❚❚  LECTURE EN PAUSE", 40))
	col.add_child(Control.new())
	pause_buttons = VBoxContainer.new()
	pause_buttons.add_theme_constant_override("separation", 12)
	col.add_child(pause_buttons)
	pause_buttons.add_child(_button("▶  REPRENDRE", func() -> void: Game.resume()))
	pause_buttons.add_child(_button("PARAMÈTRES", func() -> void:
		pause_buttons.visible = false
		settings_pause.visible = true))
	pause_buttons.add_child(_button("RECOMMENCER LE CHAPITRE", func() -> void: Game.restart_level()))
	pause_buttons.add_child(_button("MENU PRINCIPAL", func() -> void: Game.quit_to_menu()))
	pause_buttons.add_child(_button("QUITTER LE JEU", func() -> void: get_tree().quit()))
	settings_pause = _build_settings(func() -> void:
		settings_pause.visible = false
		pause_buttons.visible = true)
	settings_pause.visible = false
	col.add_child(settings_pause)


func show_pause(on: bool) -> void:
	pause_menu.visible = on
	pause_buttons.visible = true
	settings_pause.visible = false


# ------------------------------------------------------------------ mort
func _build_death_menu() -> void:
	death_menu = _fullscreen_menu()
	(death_menu.get_child(0) as ColorRect).color = Color(0, 0, 0, 0.92)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_menu.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	center.add_child(col)
	col.add_child(_title_label("FIN DE L'ENREGISTREMENT", 64, Color(1, 0.2, 0.17)))
	death_sub = _title_label("", 22, Color(0.7, 0.7, 0.7))
	col.add_child(death_sub)
	col.add_child(Control.new())
	col.add_child(_button("▶  REPRENDRE LA LECTURE", func() -> void: Game.retry_from_checkpoint()))
	col.add_child(_button("MENU PRINCIPAL", func() -> void: Game.quit_to_menu()))


func show_death(subtitle_text: String) -> void:
	death_sub.text = subtitle_text
	death_menu.visible = true
	death_menu.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(death_menu, "modulate:a", 1.0, 1.5)


func hide_menus() -> void:
	main_menu.visible = false
	pause_menu.visible = false
	death_menu.visible = false
	_stop_menu_drone()


func set_loading(on: bool) -> void:
	loading_label.visible = on


func set_cover(on: bool) -> void:
	cover_rect.visible = on


# ------------------------------------------------------------------ fondus & cartons
func fade_to(alpha: float, duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", alpha, maxf(duration, 0.01))
	await tw.finished


## Affiche des lignes de texte une à une sur fond noir.
## Chaque entrée : "texte" ou {"text": ..., "style": "title"|"red"|"small"|"normal"}.
func show_card(lines: Array, line_delay := 1.3, hold := 3.0, fade_out := 1.2) -> void:
	for c in card_box.get_children():
		c.queue_free()
	card_root.visible = true
	card_root.modulate.a = 1.0
	var labels: Array[Label] = []
	for entry in lines:
		var text := ""
		var style := "normal"
		if entry is Dictionary:
			text = entry.get("text", "")
			style = entry.get("style", "normal")
		else:
			text = str(entry)
		var size := 30
		var color := Color(0.85, 0.85, 0.85)
		var font: Font = mono
		match style:
			"title":
				size = 50
				color = Color(1, 1, 1)
			"red":
				color = Color(1, 0.25, 0.2)
			"small":
				size = 22
				color = Color(0.6, 0.6, 0.6)
			"serif":
				font = sans
		var l := _title_label(text, size, color, font)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.modulate.a = 0.0
		card_box.add_child(l)
		labels.append(l)
	for l in labels:
		var tw := create_tween()
		tw.tween_property(l, "modulate:a", 1.0, 1.0)
		await get_tree().create_timer(line_delay, true).timeout
	await get_tree().create_timer(hold, true).timeout
	var tw2 := create_tween()
	tw2.tween_property(card_root, "modulate:a", 0.0, fade_out)
	await tw2.finished
	card_root.visible = false


# ------------------------------------------------------------------ documents
func _build_document() -> void:
	doc_root = Control.new()
	doc_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	doc_root.visible = false
	add_child(doc_root)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	doc_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	doc_root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	center.add_child(col)
	doc_panel = PanelContainer.new()
	doc_panel.custom_minimum_size = Vector2(760, 0)
	col.add_child(doc_panel)
	doc_text = RichTextLabel.new()
	doc_text.bbcode_enabled = true
	doc_text.fit_content = true
	doc_text.scroll_active = false
	doc_text.custom_minimum_size = Vector2(680, 0)
	doc_panel.add_child(doc_text)
	_doc_close = _title_label("", 18, Color(0.7, 0.7, 0.7))
	col.add_child(_doc_close)


func show_document(text: String, style := "paper") -> void:
	_doc_close.text = Game.with_keys("[E] ou clic pour fermer").replace("[", "").replace("]", "")
	var sb := StyleBoxFlat.new()
	sb.set_content_margin_all(44)
	var font: Font = hand
	var color := Color(0.12, 0.1, 0.09)
	var size := 30
	match style:
		"paper":
			sb.bg_color = Color(0.91, 0.88, 0.8)
		"typed":
			sb.bg_color = Color(0.85, 0.84, 0.8)
			font = mono
			size = 22
		"phone":
			sb.bg_color = Color(0.05, 0.06, 0.08)
			sb.set_corner_radius_all(34)
			sb.border_color = Color(0.15, 0.15, 0.17)
			sb.set_border_width_all(10)
			font = sans
			color = Color(0.92, 0.92, 0.94)
			size = 24
	doc_panel.add_theme_stylebox_override("panel", sb)
	doc_text.add_theme_font_override("normal_font", font)
	doc_text.add_theme_font_override("bold_font", font)
	doc_text.add_theme_font_size_override("normal_font_size", size)
	doc_text.add_theme_font_size_override("bold_font_size", size)
	doc_text.add_theme_color_override("default_color", color)
	doc_text.text = text
	doc_root.visible = true
	document_open = true
	Sound.play("paper", -4.0, 1.0, "UI")
	await document_closed


var doc_closed_at := -10.0


func _close_document() -> void:
	doc_root.visible = false
	document_open = false
	doc_closed_at = Time.get_ticks_msec() / 1000.0
	document_closed.emit()


## Vrai pendant un document, et un court instant après sa fermeture : la touche qui l'a fermé
## ne doit pas relancer l'interaction (sinon le document se rouvre aussitôt).
func blocks_interaction() -> bool:
	return document_open or Time.get_ticks_msec() / 1000.0 - doc_closed_at < 0.35


func _input(event: InputEvent) -> void:
	if controls_menu != null and controls_menu.visible:
		if _capture_binding(event):
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("pause"):
			_close_controls()
			get_viewport().set_input_as_handled()
		return
	if not document_open:
		return
	var close := event.is_action_pressed("interact") or event.is_action_pressed("pause")
	if event is InputEventMouseButton and event.pressed:
		close = true
	if close:
		get_viewport().set_input_as_handled()
		_close_document()
