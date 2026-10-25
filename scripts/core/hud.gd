class_name HUD
extends CanvasLayer
## Incrustation de la caméra-piéton : REC, horodatage, batterie, vumètre micro,
## sous-titres, objectifs, invites d'interaction, indices, et l'overlay "EN DIRECT" de la fin.

const MARGIN := 58.0

var root: Control
var mono: SystemFont
var sans: SystemFont

var rec_dot: Label
var rec_label: Label
var osd_center: Label  ## « SIGNAL PERDU »
var osd_top: Label  ## « ◀◀ REMBOBINAGE »
var battery_label: Label
var clock_label: Label
var device_label: Label
var mic_bars: Array[ColorRect] = []
var objective_box: HBoxContainer
var objective_label: Label
var prompt_label: RichTextLabel
var hold_bg: ColorRect
var hold_fill: ColorRect
var subtitle: RichTextLabel
var hint_panel: PanelContainer
var hint_label: RichTextLabel
const HINT_BOTTOM := -44.0  ## bas de la boîte des conseils (sous les sous-titres, au ras de l'écran)
var live_root: Control
var live_viewers: Label
var live_big: Label

var battery := 4
var rec_visible := true
var _sub_id := 0
var _hint_id := 0
var _obj_id := 0
var _blink := 0.0
var _objective_text := ""
var _mic_smooth := 0.0
var _voice_hot := 0.0
var mic_label: Label


func _ready() -> void:
	layer = 2
	process_mode = Node.PROCESS_MODE_ALWAYS
	mono = SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "Monospace"])
	mono.font_weight = 700
	sans = SystemFont.new()
	sans.font_names = PackedStringArray(["Segoe UI", "Arial", "Sans-Serif"])
	sans.font_weight = 600

	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- haut gauche : REC + batterie
	var tl := VBoxContainer.new()
	_place(tl, 0, 0, 0, 0, MARGIN, 36, 600, 200)
	root.add_child(tl)
	var rec_row := HBoxContainer.new()
	tl.add_child(rec_row)
	rec_dot = _label("●", 30, Color(1, 0.16, 0.16))
	rec_row.add_child(rec_dot)
	rec_label = _label("REC", 30)
	rec_row.add_child(rec_label)
	battery_label = _label("BAT ▮▮▮▮", 24)
	tl.add_child(battery_label)

	# --- haut droite : horodatage + identifiant de l'appareil
	var tr := VBoxContainer.new()
	_place(tr, 1, 0, 1, 0, -760, 36, -MARGIN, 200)
	root.add_child(tr)
	clock_label = _label("2026-11-14  23:41:07", 30)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(clock_label)
	device_label = _label("BWC-7  SN 0417  T.MARCHAND", 22)
	device_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	device_label.modulate.a = 0.85
	tr.add_child(device_label)

	# --- bas droite : vumètre micro
	var br := HBoxContainer.new()
	br.alignment = BoxContainer.ALIGNMENT_END
	_place(br, 1, 1, 1, 1, -420, -86, -MARGIN, -46)
	br.add_theme_constant_override("separation", 3)
	root.add_child(br)
	var mic := _label("MIC", 18)
	mic_label = mic
	mic.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	mic.size_flags_vertical = Control.SIZE_FILL
	br.add_child(mic)
	for i in 14:
		var bar_holder := Control.new()
		bar_holder.custom_minimum_size = Vector2(7, 30)
		br.add_child(bar_holder)
		var bar := ColorRect.new()
		var h := 6.0 + i * 1.7
		bar.position = Vector2(0, 30 - h)
		bar.size = Vector2(7, h)
		bar.color = Color(1, 1, 1, 0.22)
		bar_holder.add_child(bar)
		mic_bars.append(bar)

	# --- objectif
	objective_box = HBoxContainer.new()
	objective_box.add_theme_constant_override("separation", 12)
	_place(objective_box, 0, 0, 0, 0, MARGIN, 170, 900, 300)
	objective_box.modulate.a = 0.0
	root.add_child(objective_box)
	var bar_line := ColorRect.new()
	bar_line.color = Color(1, 1, 1, 0.7)
	bar_line.custom_minimum_size = Vector2(3, 60)
	objective_box.add_child(bar_line)
	var obj_col := VBoxContainer.new()
	objective_box.add_child(obj_col)
	var obj_title := _label("OBJECTIF", 17)
	obj_title.modulate.a = 0.6
	obj_col.add_child(obj_title)
	objective_label = _label("", 24)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.custom_minimum_size.x = 760
	obj_col.add_child(objective_label)

	# --- invite d'interaction
	prompt_label = _rich(26)
	_place(prompt_label, 0.5, 0.58, 0.5, 0.58, -500, 0, 500, 44)
	prompt_label.visible = false
	root.add_child(prompt_label)
	hold_bg = ColorRect.new()
	hold_bg.color = Color(1, 1, 1, 0.2)
	_place(hold_bg, 0.5, 0.58, 0.5, 0.58, -110, 46, 110, 52)
	hold_bg.visible = false
	root.add_child(hold_bg)
	hold_fill = ColorRect.new()
	hold_fill.color = Color(1, 1, 1, 0.9)
	hold_fill.size = Vector2(0, 6)
	hold_bg.add_child(hold_fill)

	# --- sous-titres
	subtitle = RichTextLabel.new()
	subtitle.bbcode_enabled = true
	subtitle.fit_content = true
	subtitle.scroll_active = false
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle.add_theme_font_override("normal_font", sans)
	subtitle.add_theme_font_size_override("normal_font_size", 34)
	subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	subtitle.add_theme_constant_override("shadow_offset_x", 2)
	subtitle.add_theme_constant_override("shadow_offset_y", 2)
	subtitle.add_theme_constant_override("outline_size", 6)
	subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_place(subtitle, 0.5, 1, 0.5, 1, -720, -250, 720, -130)
	root.add_child(subtitle)

	# --- textes de la caméra elle-même
	osd_center = _label("", 54)
	osd_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(osd_center, 0.5, 0.5, 0.5, 0.5, -500, -40, 500, 40)
	root.add_child(osd_center)
	osd_top = _label("", 34)
	osd_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(osd_top, 0.5, 0, 0.5, 0, -400, 90, 400, 140)
	root.add_child(osd_top)

	# --- conseil (tutoriel) : une boîte sombre aux coins arrondis, touches dessinées
	hint_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.035, 0.035, 0.8)
	sb.set_corner_radius_all(9)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 10
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 11
	hint_panel.add_theme_stylebox_override("panel", sb)
	hint_label = _rich(22)
	hint_panel.add_child(hint_label)
	_place(hint_panel, 0.5, 1, 0.5, 1, -450, HINT_BOTTOM - 50.0, 450, HINT_BOTTOM)
	hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_panel.visible = false
	root.add_child(hint_panel)

	# --- overlay "EN DIRECT" (révélation finale)
	live_root = Control.new()
	live_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	live_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live_root.visible = false
	root.add_child(live_root)
	var live_row := HBoxContainer.new()
	live_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_place(live_row, 0.5, 0, 0.5, 0, -400, 40, 400, 90)
	live_root.add_child(live_row)
	var live_badge := PanelContainer.new()
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(0.88, 0.08, 0.12)
	lsb.content_margin_left = 14
	lsb.content_margin_right = 14
	live_badge.add_theme_stylebox_override("panel", lsb)
	var live_lbl := _label("● EN DIRECT", 28, Color.WHITE, sans)
	live_badge.add_child(live_lbl)
	live_row.add_child(live_badge)
	live_viewers = _label("  2 341 spectateurs", 28, Color.WHITE, sans)
	live_row.add_child(live_viewers)
	live_big = _label("", 54, Color.WHITE, sans)
	live_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(live_big, 0, 0.42, 1, 0.42, 0, -40, 0, 40)
	live_root.add_child(live_big)

	root.visible = false


# ------------------------------------------------------------------ helpers
## Texte riche centré (pour les touches dessinées), même police que les sous-titres.
func _rich(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", sans)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_color_override("default_color", Color(1, 1, 1, 0.92))
	r.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	r.add_theme_constant_override("outline_size", 5)
	return r


## « [F] lampe » → la touche F dessinée comme une touche de clavier (fond clair, lettre blanche) ;
## « [clic droit] » / « [clic gauche] » → une petite souris, le bouton concerné allumé.
func _keycaps(text: String) -> String:
	var re := RegEx.new()
	re.compile("\\[([^\\]]{1,14})\\]")
	var out := text
	for m in re.search_all(text):
		var key := m.get_string(1)
		if key in ["clic droit", "clic gauche"]:
			var icon := "res://assets/gen/icon_mouse_%s.png" % ("right" if key == "clic droit" else "left")
			out = out.replace("[" + key + "]", "[img=24x34]%s[/img]" % icon)
			continue
		out = out.replace("[" + key + "]", "[bgcolor=#ffffff33][color=#ffffff]\u2009" + key + "\u2009[/color][/bgcolor]\u2009")
	return out.replace("   ·   ", "    [color=#ffffff66]·[/color]    ")


func _label(text: String, size: int, color := Color(1, 1, 1, 0.9), font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font = font if font != null else mono
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = 5
	ls.outline_color = Color(0, 0, 0, 0.55)
	ls.shadow_size = 3
	ls.shadow_color = Color(0, 0, 0, 0.6)
	ls.shadow_offset = Vector2(2, 2)
	l.label_settings = ls
	return l


func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob


# ------------------------------------------------------------------ API
func show_hud(v: bool) -> void:
	root.visible = v


func reset() -> void:
	_sub_id += 1
	_hint_id += 1
	subtitle.text = ""
	prompt("")
	hold(0.0)
	hint_panel.visible = false
	objective_box.modulate.a = 0.0
	live_root.visible = false
	osd_center.text = ""
	osd_top.text = ""
	set_rec(true)


## Texte affiché par la caméra (centre : alerte ; haut : mode de lecture), clignotant.
func osd(text: String, top := false) -> void:
	var l := osd_top if top else osd_center
	l.text = text
	l.modulate.a = 1.0
	if text == "":
		return
	var tw := l.create_tween().set_loops(6)
	tw.tween_property(l, "modulate:a", 0.25, 0.35)
	tw.tween_property(l, "modulate:a", 1.0, 0.35)


func set_clock(text: String) -> void:
	clock_label.text = text


func set_battery(level: int) -> void:
	battery = clampi(level, 0, 4)
	battery_label.text = "BAT " + "▮".repeat(battery) + "▯".repeat(4 - battery)


func set_rec(on: bool) -> void:
	rec_visible = on
	rec_label.visible = on
	rec_dot.visible = on


var _sub_fade: Tween


## Affiche une réplique. Peut être attendue avec `await`.
func say(text: String, duration := 3.2, speaker := "Théo") -> void:
	_sub_id += 1
	var id := _sub_id
	# le fondu de la réplique précédente ne doit pas effacer celle-ci (répliques enchaînées)
	if _sub_fade != null and _sub_fade.is_valid():
		_sub_fade.kill()
	var who := "" if speaker == "" else "[color=#ffd27a]%s :[/color] " % speaker
	subtitle.text = "[center]%s%s[/center]" % [who, text]
	subtitle.modulate.a = 1.0
	await get_tree().create_timer(duration, false).timeout
	if id == _sub_id:
		_sub_fade = create_tween()
		_sub_fade.tween_property(subtitle, "modulate:a", 0.0, 0.4)


func objective(text: String) -> void:
	_objective_text = text
	if text == "":
		objective_box.modulate.a = 0.0
		return
	objective_label.text = text
	_show_objective(7.0)
	Sound.play("ui_beep", -14.0, 1.0, "UI")


func recall_objective() -> void:
	if _objective_text != "":
		_show_objective(4.0)


func _show_objective(duration: float) -> void:
	_obj_id += 1
	var id := _obj_id
	var tw := create_tween()
	tw.tween_property(objective_box, "modulate:a", 1.0, 0.4)
	await get_tree().create_timer(duration, false).timeout
	if id == _obj_id:
		var tw2 := create_tween()
		tw2.tween_property(objective_box, "modulate:a", 0.0, 1.2)


func prompt(text: String) -> void:
	prompt_label.visible = text != ""
	prompt_label.text = "[center]" + _keycaps("[E]") + "  " + text + "[/center]"


func hold(progress: float) -> void:
	hold_bg.visible = progress > 0.0
	hold_fill.size = Vector2(220.0 * clampf(progress, 0.0, 1.0), 6)


var _pickup_id := 0
var _pickup_label: Label


## Petite notification « + objet » en bas à gauche, quand Théo ramasse quelque chose.
func pickup(item_name: String) -> void:
	if _pickup_label == null:
		_pickup_label = Label.new()
		var ls := LabelSettings.new()
		ls.font = mono
		ls.font_size = 22
		ls.font_color = Color(1.0, 0.86, 0.55)
		ls.outline_size = 4
		ls.outline_color = Color(0, 0, 0, 0.8)
		_pickup_label.label_settings = ls
		_place(_pickup_label, 0, 1, 0, 1, MARGIN, -190, 900, -150)
		root.add_child(_pickup_label)
	_pickup_id += 1
	var id := _pickup_id
	_pickup_label.text = "+ %s      [I] inventaire" % item_name.replace("[", "(").replace("]", ")")
	_pickup_label.modulate.a = 1.0
	await get_tree().create_timer(3.2, false).timeout
	if id == _pickup_id:
		create_tween().tween_property(_pickup_label, "modulate:a", 0.0, 0.6)


func hint(text: String, duration := 6.0) -> void:
	_hint_id += 1
	var id := _hint_id
	hint_label.text = "[center]" + _keycaps(text) + "[/center]"
	# la carte prend la largeur du texte (sans dépasser 900 px)
	var plain := text.replace("[clic droit]", "WW").replace("[clic gauche]", "WW").replace("[", " ").replace("]", " ")
	var w := clampf(sans.get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 70.0, 300.0, 900.0)
	hint_label.custom_minimum_size = Vector2(w - 44.0, 0)
	hint_panel.offset_left = -w * 0.5
	hint_panel.offset_right = w * 0.5
	hint_panel.modulate.a = 0.0
	hint_panel.visible = true
	# le texte doit être mis en page (une image) avant de connaître la hauteur de la carte
	await get_tree().process_frame
	if id != _hint_id:
		return
	var h := hint_panel.get_combined_minimum_size().y
	hint_panel.offset_bottom = HINT_BOTTOM
	hint_panel.offset_top = HINT_BOTTOM - h
	hint_panel.size = Vector2(w, h)
	# apparition : glisse un peu vers le haut en fondu
	var final_y := hint_panel.position.y
	hint_panel.position.y = final_y + 14.0
	var tw := create_tween().set_parallel()
	tw.tween_property(hint_panel, "modulate:a", 1.0, 0.25)
	tw.tween_property(hint_panel, "position:y", final_y, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	Sound.play("ui_beep", -20.0, 1.3, "UI")
	await get_tree().create_timer(duration, false).timeout
	if id == _hint_id:
		var tw2 := create_tween()
		tw2.tween_property(hint_panel, "modulate:a", 0.0, 0.45)
		await tw2.finished
		if id == _hint_id:
			hint_panel.visible = false


func live_overlay(on: bool, viewers := 2341, big := "") -> void:
	live_root.visible = on
	live_viewers.text = "  %s spectateurs" % _thousands(viewers)
	live_big.text = big


func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return out


func _process(delta: float) -> void:
	if not root.visible:
		return
	_blink += delta
	rec_dot.modulate.a = 1.0 if fmod(_blink, 1.0) < 0.6 else 0.0
	# vumètre : ton vrai micro uniquement ; en rouge quand ta voix porte assez loin pour être entendue
	var voice := Sound.mic_voice
	var lvl := Sound.mic_level01() if Sound.mic_active() else 0.0
	_mic_smooth = maxf(lvl, _mic_smooth - delta * 1.8)
	mic_label.text = "MIC" if Sound.mic_active() else "MIC OFF"
	_voice_hot = maxf(0.0, _voice_hot - delta) if voice < 0.12 else 0.6
	var lit := int(round(_mic_smooth * mic_bars.size()))
	for i in mic_bars.size():
		var bar := mic_bars[i]
		if i < lit:
			bar.color = Color(1, 0.3, 0.25, 0.95) if (i >= 11 or _voice_hot > 0.0) else Color(1, 1, 1, 0.9)
		else:
			bar.color = Color(1, 1, 1, 0.22)
