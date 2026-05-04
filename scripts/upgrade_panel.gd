extends Panel
# =========================================================
# TURRET UPGRADE PANEL
# Builds its own layout entirely in code — no scene tree
# children needed. Just attach this script to a Panel node
# inside a CanvasLayer and it handles everything.
# =========================================================

const PROXIMITY_RANGE: float = 4.0
const CHECK_INTERVAL:  float = 0.15
const WORLD_OFFSET:    Vector3 = Vector3(0, 2.5, 0)

const PANEL_WIDTH:  float = 280.0
const FONT_SIZE_TITLE: int = 18
const FONT_SIZE_STAT:  int = 14
const FONT_SIZE_BTN:   int = 15

# =========================================================
# UI NODES — created in code
# =========================================================
var level_label:     Label
var damage_label:    Label
var fire_rate_label: Label
var range_label:     Label
var cost_label:      Label
var max_level_label: Label
var upgrade_button:  Button
var close_button:    Button

# =========================================================
# STATE
# =========================================================
var selected_turret: Node3D = null
var gm:     Node    = null
var player: Node3D  = null

var _check_timer:     float = 0.0
var _manually_closed: bool  = false

# =========================================================
# READY
# =========================================================
func _ready() -> void:
	add_to_group("turret_upgrade_panel")
	visible = false
	_build_layout()

	if has_node("/root/GameManager"):
		gm = get_node("/root/GameManager")
	else:
		gm = get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		push_error("TurretUpgradePanel: GameManager not found.")

	player = get_tree().get_first_node_in_group("players") as Node3D

# =========================================================
# BUILD LAYOUT IN CODE
# =========================================================
func _build_layout() -> void:
	# ── Panel size & style ───────────────────────────────
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)

	var style := StyleBoxFlat.new()
	style.bg_color        = Color(0.08, 0.08, 0.12, 0.92)
	style.border_color    = Color(0.4, 0.7, 1.0, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left   = 14
	style.content_margin_right  = 14
	style.content_margin_top    = 12
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)

	# ── Root VBox fills the panel ────────────────────────
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# ── Title row: "Turret" label + close X ─────────────
	var title_row := HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(title_row)

	var title_lbl := Label.new()
	title_lbl.text = "TURRET"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", FONT_SIZE_TITLE)
	title_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	title_row.add_child(title_lbl)

	close_button = Button.new()
	close_button.text = "✕"
	close_button.flat = true
	close_button.custom_minimum_size = Vector2(28, 28)
	close_button.add_theme_font_size_override("font_size", FONT_SIZE_TITLE)
	close_button.pressed.connect(_on_close)
	title_row.add_child(close_button)

	# ── Divider ──────────────────────────────────────────
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# ── Stat labels ─────────────────────────────────────
	level_label     = _make_stat_label()
	damage_label    = _make_stat_label()
	fire_rate_label = _make_stat_label()
	range_label     = _make_stat_label()
	vbox.add_child(level_label)
	vbox.add_child(damage_label)
	vbox.add_child(fire_rate_label)
	vbox.add_child(range_label)

	# ── Max level badge ──────────────────────────────────
	max_level_label = Label.new()
	max_level_label.text = "★ MAX LEVEL ★"
	max_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	max_level_label.add_theme_font_size_override("font_size", FONT_SIZE_STAT)
	max_level_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	max_level_label.visible = false
	vbox.add_child(max_level_label)

	# ── Cost label ───────────────────────────────────────
	cost_label = Label.new()
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", FONT_SIZE_STAT)
	cost_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	vbox.add_child(cost_label)

	# ── Upgrade button ───────────────────────────────────
	upgrade_button = Button.new()
	upgrade_button.text = "Upgrade"
	upgrade_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrade_button.custom_minimum_size = Vector2(0, 36)
	upgrade_button.add_theme_font_size_override("font_size", FONT_SIZE_BTN)
	upgrade_button.pressed.connect(_on_upgrade)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.15, 0.5, 0.15)
	btn_style.set_corner_radius_all(6)
	upgrade_button.add_theme_stylebox_override("normal", btn_style)

	var btn_disabled := StyleBoxFlat.new()
	btn_disabled.bg_color = Color(0.25, 0.25, 0.25)
	btn_disabled.set_corner_radius_all(6)
	upgrade_button.add_theme_stylebox_override("disabled", btn_disabled)

	vbox.add_child(upgrade_button)

	# Force panel to fit its content
	reset_size()

func _make_stat_label() -> Label:
	var lbl := Label.new()
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", FONT_SIZE_STAT)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	return lbl

# =========================================================
# PROCESS
# =========================================================
func _process(delta: float) -> void:
	if visible and is_instance_valid(selected_turret):
		_reposition()

	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = CHECK_INTERVAL

	if player == null:
		player = get_tree().get_first_node_in_group("players") as Node3D
	if player == null:
		return

	var nearest: Node3D = _find_nearest_turret()

	if nearest == null:
		if visible:
			_hide_panel()
		_manually_closed = false
		selected_turret  = null
		return

	if _manually_closed and nearest == selected_turret:
		return

	if nearest != selected_turret or not visible:
		_manually_closed = false
		_open(nearest)

	_refresh_button_state()

# =========================================================
# REPOSITION
# =========================================================
func _reposition() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	var world_pos: Vector3 = selected_turret.global_position + WORLD_OFFSET

	if camera.is_position_behind(world_pos):
		modulate.a = 0.0
		return
	modulate.a = 1.0

	var screen_pos: Vector2 = camera.unproject_position(world_pos)

	# Centre horizontally, bottom edge at the projected point
	position = Vector2(
		screen_pos.x - size.x * 0.5,
		screen_pos.y - size.y
	)

# =========================================================
# FIND NEAREST TURRET
# =========================================================
func _find_nearest_turret() -> Node3D:
	var best:      Node3D = null
	var best_dist: float  = PROXIMITY_RANGE

	for turret in get_tree().get_nodes_in_group("turrets"):
		if not turret is Node3D:
			continue
		if "team_id" in turret and "team_id" in player:
			if turret.team_id != player.team_id:
				continue
		var dist: float = player.global_position.distance_to(turret.global_position)
		if dist < best_dist:
			best_dist = dist
			best      = turret

	return best

# =========================================================
# OPEN
# =========================================================
func _open(turret: Node3D) -> void:
	selected_turret = turret
	visible = true
	_update_ui()
	reset_size()       # recalc height to fit content
	_reposition()      # snap before first frame

func open(turret: Node3D) -> void:
	_open(turret)

# =========================================================
# HIDE / CLOSE
# =========================================================
func _hide_panel() -> void:
	visible = false

func close() -> void:
	selected_turret = null
	visible = false

# =========================================================
# UPDATE UI
# =========================================================
func _update_ui() -> void:
	if not is_instance_valid(selected_turret):
		visible = false
		return

	var t := selected_turret
	var at_max: bool = t.level >= t.max_level

	level_label.text     = "Level:      %d / %d" % [t.level, t.max_level]
	damage_label.text    = "Damage:     %.0f" % t.damage
	var sps: float = 1.0 / max(t.fire_rate, 0.01)
	fire_rate_label.text = "Fire Rate:  %.2f / s" % sps
	range_label.text     = "Range:      %.1f" % t.range

	max_level_label.visible = at_max

	if at_max:
		cost_label.text         = "Fully Upgraded"
		upgrade_button.disabled = true
	else:
		cost_label.text         = "Upgrade Cost:  %d 💰" % t.get_upgrade_cost()
		_refresh_button_state()

func _refresh_button_state() -> void:
	if not is_instance_valid(upgrade_button) or not is_instance_valid(selected_turret):
		return
	if selected_turret.level >= selected_turret.max_level:
		upgrade_button.disabled = true
		return
	if gm == null:
		return

	var cost: int = selected_turret.get_upgrade_cost()
	var can_buy: bool = false

	if gm.has_method("get_gold"):
		var team: int = selected_turret.team_id if "team_id" in selected_turret else 1
		can_buy = gm.get_gold(team) >= cost
	elif gm.has_method("can_afford"):
		can_buy = gm.can_afford(cost)

	upgrade_button.disabled = not can_buy

# =========================================================
# UPGRADE BUTTON
# =========================================================
func _on_upgrade() -> void:
	if not is_instance_valid(selected_turret) or gm == null:
		return
	if selected_turret.level >= selected_turret.max_level:
		return

	var cost: int = selected_turret.get_upgrade_cost()
	var paid: bool = false

	if gm.has_method("spend_gold"):
		var team: int = selected_turret.team_id if "team_id" in selected_turret else 1
		paid = gm.spend_gold(team, cost)
	elif gm.has_method("spend_money"):
		paid = gm.spend_money(cost)

	if paid:
		selected_turret.upgrade()
		_update_ui()
	else:
		print("TurretUpgradePanel: Not enough gold!")

# =========================================================
# CLOSE BUTTON
# =========================================================
func _on_close() -> void:
	_manually_closed = true
	_hide_panel()
