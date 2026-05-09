# ============================================================
# main_menu.gd
# ============================================================
extends Control

# =============================================================
# EXPORTS
# =============================================================
@export var game_scene   : PackedScene
@export var music_stream : AudioStream
@export var hover_sound  : AudioStream
@export var game_title   : String = "SURVIVAL"
@export var game_subtitle: String = "ENTER THE DARK"
@export_range(0.0, 1.0, 0.05) var default_music_volume : float = 0.8

# =============================================================
# STATE
# =============================================================
var _settings_open    : bool = false
var _splitscreen_open : bool = false
var _teamselect_open  : bool = false
var _master_volume    : float = 1.0
var _music_volume     : float = 0.8
var _sfx_volume       : float = 1.0
var _fullscreen       : bool = false
var _player_count     : int  = 1
var _ai_difficulty    : int  = 2   # 1=Easy 2=Medium 3=Hard 4=Nightmare
var _ai_enabled       : bool = true

# player index (0-based) -> team_id (1 or 2)
var _team_assignments : Dictionary = {}

# =============================================================
# NODES
# =============================================================
var _music          : AudioStreamPlayer
var _hover_sfx      : AudioStreamPlayer
var _main_panel     : Control
var _settings_panel : Control
var _split_panel    : Control
var _team_panel     : Control

var _player_rows    : VBoxContainer
var _warn_label     : Label
var _layout_preview : Control
var _count_row      : HBoxContainer
var _diff_row       : HBoxContainer
var _ai_toggle_btn  : Button


# =============================================================
# READY
# =============================================================
func _ready() -> void:
	_music_volume = default_music_volume
	_load_from_settings()
	_setup_audio()
	_build_ui()
	_animate_in()


func _load_from_settings() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if not is_instance_valid(gs): return
	_ai_difficulty = gs.ai_difficulty
	_ai_enabled    = gs.ai_enabled


# =============================================================
# INPUT
# =============================================================
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _teamselect_open:  _close_teamselect()
		elif _settings_open:  _close_settings()
		elif _splitscreen_open: _close_splitscreen()


# =============================================================
# AUDIO
# =============================================================
func _setup_audio() -> void:
	_music          = AudioStreamPlayer.new()
	_music.bus      = "Master"
	_music.autoplay = false
	add_child(_music)
	if music_stream:
		_music.stream    = music_stream
		_music.volume_db = linear_to_db(_music_volume)
		_music.play()

	_hover_sfx           = AudioStreamPlayer.new()
	_hover_sfx.bus       = "Master"
	_hover_sfx.volume_db = -6.0
	add_child(_hover_sfx)
	if hover_sound:
		_hover_sfx.stream = hover_sound


# =============================================================
# BUILD UI
# =============================================================
func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.06, 1.0)
	add_child(bg)

	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.color = Color(0.0, 0.0, 0.0, 0.45)
	add_child(vignette)

	_main_panel     = _build_main_panel()
	_settings_panel = _build_settings_panel()
	_split_panel    = _build_splitscreen_panel()
	_team_panel     = _build_teamselect_panel()

	_settings_panel.visible = false
	_split_panel.visible    = false
	_team_panel.visible     = false

	add_child(_main_panel)
	add_child(_settings_panel)
	add_child(_split_panel)
	add_child(_team_panel)


# =============================================================
# MAIN PANEL
# =============================================================
func _build_main_panel() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bar := ColorRect.new()
	bar.color = Color(0.6, 0.15, 0.1, 1.0)
	bar.set_anchor(SIDE_LEFT,   0.08); bar.set_anchor(SIDE_RIGHT,  0.083)
	bar.set_anchor(SIDE_TOP,    0.18); bar.set_anchor(SIDE_BOTTOM, 0.62)
	root.add_child(bar)

	var title := Label.new()
	title.name = "Title"
	title.text = game_title
	title.add_theme_font_size_override("font_size", 92)
	title.add_theme_color_override("font_color", Color(0.92, 0.88, 0.82))
	title.set_anchor(SIDE_LEFT,   0.12); title.set_anchor(SIDE_RIGHT,  0.9)
	title.set_anchor(SIDE_TOP,    0.18); title.set_anchor(SIDE_BOTTOM, 0.38)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.modulate.a = 0.0
	root.add_child(title)

	var sub := Label.new()
	sub.name = "Subtitle"
	sub.text = game_subtitle
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.6, 0.15, 0.1))
	sub.set_anchor(SIDE_LEFT,   0.12); sub.set_anchor(SIDE_RIGHT,  0.9)
	sub.set_anchor(SIDE_TOP,    0.36); sub.set_anchor(SIDE_BOTTOM, 0.46)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.modulate.a = 0.0
	root.add_child(sub)

	var btns := VBoxContainer.new()
	btns.name = "Buttons"
	btns.set_anchor(SIDE_LEFT,   0.12); btns.set_anchor(SIDE_RIGHT,  0.48)
	btns.set_anchor(SIDE_TOP,    0.50); btns.set_anchor(SIDE_BOTTOM, 0.92)
	btns.add_theme_constant_override("separation", 14)
	btns.modulate.a = 0.0
	root.add_child(btns)

	# ── Main buttons ──────────────────────────────────────────
	var play_btn  := _make_button("▶   PLAY",         Color(0.6, 0.15, 0.1))
	var split_btn := _make_button("⊞   SPLIT SCREEN",  Color(0.15, 0.25, 0.35))
	var set_btn   := _make_button("⚙   SETTINGS",     Color(0.18, 0.18, 0.2))
	var quit_btn  := _make_button("✕   QUIT",          Color(0.1, 0.1, 0.12))

	play_btn.pressed.connect(_on_play)
	split_btn.pressed.connect(_open_splitscreen)
	set_btn.pressed.connect(_open_settings)
	quit_btn.pressed.connect(_on_quit)

	btns.add_child(play_btn)
	btns.add_child(split_btn)

	# ── AI toggle + difficulty (shown for solo play) ──────────
	var ai_section := VBoxContainer.new()
	ai_section.add_theme_constant_override("separation", 6)
	btns.add_child(ai_section)

	_ai_toggle_btn = _make_small_button(
		"🤖 VS AI: %s" % ("ON" if _ai_enabled else "OFF"),
		Color(0.18, 0.25, 0.35) if _ai_enabled else Color(0.18, 0.18, 0.2))
	_ai_toggle_btn.pressed.connect(_toggle_ai)
	ai_section.add_child(_ai_toggle_btn)

	var diff_lbl := Label.new()
	diff_lbl.text = "DIFFICULTY"
	diff_lbl.add_theme_font_size_override("font_size", 11)
	diff_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	diff_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ai_section.add_child(diff_lbl)

	_diff_row = HBoxContainer.new()
	_diff_row.add_theme_constant_override("separation", 6)
	ai_section.add_child(_diff_row)

	var diff_defs := [
		["EASY",      1, Color(0.1, 0.4, 0.15)],
		["MEDIUM",    2, Color(0.4, 0.35, 0.08)],
		["HARD",      3, Color(0.45, 0.15, 0.08)],
		["NIGHTMARE", 4, Color(0.35, 0.04, 0.04)],
	]
	for dd in diff_defs:
		var dv   : int    = dd[1]
		var dcol : Color  = dd[2]
		var dbtn := _make_diff_button(dd[0], dv, dcol)
		dbtn.name = "Diff_%d" % dv
		dbtn.pressed.connect(func():
			_ai_difficulty = dv
			_refresh_diff_buttons())
		_diff_row.add_child(dbtn)

	_refresh_diff_buttons()

	btns.add_child(set_btn)
	btns.add_child(quit_btn)

	var ver := Label.new()
	ver.text = "v0.1 ALPHA"
	ver.add_theme_font_size_override("font_size", 11)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.2))
	ver.set_anchor(SIDE_LEFT,   0.88); ver.set_anchor(SIDE_RIGHT,  1.0)
	ver.set_anchor(SIDE_TOP,    0.95); ver.set_anchor(SIDE_BOTTOM, 1.0)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(ver)

	return root


# =============================================================
# SPLIT SCREEN PANEL
# =============================================================
func _build_splitscreen_panel() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.78)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var box := PanelContainer.new()
	box.set_anchor(SIDE_LEFT, 0.28); box.set_anchor(SIDE_RIGHT,  0.72)
	box.set_anchor(SIDE_TOP,  0.18); box.set_anchor(SIDE_BOTTOM, 0.82)
	box.add_theme_stylebox_override("panel", _panel_style(Color(0.15, 0.25, 0.35)))
	root.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	box.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "SPLIT SCREEN"
	hdr.add_theme_font_size_override("font_size", 30)
	hdr.add_theme_color_override("font_color", Color(0.92, 0.88, 0.82))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hdr)

	vbox.add_child(_hsep(Color(0.15, 0.25, 0.35, 0.8)))

	var count_lbl := Label.new()
	count_lbl.text = "SELECT NUMBER OF PLAYERS"
	count_lbl.add_theme_font_size_override("font_size", 13)
	count_lbl.add_theme_color_override("font_color", Color(0.55, 0.65, 0.75))
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(count_lbl)

	_count_row = HBoxContainer.new()
	_count_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_count_row.add_theme_constant_override("separation", 12)
	vbox.add_child(_count_row)

	for i in range(1, 5):
		var n    : int = i
		var pbtn := _make_count_button(str(n), n == _player_count)
		pbtn.name = "Count_%d" % n
		pbtn.pressed.connect(func():
			_player_count = n
			_refresh_count_buttons())
		_count_row.add_child(pbtn)

	var prev_lbl := Label.new()
	prev_lbl.text = "LAYOUT PREVIEW"
	prev_lbl.add_theme_font_size_override("font_size", 12)
	prev_lbl.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6))
	prev_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(prev_lbl)

	_layout_preview = _build_layout_preview()
	vbox.add_child(_layout_preview)

	vbox.add_child(_hsep(Color(0.15, 0.25, 0.35, 0.8)))

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	vbox.add_child(action_row)

	var back_btn := _make_button("←  BACK", Color(0.12, 0.12, 0.14))
	var next_btn := _make_button("▶  NEXT", Color(0.15, 0.38, 0.22))
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.pressed.connect(_close_splitscreen)
	next_btn.pressed.connect(_on_play_splitscreen)
	action_row.add_child(back_btn)
	action_row.add_child(next_btn)

	return root


# =============================================================
# TEAM SELECT PANEL
# =============================================================
func _build_teamselect_panel() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.82)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var box := PanelContainer.new()
	box.set_anchor(SIDE_LEFT, 0.18); box.set_anchor(SIDE_RIGHT,  0.82)
	box.set_anchor(SIDE_TOP,  0.08); box.set_anchor(SIDE_BOTTOM, 0.92)
	box.add_theme_stylebox_override("panel", _panel_style(Color(0.6, 0.15, 0.1)))
	root.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	box.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "SELECT TEAMS"
	hdr.add_theme_font_size_override("font_size", 30)
	hdr.add_theme_color_override("font_color", Color(0.92, 0.88, 0.82))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hdr)

	var sub := Label.new()
	sub.text = "Assign each player to a team — AI covers any empty team"
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.55, 0.55, 0.5))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	vbox.add_child(_hsep(Color(0.6, 0.15, 0.1, 0.5)))

	_player_rows = VBoxContainer.new()
	_player_rows.add_theme_constant_override("separation", 12)
	_player_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_player_rows)

	vbox.add_child(_hsep(Color(0.6, 0.15, 0.1, 0.5)))

	_warn_label = Label.new()
	_warn_label.text = ""
	_warn_label.add_theme_font_size_override("font_size", 12)
	_warn_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.2))
	_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_warn_label)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	vbox.add_child(action_row)

	var back_btn   := _make_button("←  BACK",   Color(0.12, 0.12, 0.14))
	var launch_btn := _make_button("▶  LAUNCH", Color(0.15, 0.38, 0.22))
	back_btn.size_flags_horizontal   = Control.SIZE_EXPAND_FILL
	launch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.pressed.connect(_close_teamselect)
	launch_btn.pressed.connect(_on_launch_from_teamselect)
	action_row.add_child(back_btn)
	action_row.add_child(launch_btn)

	return root


# =============================================================
# PLAYER ROWS (team select)
# =============================================================
func _rebuild_player_rows() -> void:
	for c in _player_rows.get_children():
		c.queue_free()

	for i in range(_player_count):
		if not _team_assignments.has(i):
			_team_assignments[i] = (i % 2) + 1

	for i in range(_player_count):
		var pi := i
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_player_rows.add_child(row)

		var lbl := Label.new()
		lbl.text = "PLAYER %d" % (i + 1)
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.custom_minimum_size.x = 120
		row.add_child(lbl)

		var t1 := _make_team_button("TEAM 1", 1, _team_assignments[i] == 1)
		t1.name = "T1_%d" % i
		t1.pressed.connect(func(): _team_assignments[pi] = 1; _refresh_team_row(pi))
		row.add_child(t1)

		var t2 := _make_team_button("TEAM 2", 2, _team_assignments[i] == 2)
		t2.name = "T2_%d" % i
		t2.pressed.connect(func(): _team_assignments[pi] = 2; _refresh_team_row(pi))
		row.add_child(t2)

		var ind := ColorRect.new()
		ind.name = "Ind_%d" % i
		ind.custom_minimum_size = Vector2(12, 40)
		ind.color = _team_color(_team_assignments[i])
		row.add_child(ind)


func _refresh_team_row(player_idx: int) -> void:
	if player_idx >= _player_rows.get_child_count(): return
	var row := _player_rows.get_child(player_idx) as HBoxContainer
	if not row: return
	var t1  := row.get_node_or_null("T1_%d" % player_idx) as Button
	var t2  := row.get_node_or_null("T2_%d" % player_idx) as Button
	var ind := row.get_node_or_null("Ind_%d" % player_idx) as ColorRect
	if t1:  _style_team_button(t1, 1, _team_assignments[player_idx] == 1)
	if t2:  _style_team_button(t2, 2, _team_assignments[player_idx] == 2)
	if ind: ind.color = _team_color(_team_assignments[player_idx])
	_update_team_warning()


func _update_team_warning() -> void:
	var t1 := 0; var t2 := 0
	for i in range(_player_count):
		if _team_assignments.get(i, 1) == 1: t1 += 1
		else: t2 += 1
	if t1 == 0:
		_warn_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.2))
		_warn_label.text = "⚠ No players on Team 1 — AI will cover it."
	elif t2 == 0:
		_warn_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.2))
		_warn_label.text = "⚠ No players on Team 2 — AI will cover it."
	else:
		_warn_label.add_theme_color_override("font_color", Color(0.4, 0.75, 0.45))
		_warn_label.text = "Team 1: %d   |   Team 2: %d" % [t1, t2]


# =============================================================
# LAYOUT PREVIEW
# =============================================================
func _build_layout_preview() -> Control:
	var c := Control.new()
	c.custom_minimum_size    = Vector2(0, 100)
	c.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	for i in range(4):
		var r     := ColorRect.new()
		r.name    = "Slot_%d" % i
		r.color   = Color(0.1, 0.18, 0.26, 0.0)
		c.add_child(r)
	_update_layout_preview(_player_count)
	return c


func _update_layout_preview(count: int) -> void:
	if not is_instance_valid(_layout_preview): return
	const ACTIVE   := Color(0.2, 0.4, 0.6, 0.85)
	const INACTIVE := Color(0.08, 0.1, 0.14, 0.4)
	const GAP      := 0.015
	var layouts := {
		1: [[0.0,0.0,1.0,1.0],[0.0,0.0,0.0,0.0],[0.0,0.0,0.0,0.0],[0.0,0.0,0.0,0.0]],
		2: [[0.0,0.0,0.5-GAP/2,1.0],[0.5+GAP/2,0.0,1.0,1.0],[0.0,0.0,0.0,0.0],[0.0,0.0,0.0,0.0]],
		3: [[0.0,0.0,0.5-GAP/2,1.0],[0.5+GAP/2,0.0,1.0,0.5-GAP/2],[0.5+GAP/2,0.5+GAP/2,1.0,1.0],[0.0,0.0,0.0,0.0]],
		4: [[0.0,0.0,0.5-GAP/2,0.5-GAP/2],[0.5+GAP/2,0.0,1.0,0.5-GAP/2],[0.0,0.5+GAP/2,0.5-GAP/2,1.0],[0.5+GAP/2,0.5+GAP/2,1.0,1.0]],
	}
	var layout : Array = layouts[count]
	for i in range(4):
		var slot := _layout_preview.get_node("Slot_%d" % i) as ColorRect
		var l    : Array = layout[i]
		if l[0] == l[2] and l[1] == l[3]:
			slot.color = INACTIVE
			slot.set_anchor(SIDE_LEFT, 0.0); slot.set_anchor(SIDE_RIGHT,  0.0)
			slot.set_anchor(SIDE_TOP,  0.0); slot.set_anchor(SIDE_BOTTOM, 0.0)
		else:
			slot.color = ACTIVE if i < count else INACTIVE
			slot.set_anchor(SIDE_LEFT,   l[0]); slot.set_anchor(SIDE_RIGHT,  l[2])
			slot.set_anchor(SIDE_TOP,    l[1]); slot.set_anchor(SIDE_BOTTOM, l[3])


# =============================================================
# SETTINGS PANEL
# =============================================================
func _build_settings_panel() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.75)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var box := PanelContainer.new()
	box.set_anchor(SIDE_LEFT, 0.25); box.set_anchor(SIDE_RIGHT,  0.75)
	box.set_anchor(SIDE_TOP,  0.12); box.set_anchor(SIDE_BOTTOM, 0.88)
	box.add_theme_stylebox_override("panel", _panel_style(Color(0.6, 0.15, 0.1)))
	root.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 22)
	box.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "SETTINGS"
	hdr.add_theme_font_size_override("font_size", 32)
	hdr.add_theme_color_override("font_color", Color(0.92, 0.88, 0.82))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hdr)

	vbox.add_child(_hsep(Color(0.6, 0.15, 0.1, 0.6)))

	vbox.add_child(_make_slider_row("MASTER VOLUME", _master_volume, func(v):
		_master_volume = v
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(v))))
	vbox.add_child(_make_slider_row("MUSIC VOLUME", _music_volume, func(v):
		_music_volume = v
		if _music: _music.volume_db = linear_to_db(v)))
	vbox.add_child(_make_slider_row("SFX VOLUME", _sfx_volume, func(v):
		_sfx_volume = v
		if _hover_sfx: _hover_sfx.volume_db = linear_to_db(v) - 6.0))

	var fs_row := HBoxContainer.new()
	var fs_lbl := Label.new()
	fs_lbl.text = "FULLSCREEN"
	fs_lbl.add_theme_font_size_override("font_size", 14)
	fs_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	fs_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fs_chk := CheckButton.new()
	fs_chk.button_pressed = _fullscreen
	fs_chk.toggled.connect(func(on):
		_fullscreen = on
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	fs_row.add_child(fs_lbl)
	fs_row.add_child(fs_chk)
	vbox.add_child(fs_row)

	vbox.add_child(_hsep(Color(0.6, 0.15, 0.1, 0.6)))

	var close := _make_button("✕   CLOSE", Color(0.18, 0.18, 0.2))
	close.pressed.connect(_close_settings)
	vbox.add_child(close)

	return root


# =============================================================
# AI TOGGLE + DIFFICULTY
# =============================================================
func _toggle_ai() -> void:
	_ai_enabled = not _ai_enabled
	if is_instance_valid(_ai_toggle_btn):
		_ai_toggle_btn.text = "🤖 VS AI: %s" % ("ON" if _ai_enabled else "OFF")
		var col := Color(0.18, 0.25, 0.35) if _ai_enabled else Color(0.18, 0.18, 0.2)
		var s := StyleBoxFlat.new()
		s.bg_color = col; s.set_corner_radius_all(3); s.content_margin_left = 24
		_ai_toggle_btn.add_theme_stylebox_override("normal", s)
		_ai_toggle_btn.add_theme_stylebox_override("hover",  s)
		_ai_toggle_btn.add_theme_stylebox_override("pressed", s)
		_ai_toggle_btn.add_theme_stylebox_override("focus",  s)


func _refresh_diff_buttons() -> void:
	if not is_instance_valid(_diff_row): return
	var diff_colors := [
		Color(0.1, 0.4, 0.15),
		Color(0.4, 0.35, 0.08),
		Color(0.45, 0.15, 0.08),
		Color(0.35, 0.04, 0.04),
	]
	for child in _diff_row.get_children():
		if not (child is Button): continue
		var n : int = int((child as Button).name.replace("Diff_", ""))
		var active := n == _ai_difficulty
		var col : Color = Color(0.15, 0.38, 0.22) if active else Color(0.12, 0.18, 0.24)
		var s := StyleBoxFlat.new()
		s.bg_color = col; s.set_corner_radius_all(3)
		s.set_border_width_all(2 if not active else 0)
		s.border_color = diff_colors[n - 1]
		(child as Button).add_theme_stylebox_override("normal",  s)
		(child as Button).add_theme_stylebox_override("hover",   s)
		(child as Button).add_theme_stylebox_override("pressed", s)
		(child as Button).add_theme_stylebox_override("focus",   s)


# =============================================================
# OPEN / CLOSE PANELS
# =============================================================
func _open_settings() -> void:
	_settings_open = true
	_settings_panel.visible = true
	_settings_panel.modulate.a = 0.0
	create_tween().tween_property(_settings_panel, "modulate:a", 1.0, 0.2)

func _close_settings() -> void:
	_settings_open = false
	var tw := create_tween()
	tw.tween_property(_settings_panel, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func(): _settings_panel.visible = false)

func _open_splitscreen() -> void:
	_splitscreen_open = true
	_split_panel.visible = true
	_split_panel.modulate.a = 0.0
	create_tween().tween_property(_split_panel, "modulate:a", 1.0, 0.2)

func _close_splitscreen() -> void:
	_splitscreen_open = false
	var tw := create_tween()
	tw.tween_property(_split_panel, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func(): _split_panel.visible = false)

func _open_teamselect() -> void:
	_teamselect_open = true
	_team_panel.visible = true
	_team_panel.modulate.a = 0.0
	_rebuild_player_rows()
	_update_team_warning()
	create_tween().tween_property(_team_panel, "modulate:a", 1.0, 0.2)

func _close_teamselect() -> void:
	_teamselect_open = false
	var tw := create_tween()
	tw.tween_property(_team_panel, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func(): _team_panel.visible = false)
	_open_splitscreen()


# =============================================================
# PLAY ACTIONS
# =============================================================
func _on_play() -> void:
	# Solo: 1 human on team 1, AI on team 2 (if enabled)
	_player_count     = 1
	_team_assignments = { 0: 1 }
	_launch()


func _on_play_splitscreen() -> void:
	_close_splitscreen()
	await get_tree().create_timer(0.18).timeout
	_open_teamselect()


func _on_launch_from_teamselect() -> void:
	# Allow launch even if all humans are on one team — AI covers the other
	_launch()


# =============================================================
# LAUNCH — writes everything to GameSettings then changes scene
# =============================================================
func _launch() -> void:
	if not game_scene:
		push_warning("MainMenu: game_scene not assigned.")
		return

	var gs := get_node_or_null("/root/GameSettings")
	if is_instance_valid(gs):
		gs.player_count     = _player_count
		gs.team_assignments = _team_assignments.duplicate()
		gs.ai_enabled       = _ai_enabled
		gs.ai_difficulty    = _ai_difficulty
		gs.ai_team_id       = _pick_ai_team()
		gs.master_volume    = _master_volume
		gs.music_volume     = _music_volume
		gs.sfx_volume       = _sfx_volume
		gs.fullscreen       = _fullscreen
	else:
		push_warning("MainMenu: GameSettings autoload not found.")

	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		if is_instance_valid(_music): _music.stop()
		get_tree().change_scene_to_packed(game_scene))


func _pick_ai_team() -> int:
	# AI controls whichever team has no human players
	var has_team1 := false
	var has_team2 := false
	for i in range(_player_count):
		var tid : int = _team_assignments.get(i, (i % 2) + 1)
		if tid == 1: has_team1 = true
		if tid == 2: has_team2 = true
	if not has_team2: return 2
	if not has_team1: return 1
	return 2  # default


# =============================================================
# ANIMATE IN
# =============================================================
func _animate_in() -> void:
	var title   : Label         = _main_panel.get_node("Title")
	var sub     : Label         = _main_panel.get_node("Subtitle")
	var buttons : VBoxContainer = _main_panel.get_node("Buttons")
	var tw := create_tween()
	tw.set_parallel(false)
	tw.tween_property(title,   "modulate:a", 1.0, 0.7).set_delay(0.2)
	tw.tween_property(sub,     "modulate:a", 1.0, 0.5).set_delay(0.1)
	tw.tween_property(buttons, "modulate:a", 1.0, 0.5).set_delay(0.15)


# =============================================================
# QUIT
# =============================================================
func _on_quit() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): get_tree().quit())


# =============================================================
# IN-GAME PAUSE (reused as pause menu)
# =============================================================
func show_in_game() -> void:
	visible = true
	get_tree().paused = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)

func hide_in_game() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		visible = false
		get_tree().paused = false)


# =============================================================
# REFRESH BUTTONS
# =============================================================
func _refresh_count_buttons() -> void:
	for child in _count_row.get_children():
		if not (child is Button): continue
		var n      : int = int((child as Button).name.replace("Count_", ""))
		var active : bool = n == _player_count
		var col    := Color(0.15, 0.38, 0.22) if active else Color(0.12, 0.18, 0.24)
		var s := StyleBoxFlat.new()
		s.bg_color = col; s.set_corner_radius_all(4)
		(child as Button).add_theme_stylebox_override("normal",  s)
		(child as Button).add_theme_stylebox_override("hover",   s)
		(child as Button).add_theme_stylebox_override("pressed", s)
		(child as Button).add_theme_stylebox_override("focus",   s)
	_update_layout_preview(_player_count)


# =============================================================
# HELPERS
# =============================================================
func _team_color(tid: int) -> Color:
	return Color(0.2, 0.45, 0.75) if tid == 1 else Color(0.75, 0.25, 0.2)

func _make_team_button(label: String, tid: int, active: bool) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(110, 46)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color(0.92, 0.88, 0.82))
	_style_team_button(btn, tid, active)
	btn.mouse_entered.connect(_play_hover)
	return btn

func _style_team_button(btn: Button, tid: int, active: bool) -> void:
	var tcol := _team_color(tid)
	var s    := StyleBoxFlat.new()
	s.bg_color     = tcol if active else Color(0.12, 0.14, 0.16)
	s.border_color = tcol if not active else Color(0, 0, 0, 0)
	s.set_border_width_all(2 if not active else 0)
	s.set_corner_radius_all(4)
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, s)

func _panel_style(border_color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = Color(0.07, 0.08, 0.09, 0.97)
	s.border_color = border_color
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	return s

func _hsep(col: Color) -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_color_override("color", col)
	return s

func _make_slider_row(label_text: String, initial: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.custom_minimum_size.x = 160
	var slider := HSlider.new()
	slider.min_value = 0.0; slider.max_value = 1.0; slider.step = 0.01
	slider.value     = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(on_change)
	row.add_child(lbl)
	row.add_child(slider)
	return row

func _make_button(text: String, bg: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 54)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color(0.92, 0.88, 0.82))
	var n := StyleBoxFlat.new(); n.bg_color = bg; n.set_corner_radius_all(3); n.content_margin_left = 24
	var h := StyleBoxFlat.new(); h.bg_color = bg.lightened(0.18); h.set_corner_radius_all(3); h.content_margin_left = 24
	var p := StyleBoxFlat.new(); p.bg_color = bg.darkened(0.15);  p.set_corner_radius_all(3); p.content_margin_left = 24
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover",  h)
	btn.add_theme_stylebox_override("pressed", p)
	btn.add_theme_stylebox_override("focus",  n)
	btn.mouse_entered.connect(_play_hover)
	return btn

func _make_small_button(text: String, bg: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 38)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(0.92, 0.88, 0.82))
	var s := StyleBoxFlat.new(); s.bg_color = bg; s.set_corner_radius_all(3); s.content_margin_left = 16
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover",  s)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_stylebox_override("focus",  s)
	btn.mouse_entered.connect(_play_hover)
	return btn

func _make_count_button(label: String, active: bool) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(64, 64)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color(0.92, 0.88, 0.82))
	var col := Color(0.15, 0.38, 0.22) if active else Color(0.12, 0.18, 0.24)
	var s := StyleBoxFlat.new(); s.bg_color = col; s.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover",  s)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_stylebox_override("focus",  s)
	btn.mouse_entered.connect(_play_hover)
	return btn

func _make_diff_button(label: String, _dv: int, active_col: Color) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 36)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color(0.92, 0.88, 0.82))
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.12, 0.14, 0.16)
	s.set_corner_radius_all(3)
	s.set_border_width_all(2)
	s.border_color = active_col
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover",  s)
	btn.add_theme_stylebox_override("pressed", s)
	btn.add_theme_stylebox_override("focus",  s)
	btn.mouse_entered.connect(_play_hover)
	return btn

func _play_hover() -> void:
	if hover_sound and is_instance_valid(_hover_sfx):
		_hover_sfx.stop()
		_hover_sfx.play()
