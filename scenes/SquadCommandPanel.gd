# ============================================================
# SquadCommandPanel.gd
# ============================================================
# Attach as a child of your HUD Control node.
# Positions itself at the bottom center (above ability bar).
# Replaces the old squad strip that was inside hud.gd.
#
# Features:
#   - SELECT ALL [G] button
#   - ATTACK / DEFEND / PATROL / STAY / FOLLOW buttons [1-5]
#   - Defend immediately rallies to base — no click needed
#   - Follow has interrupt priority
#   - Patrol collects waypoints then sends on second press / ESC
#   - Box-select and single-click select via Z mode
#   - Shows selected count
# ============================================================
extends Control

# ── SINGLETON GUARD ──────────────────────────────────────────
const _GROUP := "squad_command_panel"

func _enter_tree() -> void:
	var existing := get_tree().get_nodes_in_group(_GROUP)
	for n in existing:
		if is_instance_valid(n) and n != self:
			queue_free(); return
	add_to_group(_GROUP)

var player      : Node  = null
var _team_id    : int   = 1
var _device_id  : int   = -1
var _player_iid : int   = -1
var _horde_mgr          = null

const DEFEND_RALLY_OFFSET : float = 4.0

var _pending_command  : String = ""
var _patrol_waypoints : Array  = []
var _in_patrol_set    : bool   = false

# UI refs
var _count_label  : Label
var _status_label : Label
var _sel_btn      : Button
var _atk_btn      : Button
var _def_btn      : Button
var _pat_btn      : Button
var _stay_btn     : Button
var _follow_btn   : Button
var _box_rect     : ColorRect

# Box select
var _box_selecting : bool    = false
var _box_start     : Vector2 = Vector2.ZERO

const C_ATTACK  := Color(0.85, 0.25, 0.10)
const C_DEFEND  := Color(0.20, 0.45, 0.85)
const C_PATROL  := Color(0.20, 0.75, 0.45)
const C_STAY    := Color(0.45, 0.45, 0.50)
const C_FOLLOW  := Color(0.75, 0.55, 0.20)
const C_SELECT  := Color(0.15, 0.55, 0.25)


func _ready() -> void:
	# Try new HordeManager first, then legacy ZombieHordeManager
	_horde_mgr = get_tree().get_first_node_in_group("horde_manager")
	if not is_instance_valid(_horde_mgr):
		_horde_mgr = get_tree().get_first_node_in_group("zombie_horde_manager")
	if not is_instance_valid(_horde_mgr) and Engine.has_singleton("ZombieHordeManager"):
		_horde_mgr = Engine.get_singleton("ZombieHordeManager")
	if is_instance_valid(_horde_mgr) and _horde_mgr.has_signal("selection_changed"):
		_horde_mgr.selection_changed.connect(_on_selection_changed)
	_build_ui()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind_player(p: Node) -> void:
	player      = p
	_team_id    = int(p.get("team_id")   if "team_id"   in p else 1)
	_device_id  = int(p.get("device_id") if "device_id" in p else -1)
	_player_iid = p.get_instance_id()
	_refresh_count()


# ============================================================
# BUILD UI — bottom center strip
# ============================================================
func _build_ui() -> void:
	# Sits at very bottom of screen — below ability bar (which is at 0.780-0.855)
	anchor_left   = 0.0; anchor_right  = 1.0
	anchor_top    = 0.86; anchor_bottom = 1.0
	offset_top    = 0.0;  offset_bottom = 0.0
	offset_left   = 0.0;  offset_right  = 0.0
	mouse_filter  = Control.MOUSE_FILTER_IGNORE

	# Outer panel — full width, dark tinted
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.94)
	style.border_color = Color(0.15, 0.55, 0.32, 0.8)
	style.set_border_width_all(1)
	style.border_width_top = 2
	style.set_corner_radius_all(0)
	style.content_margin_left = 10; style.content_margin_right  = 10
	style.content_margin_top  = 5;  style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var root_row := HBoxContainer.new()
	root_row.add_theme_constant_override("separation", 8)
	root_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(root_row)

	# ── LEFT: count + select ─────────────────────────────────
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 2)
	left_col.custom_minimum_size = Vector2(110, 0)
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_row.add_child(left_col)

	_count_label = Label.new()
	_count_label.text = "🧟  0 selected"
	_count_label.add_theme_font_size_override("font_size", 11)
	_count_label.add_theme_color_override("font_color", Color(0.35, 0.90, 0.55))
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(_count_label)

	_sel_btn = _make_btn("SELECT ALL  [G]", C_SELECT, _on_select_all)
	_sel_btn.custom_minimum_size = Vector2(110, 24)
	_sel_btn.add_theme_font_size_override("font_size", 10)
	left_col.add_child(_sel_btn)

	# ── CENTER: command buttons ───────────────────────────────
	var center_col := VBoxContainer.new()
	center_col.add_theme_constant_override("separation", 3)
	center_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_row.add_child(center_col)

	# Help hint row
	var hint := Label.new()
	hint.text = "SQUAD COMMANDS  —  select zombies with [G] then issue orders below"
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.42, 0.46, 0.54))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_col.add_child(hint)

	var cmd_row := HBoxContainer.new()
	cmd_row.add_theme_constant_override("separation", 5)
	cmd_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_col.add_child(cmd_row)

	_atk_btn    = _make_btn("⚔  ATTACK [1]
Rush nearest enemy", C_ATTACK, _on_attack)
	_def_btn    = _make_btn("🛡  DEFEND [2]
Rally to your base", C_DEFEND, _on_defend)
	_pat_btn    = _make_btn("↺  PATROL [3]
Click waypoints", C_PATROL, _on_patrol)
	_stay_btn   = _make_btn("■  HOLD [4]
Hold position", C_STAY, _on_stay)
	_follow_btn = _make_btn("👤  FOLLOW [5]
Follow you", C_FOLLOW, _on_follow)

	for b in [_atk_btn, _def_btn, _pat_btn, _stay_btn, _follow_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size   = Vector2(0, 42)
		b.add_theme_font_size_override("font_size", 10)
		cmd_row.add_child(b)

	# ── RIGHT: status ─────────────────────────────────────────
	var right_col := VBoxContainer.new()
	right_col.custom_minimum_size = Vector2(120, 0)
	right_col.add_theme_constant_override("separation", 2)
	right_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_row.add_child(right_col)

	var status_head := Label.new()
	status_head.text = "STATUS"
	status_head.add_theme_font_size_override("font_size", 9)
	status_head.add_theme_color_override("font_color", Color(0.35, 0.38, 0.45))
	right_col.add_child(status_head)

	_status_label = Label.new()
	_status_label.text = "Press [G] to
select all zombies"
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.90))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	right_col.add_child(_status_label)

	# Box-select overlay
	_box_rect              = ColorRect.new()
	_box_rect.color        = Color(0.3, 0.7, 1.0, 0.14)
	_box_rect.visible      = false
	_box_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	call_deferred("_attach_box_rect")


func _attach_box_rect() -> void:
	get_tree().current_scene.add_child(_box_rect)


# ============================================================
# INPUT
# ============================================================
func _is_my_event(event: InputEvent) -> bool:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return event.device == _device_id
	return _device_id == -1


func _input(event: InputEvent) -> void:
	if not _is_my_event(event): return
	if not is_instance_valid(player): return
	# Don't eat input while shop or talent tree is open
	if player.get("shop_open") == true: return
	if player.get("_talent_tree_open") == true: return

	if event is InputEventKey and event.pressed and not event.is_echo():
		match (event as InputEventKey).keycode:
			KEY_G:      _on_select_all();   get_viewport().set_input_as_handled()
			KEY_1:      _on_attack();        get_viewport().set_input_as_handled()
			KEY_2:      _on_defend();        get_viewport().set_input_as_handled()
			KEY_3:      _on_patrol();        get_viewport().set_input_as_handled()
			KEY_4:      _on_stay();          get_viewport().set_input_as_handled()
			KEY_5:      _on_follow();        get_viewport().set_input_as_handled()
			KEY_ESCAPE: _cancel_pending();   get_viewport().set_input_as_handled()

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed: _on_lmb_down(mb.position)
			else:          _on_lmb_up(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_cancel_pending()

	if event is InputEventMouseMotion and _box_selecting:
		_update_box((event as InputEventMouseMotion).position)


# ============================================================
# BOX SELECT
# ============================================================
func _on_lmb_down(pos: Vector2) -> void:
	if _pending_command != "":
		_execute_pending_at_screen(pos); return
	_box_selecting = true
	_box_start     = pos
	if is_instance_valid(_box_rect):
		_box_rect.visible  = true
		_box_rect.position = pos
		_box_rect.size     = Vector2.ZERO


func _on_lmb_up(pos: Vector2) -> void:
	if not _box_selecting: return
	_box_selecting = false
	if is_instance_valid(_box_rect): _box_rect.visible = false
	if pos.distance_to(_box_start) < 8.0:
		_select_at_point(_box_start); return
	if not is_instance_valid(_horde_mgr): return
	var cam := _get_cam(); if not cam: return
	var vp  := get_viewport().get_visible_rect().size
	_horde_mgr.select_box(cam,
		Vector2(minf(_box_start.x,pos.x)/vp.x, minf(_box_start.y,pos.y)/vp.y),
		Vector2(maxf(_box_start.x,pos.x)/vp.x, maxf(_box_start.y,pos.y)/vp.y),
		_team_id)


func _update_box(pos: Vector2) -> void:
	if not is_instance_valid(_box_rect): return
	_box_rect.position = Vector2(minf(_box_start.x,pos.x), minf(_box_start.y,pos.y))
	_box_rect.size     = Vector2(absf(pos.x-_box_start.x),  absf(pos.y-_box_start.y))


func _select_at_point(sp: Vector2) -> void:
	var cam := _get_cam(); if not cam: return
	var space := get_viewport().get_world_3d().direct_space_state
	if not space: return
	var q   := PhysicsRayQueryParameters3D.create(
		cam.project_ray_origin(sp),
		cam.project_ray_origin(sp) + cam.project_ray_normal(sp) * 200.0)
	var hit := space.intersect_ray(q)
	if hit.is_empty(): return
	var z   := hit.get("collider") as Node
	while is_instance_valid(z) and z != get_tree().current_scene:
		if "team_id" in z and "health" in z and int(z.team_id) == _team_id:
			if is_instance_valid(_horde_mgr):
				_horde_mgr.deselect_all()
				_horde_mgr.select_in_radius(z.global_position, 0.1, _team_id)
			return
		z = z.get_parent()


# ============================================================
# PENDING (attack / patrol)
# ============================================================
func _execute_pending_at_screen(sp: Vector2) -> void:
	var pos := _screen_to_ground(sp)
	if pos == Vector3.ZERO: _cancel_pending(); return
	match _pending_command:
		"attack":
			if is_instance_valid(_horde_mgr): _horde_mgr.command_attack(pos)
			_set_status("⚔ Attacking!"); _pending_command = ""; _unhighlight_all()
		"patrol_add":
			_patrol_waypoints.append(pos)
			_set_status("↺ Waypoint %d. Press [3]/ESC to send." % _patrol_waypoints.size())


func _cancel_pending() -> void:
	if _pending_command == "patrol_add" and not _patrol_waypoints.is_empty():
		if is_instance_valid(_horde_mgr): _horde_mgr.command_patrol(_patrol_waypoints)
		_set_status("↺ Patrol: %d points set." % _patrol_waypoints.size())
	_patrol_waypoints.clear(); _pending_command = ""; _in_patrol_set = false
	_unhighlight_all()


# ============================================================
# COMMANDS
# ============================================================
func _on_select_all() -> void:
	if not is_instance_valid(_horde_mgr): return
	_horde_mgr.select_all_team(_team_id)
	var n : int = _horde_mgr.get_selected().size()
	if n == 0:
		_horde_mgr.select_owned_by(_player_iid)
		n = _horde_mgr.get_selected().size()
	_set_status("🧟 %d zombies selected." % n)
	_refresh_count(n)


func _on_attack() -> void:
	_auto_select_if_empty()
	if _get_sel().is_empty(): _set_status("No zombies!"); return
	_cancel_pending()
	# If an enemy is nearby, attack immediately. Otherwise wait for click.
	var nearest := _find_nearest_enemy()
	if is_instance_valid(nearest):
		# Route through AIDirector if available for flow field updates
		var _director = null
		if Engine.has_singleton("AIDirector"):
			_director = Engine.get_singleton("AIDirector")
		if is_instance_valid(_director) and _director.has_method("director_attack"):
			_director.director_attack(nearest.global_position, _team_id)
		elif is_instance_valid(_horde_mgr):
			_horde_mgr.command_attack(nearest.global_position)
		_set_status("⚔ %d attacking!" % _get_sel().size())
	else:
		_set_status("⚔ Click target to attack…")
		_pending_command = "attack"
		_highlight_btn(_atk_btn)


func _on_defend() -> void:
	_auto_select_if_empty()
	if _get_sel().is_empty(): _set_status("No zombies!"); return
	_cancel_pending()
	var base_pos := _get_base_pos()
	if base_pos == Vector3.ZERO and is_instance_valid(player):
		base_pos = (player as Node3D).global_position
	if is_instance_valid(_horde_mgr): _horde_mgr.command_defend(base_pos)
	_set_status("🛡 %d defending base!" % _get_sel().size())
	_highlight_btn(_def_btn)


func _on_patrol() -> void:
	_auto_select_if_empty()
	if _get_sel().is_empty(): _set_status("No zombies!"); return
	if not _in_patrol_set:
		_cancel_pending()
		_in_patrol_set = true; _patrol_waypoints.clear()
		_pending_command = "patrol_add"
		_set_status("↺ Click waypoints. [3]/ESC to finish.")
		_highlight_btn(_pat_btn)
	else:
		_cancel_pending()


func _on_stay() -> void:
	_auto_select_if_empty()
	if _get_sel().is_empty(): _set_status("No zombies!"); return
	_cancel_pending()
	if is_instance_valid(_horde_mgr): _horde_mgr.command_stay()
	_set_status("■ %d holding position." % _get_sel().size()); _unhighlight_all()


func _on_follow() -> void:
	_auto_select_if_empty()
	if _get_sel().is_empty(): _set_status("No zombies!"); return
	_cancel_pending()
	if is_instance_valid(_horde_mgr) and is_instance_valid(player):
		if _horde_mgr.has_method("command_follow_interrupt"):
			_horde_mgr.command_follow_interrupt(player as Node3D)
		else:
			_horde_mgr.command_follow(player as Node3D)
	_set_status("👤 %d following!" % _get_sel().size()); _highlight_btn(_follow_btn)


func handle_gamepad_command(mode_index: int) -> void:
	match mode_index:
		0: _on_attack()
		1: _on_defend()
		2: _on_patrol()
		3: _on_stay()
		4: _on_follow()


# ============================================================
# SIGNALS / HELPERS
# ============================================================
func _on_selection_changed(selected: Array) -> void:
	_refresh_count(selected.size())


func _get_sel() -> Array:
	if not is_instance_valid(_horde_mgr): return []
	return _horde_mgr.get_selected()


func _auto_select_if_empty() -> void:
	if not _get_sel().is_empty(): return
	if not is_instance_valid(_horde_mgr): return
	_horde_mgr.select_all_team(_team_id)
	# Fallback: if team select got nothing (team_id not set on zombies)
	if _horde_mgr.get_selected().is_empty():
		_horde_mgr.select_owned_by(_player_iid)


func _refresh_count(n: int = -1) -> void:
	if n < 0: n = _get_sel().size()
	if is_instance_valid(_count_label):
		_count_label.text = "🧟 %d selected" % n


func _set_status(text: String) -> void:
	if is_instance_valid(_status_label): _status_label.text = text


func _get_cam() -> Camera3D:
	if is_instance_valid(player):
		# Try common camera paths
		for path in ["CameraRoot/FPSPivot/FPSCamera","CameraRoot/FPSPivot/Camera3D",
					 "CameraRoot/TopDownPivot/TopDownCamera","Head/Camera3D"]:
			var cam := player.get_node_or_null(path) as Camera3D
			if is_instance_valid(cam) and cam.current: return cam
	return get_viewport().get_camera_3d()


func _screen_to_ground(sp: Vector2) -> Vector3:
	var cam := _get_cam(); if not cam: return Vector3.ZERO
	var space := get_viewport().get_world_3d().direct_space_state
	if not space: return Vector3.ZERO
	var q   := PhysicsRayQueryParameters3D.create(
		cam.project_ray_origin(sp),
		cam.project_ray_origin(sp) + cam.project_ray_normal(sp) * 300.0)
	return space.intersect_ray(q).get("position", Vector3.ZERO)


func _get_base_pos() -> Vector3:
	for b in get_tree().get_nodes_in_group("bases"):
		if not is_instance_valid(b): continue
		if "team_id" in b and int(b.get("team_id")) == _team_id:
			if b is Node3D:
				var fwd := -(b as Node3D).global_transform.basis.z
				return (b as Node3D).global_position + fwd * DEFEND_RALLY_OFFSET
	return Vector3.ZERO


func _find_nearest_enemy() -> Node3D:
	if not is_instance_valid(player): return null
	var origin : Vector3 = (player as Node3D).global_position
	var best   : Node3D  = null
	var best_d : float   = 60.0
	var candidates : Array = []
	candidates.append_array(get_tree().get_nodes_in_group("units"))
	candidates.append_array(get_tree().get_nodes_in_group("minions"))
	for u in candidates:
		if not is_instance_valid(u) or not ("team_id" in u): continue
		if int(u.get("team_id")) == _team_id: continue
		if u.has_method("is_dead") and u.is_dead(): continue
		var d : float = origin.distance_to((u as Node3D).global_position)
		if d < best_d: best_d = d; best = u as Node3D
	return best


func _make_btn(text: String, color: Color, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_color_override("font_color", Color(0.92, 0.88, 0.82))
	btn.focus_mode   = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var s := StyleBoxFlat.new()
	s.bg_color = color * Color(1,1,1,0.68); s.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal",  s)
	btn.add_theme_stylebox_override("pressed", s)
	var h := StyleBoxFlat.new()
	h.bg_color = color; h.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("hover", h)
	btn.pressed.connect(cb)
	return btn


func _highlight_btn(btn: Button) -> void:
	_unhighlight_all()
	if not is_instance_valid(btn): return
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.9, 0.9, 0.2, 0.92); s.set_corner_radius_all(3)
	s.set_border_width_all(2); s.border_color = Color.WHITE
	btn.add_theme_stylebox_override("normal", s)


func _unhighlight_all() -> void:
	var pairs := [[_atk_btn,C_ATTACK],[_def_btn,C_DEFEND],[_pat_btn,C_PATROL],
				  [_stay_btn,C_STAY],[_follow_btn,C_FOLLOW]]
	for pair in pairs:
		var btn : Button = pair[0]; if not is_instance_valid(btn): continue
		var s := StyleBoxFlat.new()
		s.bg_color = (pair[1] as Color) * Color(1,1,1,0.68); s.set_corner_radius_all(3)
		btn.add_theme_stylebox_override("normal", s)


func has_pending_command() -> bool:
	return _pending_command != ""

func get_count_label() -> Label:
	return _count_label

func get_status_label() -> Label:
	return _status_label
