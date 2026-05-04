# ============================================================
# shop.gd  —  Full Rewrite (Godot 4.x)
# ============================================================
# BEHAVIOURS
# ─────────────────────────────────────────────────────────────
# Tab (ground)       → arc camera up, show shop panel
# Tab (panel open)   → hide panel, enter top-down play mode
# Tab (play mode)    → reopen panel
# Escape (play mode) → reopen panel
# Escape (panel open)→ arc camera back down, resume FPS
# LMB (play mode)    → fire weapon toward mouse (hold to auto)
# R                  → reload (forwarded to WeaponManager)
# ============================================================
extends Control
class_name ShopUI

# ───────────────────────────────────────────────────────────────
# CONSTANTS
# ───────────────────────────────────────────────────────────────
const TAB_TURRETS    := 0
const TAB_PLAYER_UPG := 1
const TAB_CREEP_UPG  := 2
const TAB_CREEPS     := 3
const TAB_NAMES      := ["Turrets", "Player Upgrades", "Creep Upgrades", "Creeps"]
const BTN_MIN_HEIGHT := 56

const TOPDOWN_HEIGHT   := 20.0
const SKY_HEIGHT       := 80.0
const TOPDOWN_FOV      := 60.0
const RISE_DURATION    := 0.45   # ground → sky
const PAN_DURATION     := 0.35   # sky    → overhead (and back)
const DROP_DURATION    := 0.45   # sky    → ground

const GHOST_ALPHA      := 0.45
const SHOP_PANEL_ALPHA := 0.82

const MAX_TURRET_DISTANCE := 30.0
const CREEP_ORBIT_RADIUS  := 1.8
const CREEP_ANGLE_SPREAD  := 0.55

# ───────────────────────────────────────────────────────────────
# EXPORTS
# ───────────────────────────────────────────────────────────────
@export var turret_scenes : Array[PackedScene] = []
@export var turret_costs  : Array[int]         = [500]

@export var attack_creep_scenes : Array[PackedScene] = []
@export var attack_creep_labels : Array[String]      = []
@export var attack_creep_costs  : Array[int]         = []

@export var defend_creep_scenes : Array[PackedScene] = []
@export var defend_creep_labels : Array[String]      = []
@export var defend_creep_costs  : Array[int]         = []

@export var creep_spawn_count : int = 1

# ───────────────────────────────────────────────────────────────
# UPGRADE TABLES
# ───────────────────────────────────────────────────────────────
const PLAYER_UPGRADES : Array = [
	{ "label": "Max Health +50",    "stat": "max_health", "amount": 50   },
	{ "label": "Move Speed +10%",   "stat": "move_speed", "amount": 0.10 },
	{ "label": "Rate of Fire +10%", "stat": "fire_rate",  "amount": 0.10 },
	{ "label": "Damage +5",         "stat": "damage",     "amount": 5    },
]
const PLAYER_UPGRADE_COSTS : Array = [150, 200, 250, 300]

const CREEP_UPGRADES : Array = [
	{ "label": "Zombie Health +50",       "stat": "health",       "amount": 50   },
	{ "label": "Zombie Attack Speed +5%", "stat": "attack_speed", "amount": 0.05 },
	{ "label": "Zombie Damage +10",       "stat": "damage",       "amount": 10   },
]
const CREEP_UPGRADE_COSTS : Array = [150, 200, 250]

const BASE_UPGRADES : Array = [
	{ "label": "Base Health +100", "amount": 100 },
	{ "label": "Base Health +250", "amount": 250 },
	{ "label": "Base Health +500", "amount": 500 },
]
const BASE_UPGRADE_COSTS : Array = [200, 400, 700]

# ───────────────────────────────────────────────────────────────
# CAMERA ARC STATE
# ───────────────────────────────────────────────────────────────
# Phases:
#   0 = idle
#   1 = rising   (FPS pos → sky above FPS)
#   2 = panning  (sky → overhead player)
#   3 = repanning (overhead → sky above FPS)
#   4 = dropping (sky → FPS pos)
enum ArcPhase { IDLE, RISE, PAN_TO_TOP, PAN_TO_SKY, DROP }

var _arc_phase     : ArcPhase = ArcPhase.IDLE
var _arc_t         : float    = 0.0

# Snapshot of where the FPS camera was when we started the arc
var _fps_saved_pos : Vector3 = Vector3.ZERO
var _fps_saved_rot : Vector3 = Vector3.ZERO
var _fps_saved_fov : float   = 75.0

# The dynamic overhead camera we create/destroy each session
var _td_cam        : Camera3D = null

# ───────────────────────────────────────────────────────────────
# SESSION STATE
# ───────────────────────────────────────────────────────────────
var _topdown_active : bool = false  # true while overhead cam is live
var _play_mode      : bool = false  # true while panel is hidden, player is moving/shooting
var _is_firing      : bool = false

# ───────────────────────────────────────────────────────────────
# PLACEMENT / ATTACK STATE
# ───────────────────────────────────────────────────────────────
var _placement_mode       : bool        = false
var _placement_scene      : PackedScene = null
var _current_turret_index : int         = -1
var _attack_target_mode   : bool        = false

var _ghost          : Node3D             = null
var _ghost_material : StandardMaterial3D = null

# ───────────────────────────────────────────────────────────────
# SCENE / NODE REFERENCES
# ───────────────────────────────────────────────────────────────
var game_manager    : Node      = null
var player          : Node      = null
var _fps_cam        : Camera3D  = null   # the player's FPS camera
var hud             : Node      = null

var _player_team_id     : int = 1
var _player_instance_id : int = -1

# ───────────────────────────────────────────────────────────────
# UI REFS
# ───────────────────────────────────────────────────────────────
var shop_panel           : Panel
var tab_container        : TabContainer
var status_label         : Label
var tab_hint_label       : Label
var gold_label           : Label
var placement_hint_label : Label

# Keyboard nav
var _tab_buttons   : Array             = [[], [], [], []]
var _all_buttons   : Array[Dictionary] = []
var _focused_tab   : int               = 0
var _focused_index : int               = 0

# Creep picker
var _creep_catalogue       : Array[Dictionary] = []
var _picker_selected_index : int               = -1
var _patrol_editor         : PatrolEditor       = null

var _picker_rows_vbox  : VBoxContainer
var _picker_detail     : PanelContainer
var _picker_name_lbl   : Label
var _picker_desc_lbl   : Label
var _picker_cost_lbl   : Label
var _picker_confirm    : Button
var _picker_cmd_attack : Button
var _picker_cmd_defend : Button
var _picker_cmd_patrol : Button
var _picker_cmd_stay   : Button
var _picker_gold_lbl   : Label
var _picker_squad_lbl  : Label
var _picker_row_btns   : Array[Button] = []

# Aim
var _aim_dir : Vector3 = Vector3(0, 0, -1)

# ═══════════════════════════════════════════════════════════════
# READY
# ═══════════════════════════════════════════════════════════════
func _ready() -> void:
	add_to_group("shop")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	await get_tree().process_frame

	game_manager = get_tree().get_first_node_in_group("game_manager")
	player       = get_tree().get_first_node_in_group("players")
	hud          = get_tree().get_first_node_in_group("ui_hud")

	if player:
		_player_team_id     = player.team_id if "team_id" in player else 1
		_player_instance_id = player.get_instance_id()
		_fps_cam            = _find_player_camera()

	_build_shop_ui()
	_build_all_tabs()
	close_shop()
	_init_patrol_editor()

	print("[Shop] ready — player=%s team=%d" % [str(player), _player_team_id])

# ───────────────────────────────────────────────────────────────
# FIND PLAYER CAMERA
# ───────────────────────────────────────────────────────────────
func _find_player_camera() -> Camera3D:
	if not player: return get_viewport().get_camera_3d()
	# Look inside Head node first
	var head := player.get_node_or_null("Head")
	if head:
		for c in head.get_children():
			if c is Camera3D: return c as Camera3D
	# Then direct children
	for c in player.get_children():
		if c is Camera3D: return c as Camera3D
	return get_viewport().get_camera_3d()

# ───────────────────────────────────────────────────────────────
# ACTIVE CAMERA (used for raycasts)
# ───────────────────────────────────────────────────────────────
func _active_cam() -> Camera3D:
	if is_instance_valid(_td_cam) and _td_cam.current:
		return _td_cam
	if is_instance_valid(_fps_cam):
		return _fps_cam
	return get_viewport().get_camera_3d()

# ═══════════════════════════════════════════════════════════════
# PROCESS
# ═══════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	# ── Camera arc animation ──
	_tick_arc(delta)

	# ── Keep overhead cam locked above player ──
	if _arc_phase == ArcPhase.IDLE and _topdown_active and is_instance_valid(_td_cam) and player:
		_td_cam.global_position = (player as Node3D).global_position + Vector3(0, TOPDOWN_HEIGHT, 0)

	# ── Ghost turret preview ──
	if _placement_mode and is_instance_valid(_ghost) and _topdown_active:
		var hit = _raycast_ground()
		if hit is Vector3:
			_ghost.global_position = hit
			_set_ghost_tint(_is_placement_valid(hit))
			_ghost.visible = true
		else:
			_ghost.visible = false

	# ── Top-down play mode ──
	if _play_mode and is_instance_valid(player):
		_drive_movement(delta)
		_update_aim_from_mouse()
		if _is_firing:
			_do_fire()

	# ── Shop panel refresh ──
	if shop_panel and shop_panel.visible:
		_refresh_button_states()
		_refresh_gold_label()
		_refresh_picker_gold()

# ═══════════════════════════════════════════════════════════════
# CAMERA ARC
# ═══════════════════════════════════════════════════════════════

## Begin the open arc: snapshot FPS cam, create TD cam, start rising.
func _arc_begin_open() -> void:
	if not is_instance_valid(_fps_cam) or not player: return
	if _arc_phase != ArcPhase.IDLE: return

	# Snapshot
	_fps_saved_pos = _fps_cam.global_position
	_fps_saved_rot = _fps_cam.global_rotation
	_fps_saved_fov = _fps_cam.fov

	# Create the topdown camera parented to the scene root
	_td_cam           = Camera3D.new()
	_td_cam.fov       = _fps_saved_fov
	get_tree().current_scene.add_child(_td_cam)
	_td_cam.global_position = _fps_saved_pos
	_td_cam.global_rotation = _fps_saved_rot

	# Switch active camera
	_fps_cam.current = false
	_td_cam.current  = true

	_arc_phase = ArcPhase.RISE
	_arc_t     = 0.0

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if player and "ui_opened" in player: player.ui_opened = true

## Begin the close arc: start panning back from overhead toward sky.
func _arc_begin_close() -> void:
	if _arc_phase != ArcPhase.IDLE: return
	if not _topdown_active: return

	# Hide everything before arc starts
	shop_panel.visible = false
	_play_mode         = false
	_is_firing         = false
	if player and "topdown_mode" in player: player.topdown_mode = false

	_arc_phase = ArcPhase.PAN_TO_SKY
	_arc_t     = 0.0

func _tick_arc(delta: float) -> void:
	if _arc_phase == ArcPhase.IDLE or not is_instance_valid(_td_cam) or not player:
		return

	var player3d := player as Node3D
	_arc_t = move_toward(_arc_t, 1.0, delta / _arc_phase_duration())

	match _arc_phase:
		ArcPhase.RISE:
			# FPS position → sky above FPS position
			var sky_pos := Vector3(_fps_saved_pos.x, _fps_saved_pos.y + SKY_HEIGHT, _fps_saved_pos.z)
			var ts      := smoothstep(0.0, 1.0, _arc_t)
			_td_cam.global_position = _fps_saved_pos.lerp(sky_pos, ts)
			_td_cam.global_rotation = Vector3(
				lerp_angle(_fps_saved_rot.x, deg_to_rad(-90.0), ts),
				_fps_saved_rot.y,
				0.0
			)
			_td_cam.fov = lerpf(_fps_saved_fov, TOPDOWN_FOV, ts)

			if _arc_t >= 1.0:
				_arc_phase = ArcPhase.PAN_TO_TOP
				_arc_t     = 0.0

		ArcPhase.PAN_TO_TOP:
			# Sky above FPS → overhead player
			var sky_pos  := Vector3(_fps_saved_pos.x, _fps_saved_pos.y + SKY_HEIGHT, _fps_saved_pos.z)
			var over_pos := player3d.global_position + Vector3(0, TOPDOWN_HEIGHT, 0)
			var ts       := smoothstep(0.0, 1.0, _arc_t)
			_td_cam.global_position = sky_pos.lerp(over_pos, ts)
			_td_cam.global_rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
			_td_cam.fov             = TOPDOWN_FOV

			if _arc_t >= 1.0:
				_arc_phase      = ArcPhase.IDLE
				_arc_t          = 0.0
				_topdown_active = true
				_on_arc_open_complete()

		ArcPhase.PAN_TO_SKY:
			# Overhead player → sky above FPS
			var sky_pos  := Vector3(_fps_saved_pos.x, _fps_saved_pos.y + SKY_HEIGHT, _fps_saved_pos.z)
			var over_pos := player3d.global_position + Vector3(0, TOPDOWN_HEIGHT, 0)
			var ts       := smoothstep(0.0, 1.0, _arc_t)
			_td_cam.global_position = over_pos.lerp(sky_pos, ts)
			_td_cam.global_rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
			_td_cam.fov             = TOPDOWN_FOV

			if _arc_t >= 1.0:
				_arc_phase = ArcPhase.DROP
				_arc_t     = 0.0

		ArcPhase.DROP:
			# Sky above FPS → FPS position
			var sky_pos := Vector3(_fps_saved_pos.x, _fps_saved_pos.y + SKY_HEIGHT, _fps_saved_pos.z)
			var ts      := smoothstep(0.0, 1.0, _arc_t)
			_td_cam.global_position = sky_pos.lerp(_fps_saved_pos, ts)
			_td_cam.global_rotation = Vector3(
				lerp_angle(deg_to_rad(-90.0), _fps_saved_rot.x, ts),
				_fps_saved_rot.y,
				0.0
			)
			_td_cam.fov = lerpf(TOPDOWN_FOV, _fps_saved_fov, ts)

			if _arc_t >= 1.0:
				_arc_phase      = ArcPhase.IDLE
				_arc_t          = 0.0
				_topdown_active = false
				_on_arc_close_complete()

func _arc_phase_duration() -> float:
	match _arc_phase:
		ArcPhase.RISE:       return RISE_DURATION
		ArcPhase.PAN_TO_TOP: return PAN_DURATION
		ArcPhase.PAN_TO_SKY: return PAN_DURATION
		ArcPhase.DROP:       return DROP_DURATION
	return 0.35

func _on_arc_open_complete() -> void:
	# Switch patrol editor to the new camera
	if is_instance_valid(_patrol_editor):
		_patrol_editor._camera = _td_cam

	# Show panel in shop mode by default
	shop_panel.visible = true
	shop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if player and "topdown_mode" in player: player.topdown_mode = true
	_refresh_gold_label()

func _on_arc_close_complete() -> void:
	# Restore FPS camera
	if is_instance_valid(_fps_cam):
		_fps_cam.current = true
	_td_cam.queue_free()
	_td_cam = null

	# Restore FPS mouse capture
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if player and "ui_opened"    in player: player.ui_opened    = false
	if player and "topdown_mode" in player: player.topdown_mode = false
	_set_hud_visible(true)
	_play_mode = false
	_is_firing = false

## Returns true while any arc animation is running.
func _arc_busy() -> bool:
	return _arc_phase != ArcPhase.IDLE

# ═══════════════════════════════════════════════════════════════
# PLAY MODE  (panel hidden, player moves + shoots overhead)
# ═══════════════════════════════════════════════════════════════
func _enter_play_mode() -> void:
	_play_mode = true
	_is_firing = false
	shop_panel.visible = false
	shop_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if player and "topdown_mode" in player: player.topdown_mode = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _exit_play_mode() -> void:
	_play_mode = false
	_is_firing = false
	shop_panel.visible = true
	shop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# ═══════════════════════════════════════════════════════════════
# TOP-DOWN MOVEMENT
# ═══════════════════════════════════════════════════════════════
func _drive_movement(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move += Vector3(0, 0, -1)
	if Input.is_key_pressed(KEY_S): move += Vector3(0, 0,  1)
	if Input.is_key_pressed(KEY_A): move += Vector3(-1, 0, 0)
	if Input.is_key_pressed(KEY_D): move += Vector3( 1, 0, 0)
	if move != Vector3.ZERO:
		move = move.normalized()
		_aim_dir = move   # face movement direction when no mouse aim

	if player.has_method("topdown_move"):
		player.topdown_move(move, delta)
	elif "velocity" in player and player.has_method("move_and_slide"):
		var spd : float = player.move_speed if "move_speed" in player else 5.0
		player.velocity.x = move.x * spd
		player.velocity.z = move.z * spd
		player.move_and_slide()

func _update_aim_from_mouse() -> void:
	var cam := _active_cam()
	if not cam or not is_instance_valid(player): return

	var mpos  := get_viewport().get_mouse_position()
	var from  := cam.project_ray_origin(mpos)
	var to    := from + cam.project_ray_normal(mpos) * 500.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit   := get_viewport().get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return

	var diff : Vector3 = (hit["position"] as Vector3) - (player as Node3D).global_position
	diff.y = 0.0
	if diff.length_squared() > 0.001:
		_aim_dir = diff.normalized()

	# Push aim to player
	if "aim_direction" in player:
		player.aim_direction = _aim_dir
	if player.has_method("set_aim_direction"):
		player.set_aim_direction(_aim_dir)

func _do_fire() -> void:
	if not is_instance_valid(player): return
	_update_aim_from_mouse()
	if player.has_node("WeaponManager"):
		var wm = player.get_node("WeaponManager")
		if wm.has_method("try_shoot"): wm.try_shoot()

# ═══════════════════════════════════════════════════════════════
# SHOP OPEN / CLOSE / TOGGLE
# ═══════════════════════════════════════════════════════════════
func toggle_shop() -> void:
	if _arc_busy(): return

	if not _topdown_active:
		# ── GROUND: open shop (start arc) ──
		_arc_begin_open()

	elif _play_mode:
		# ── PLAY MODE: reopen panel ──
		_exit_play_mode()

	elif shop_panel.visible:
		# ── PANEL OPEN: switch to play mode ──
		_enter_play_mode()

	else:
		# Fallback: show panel
		shop_panel.visible = true

func open_shop() -> void:
	if _arc_busy(): return
	if _topdown_active:
		if _play_mode: _exit_play_mode()
		else:
			shop_panel.visible = true
			shop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		return
	_arc_begin_open()

func close_shop() -> void:
	shop_panel.visible = false

func _close_topdown() -> void:
	if not _topdown_active or _arc_busy(): return
	_arc_begin_close()

func is_panel_open() -> bool:
	return shop_panel != null and shop_panel.visible

# ═══════════════════════════════════════════════════════════════
# INPUT
# ═══════════════════════════════════════════════════════════════
func _input(event: InputEvent) -> void:

	# ── Keyboard ──────────────────────────────────────────────
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode

		if key == KEY_TAB:
			toggle_shop()
			get_viewport().set_input_as_handled()
			return

		if key == KEY_ESCAPE:
			if _attack_target_mode:
				_attack_target_mode = false
				if _play_mode:
					pass   # stay in play mode, just cancel attack cursor
				else:
					shop_panel.visible = true
				_show_status("Attack cancelled.")

			elif _placement_mode:
				_cancel_placement()

			elif _play_mode:
				_exit_play_mode()

			elif shop_panel.visible:
				# Panel open → go back to ground
				_close_topdown()

			get_viewport().set_input_as_handled()
			return

		# Shop panel keyboard nav — only when panel is visible
		if shop_panel.visible:
			match key:
				KEY_ENTER, KEY_KP_ENTER:
					_activate_focused()
					get_viewport().set_input_as_handled()

				KEY_UP:
					_focused_index = max(0, _focused_index - 1)
					_focus_button()

				KEY_DOWN:
					_focused_index = min(_tab_buttons[_focused_tab].size() - 1, _focused_index + 1)
					_focus_button()

				KEY_LEFT:
					_focused_tab   = max(0, _focused_tab - 1)
					_focused_index = 0
					tab_container.current_tab = _focused_tab
					_focus_button()

				KEY_RIGHT:
					_focused_tab   = min(TAB_NAMES.size() - 1, _focused_tab + 1)
					_focused_index = 0
					tab_container.current_tab = _focused_tab
					_focus_button()
			return

	# ── Mouse buttons ──────────────────────────────────────────
	if event is InputEventMouseButton:
		var mev := event as InputEventMouseButton

		# Play mode shooting (LMB)
		if _play_mode and not _placement_mode and not _attack_target_mode:
			if mev.button_index == MOUSE_BUTTON_LEFT:
				_is_firing = mev.pressed
				if mev.pressed: _do_fire()
			get_viewport().set_input_as_handled()
			return

		# Attack target mode
		if _attack_target_mode and mev.pressed:
			match mev.button_index:
				MOUSE_BUTTON_LEFT:
					var hit = _raycast_ground()
					if hit is Vector3: _issue_attack_move(hit)
				MOUSE_BUTTON_RIGHT:
					_attack_target_mode = false
					if not _play_mode: shop_panel.visible = true
					_show_status("Attack cancelled.")
			get_viewport().set_input_as_handled()
			return

		# Placement mode
		if _placement_mode and mev.pressed:
			match mev.button_index:
				MOUSE_BUTTON_LEFT:  _place_turret()
				MOUSE_BUTTON_RIGHT: _cancel_placement()
			get_viewport().set_input_as_handled()
			return

# ═══════════════════════════════════════════════════════════════
# GHOST TURRET
# ═══════════════════════════════════════════════════════════════
func _spawn_ghost(scene: PackedScene) -> void:
	_destroy_ghost()
	_ghost = scene.instantiate() as Node3D
	if not _ghost: return
	get_tree().current_scene.add_child(_ghost)
	_ghost.set_process(false)
	_ghost.set_physics_process(false)
	if "projectile_scene" in _ghost: _ghost.set("projectile_scene", null)
	_disable_collision_recursive(_ghost)
	_ghost_material                    = StandardMaterial3D.new()
	_ghost_material.albedo_color       = Color(0.3, 0.6, 1.0, GHOST_ALPHA)
	_ghost_material.transparency       = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode       = BaseMaterial3D.SHADING_MODE_UNSHADED
	_apply_ghost_mat(_ghost)
	_ghost.visible = false

func _set_ghost_tint(valid: bool) -> void:
	if not _ghost_material: return
	_ghost_material.albedo_color = Color(0.3, 0.6, 1.0, GHOST_ALPHA) if valid \
		else Color(1.0, 0.2, 0.2, GHOST_ALPHA)

func _apply_ghost_mat(node: Node) -> void:
	if node is MeshInstance3D:
		var mi    : MeshInstance3D = node
		var count : int            = mi.mesh.get_surface_count() if mi.mesh else 0
		for i in max(count, 1):
			mi.set_surface_override_material(i, _ghost_material)
	for c in node.get_children():
		_apply_ghost_mat(c)

func _disable_collision_recursive(node: Node) -> void:
	if node is CollisionShape3D: (node as CollisionShape3D).disabled = true
	if node is PhysicsBody3D:
		(node as PhysicsBody3D).collision_layer = 0
		(node as PhysicsBody3D).collision_mask  = 0
	if node is Area3D:
		(node as Area3D).collision_layer = 0
		(node as Area3D).collision_mask  = 0
	for c in node.get_children():
		_disable_collision_recursive(c)

func _destroy_ghost() -> void:
	if is_instance_valid(_ghost): _ghost.queue_free()
	_ghost = null
	_ghost_material = null

# ═══════════════════════════════════════════════════════════════
# RAYCAST / VALIDATION
# ═══════════════════════════════════════════════════════════════
func _raycast_ground() -> Variant:
	var cam := _active_cam()
	if not cam: return null
	var mpos  := get_viewport().get_mouse_position()
	var from  := cam.project_ray_origin(mpos)
	var to    := from + cam.project_ray_normal(mpos) * 300.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit   := get_viewport().get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("position", null)

func _is_placement_valid(pos: Vector3) -> bool:
	for b in get_tree().get_nodes_in_group("bases"):
		if "team_id" in b and b.team_id == _player_team_id:
			return pos.distance_to(b.global_position) <= MAX_TURRET_DISTANCE
	return true

# ═══════════════════════════════════════════════════════════════
# BUILD UI
# ═══════════════════════════════════════════════════════════════
func _build_shop_ui() -> void:
	shop_panel = Panel.new()
	shop_panel.anchor_left   = 0.08
	shop_panel.anchor_top    = 0.06
	shop_panel.anchor_right  = 0.92
	shop_panel.anchor_bottom = 0.94
	shop_panel.modulate      = Color(1, 1, 1, SHOP_PANEL_ALPHA)
	shop_panel.visible       = false
	add_child(shop_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(s, 18)
	shop_panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	margin.add_child(root_vbox)

	# Title row
	var title_row := HBoxContainer.new()
	root_vbox.add_child(title_row)

	var title := Label.new()
	title.text                 = "SHOP"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title_row.add_child(title)

	gold_label = Label.new()
	gold_label.text                  = "💰 0"
	gold_label.add_theme_font_size_override("font_size", 18)
	gold_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(gold_label)

	var hint := Label.new()
	hint.text                 = "Tab: Toggle   |   Esc: Back to ground   |   Enter: Buy"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	root_vbox.add_child(hint)

	tab_hint_label = Label.new()
	tab_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab_hint_label.add_theme_font_size_override("font_size", 14)
	root_vbox.add_child(tab_hint_label)

	tab_container = TabContainer.new()
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	tab_container.tab_changed.connect(_on_tab_changed)
	root_vbox.add_child(tab_container)

	for tab_name in ["Turrets", "Player Upgrades", "Creep Upgrades"]:
		var scroll := ScrollContainer.new()
		scroll.name = tab_name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
		tab_container.add_child(scroll)
		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 8)
		scroll.add_child(vbox)

	var creep_root := VBoxContainer.new()
	creep_root.name = "Creeps"
	creep_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creep_root.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	creep_root.add_theme_constant_override("separation", 6)
	tab_container.add_child(creep_root)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 15)
	root_vbox.add_child(status_label)

	# Placement hint (floats over everything)
	placement_hint_label = Label.new()
	placement_hint_label.text                 = "Left Click: Place   |   Right Click / Esc: Cancel"
	placement_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placement_hint_label.add_theme_font_size_override("font_size", 16)
	placement_hint_label.anchor_left          = 0.0
	placement_hint_label.anchor_right         = 1.0
	placement_hint_label.anchor_top           = 0.94
	placement_hint_label.anchor_bottom        = 1.0
	placement_hint_label.visible              = false
	add_child(placement_hint_label)

# ═══════════════════════════════════════════════════════════════
# POPULATE TABS
# ═══════════════════════════════════════════════════════════════
func _build_all_tabs() -> void:
	_populate_turret_tab()
	_populate_player_upgrade_tab()
	_populate_creep_upgrade_tab()
	_populate_creep_tab()

func _get_tab_vbox(index: int) -> VBoxContainer:
	var child := tab_container.get_child(index)
	if child is ScrollContainer:
		return child.get_child(0) as VBoxContainer
	return child as VBoxContainer

func _populate_turret_tab() -> void:
	var vbox := _get_tab_vbox(TAB_TURRETS)
	if not vbox: return
	if turret_scenes.is_empty():
		vbox.add_child(_make_placeholder("No turrets configured in Inspector"))
		return
	for i in turret_scenes.size():
		var cost     := turret_costs[i] if i < turret_costs.size() else 500
		var name_str := turret_scenes[i].resource_path.get_file().get_basename()
		var btn      := _make_button("🏰 %s — %d 🪙" % [name_str, cost])
		btn.pressed.connect(_on_turret_selected.bind(i))
		vbox.add_child(btn)
		_register_button(TAB_TURRETS, btn, cost)

func _populate_player_upgrade_tab() -> void:
	var vbox := _get_tab_vbox(TAB_PLAYER_UPG)
	if not vbox: return
	vbox.add_child(_make_section_label("— Player Upgrades —"))
	for i in PLAYER_UPGRADES.size():
		var upg  : Dictionary = PLAYER_UPGRADES[i]
		var cost : int        = PLAYER_UPGRADE_COSTS[i] if i < PLAYER_UPGRADE_COSTS.size() else 0
		var btn  := _make_button("%s — %d 🪙" % [upg["label"], cost])
		btn.pressed.connect(_on_player_upgrade_selected.bind(i))
		vbox.add_child(btn)
		_register_button(TAB_PLAYER_UPG, btn, cost)
	vbox.add_child(_make_section_label("— Base Upgrades —"))
	for i in BASE_UPGRADES.size():
		var upg  : Dictionary = BASE_UPGRADES[i]
		var cost : int        = BASE_UPGRADE_COSTS[i] if i < BASE_UPGRADE_COSTS.size() else 0
		var btn  := _make_button("🏯 %s — %d 🪙" % [upg["label"], cost])
		btn.pressed.connect(_on_base_upgrade_selected.bind(i))
		vbox.add_child(btn)
		_register_button(TAB_PLAYER_UPG, btn, cost)

func _populate_creep_upgrade_tab() -> void:
	var vbox := _get_tab_vbox(TAB_CREEP_UPG)
	if not vbox: return
	vbox.add_child(_make_section_label("— Zombie Upgrades (Team %d) —" % _player_team_id))
	for i in CREEP_UPGRADES.size():
		var upg  : Dictionary = CREEP_UPGRADES[i]
		var cost : int        = CREEP_UPGRADE_COSTS[i] if i < CREEP_UPGRADE_COSTS.size() else 0
		var btn  := _make_button("%s — %d 🪙" % [upg["label"], cost])
		btn.pressed.connect(_on_creep_upgrade_selected.bind(i, _player_team_id))
		vbox.add_child(btn)
		_register_button(TAB_CREEP_UPG, btn, cost)

# ═══════════════════════════════════════════════════════════════
# CREEP TAB
# ═══════════════════════════════════════════════════════════════
func _populate_creep_tab() -> void:
	var vbox := _get_tab_vbox(TAB_CREEPS)
	if not vbox: return

	vbox.add_child(_make_section_label("— Creeps —"))

	# Squad/gold row
	var squad_row := HBoxContainer.new()
	squad_row.add_theme_constant_override("separation", 16)
	vbox.add_child(squad_row)

	_picker_gold_lbl = Label.new()
	_picker_gold_lbl.text                  = "💰 0"
	_picker_gold_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	squad_row.add_child(_picker_gold_lbl)

	_picker_squad_lbl = Label.new()
	_picker_squad_lbl.text                  = "My Squad: 0"
	_picker_squad_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_squad_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	squad_row.add_child(_picker_squad_lbl)

	var sel_all := Button.new()
	sel_all.text = "Select All"
	sel_all.pressed.connect(_picker_select_all)
	squad_row.add_child(sel_all)

	# Command row
	var cmd_row := HBoxContainer.new()
	cmd_row.add_theme_constant_override("separation", 6)
	vbox.add_child(cmd_row)

	_picker_cmd_attack = _make_cmd_button("⚔ Attack")
	_picker_cmd_defend = _make_cmd_button("🛡 Defend")
	_picker_cmd_patrol = _make_cmd_button("↺ Patrol")
	_picker_cmd_stay   = _make_cmd_button("■ Stay")

	_picker_cmd_attack.pressed.connect(func(): _send_creeps_attack())
	_picker_cmd_defend.pressed.connect(func(): _apply_ai_mode(int(BaseCreep.AIMode.DEFEND)))
	_picker_cmd_patrol.pressed.connect(_open_patrol_editor)
	_picker_cmd_stay.pressed.connect(func():   _apply_ai_mode(int(BaseCreep.AIMode.STAY)))

	for b in [_picker_cmd_attack, _picker_cmd_defend, _picker_cmd_patrol, _picker_cmd_stay]:
		cmd_row.add_child(b)

	cmd_row.add_child(VSeparator.new())
	var btn_edit := _make_cmd_button("✏ Edit Path")
	btn_edit.pressed.connect(_open_patrol_editor)
	cmd_row.add_child(btn_edit)

	# Patrol action row
	var patrol_row := HBoxContainer.new()
	patrol_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(patrol_row)

	var btn_send := Button.new()
	btn_send.text                  = "▶ Send Patrol"
	btn_send.name                  = "BtnSendPatrol"
	btn_send.disabled              = true
	btn_send.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_send.custom_minimum_size.y = 40
	btn_send.pressed.connect(_on_send_patrol_pressed)
	patrol_row.add_child(btn_send)

	var btn_clear := Button.new()
	btn_clear.text                  = "✕ Clear Path"
	btn_clear.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn_clear.custom_minimum_size.y = 40
	btn_clear.pressed.connect(_on_clear_patrol_pressed)
	patrol_row.add_child(btn_clear)

	vbox.add_child(HSeparator.new())

	# Picker layout
	var picker_hbox := HBoxContainer.new()
	picker_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_hbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	picker_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(picker_hbox)

	var list_scroll := ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.custom_minimum_size.x  = 200
	list_scroll.size_flags_horizontal  = Control.SIZE_SHRINK_BEGIN
	list_scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	picker_hbox.add_child(list_scroll)

	_picker_rows_vbox = VBoxContainer.new()
	_picker_rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_rows_vbox.add_theme_constant_override("separation", 4)
	list_scroll.add_child(_picker_rows_vbox)

	_picker_detail = PanelContainer.new()
	_picker_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_detail.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_picker_detail.visible               = false
	picker_hbox.add_child(_picker_detail)

	var detail_margin := MarginContainer.new()
	detail_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		detail_margin.add_theme_constant_override(s, 14)
	_picker_detail.add_child(detail_margin)

	var detail_vbox := VBoxContainer.new()
	detail_vbox.add_theme_constant_override("separation", 8)
	detail_margin.add_child(detail_vbox)

	_picker_name_lbl = Label.new()
	_picker_name_lbl.add_theme_font_size_override("font_size", 22)
	detail_vbox.add_child(_picker_name_lbl)

	_picker_cost_lbl = Label.new()
	_picker_cost_lbl.add_theme_font_size_override("font_size", 15)
	detail_vbox.add_child(_picker_cost_lbl)

	_picker_desc_lbl = Label.new()
	_picker_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_picker_desc_lbl.add_theme_font_size_override("font_size", 14)
	detail_vbox.add_child(_picker_desc_lbl)

	detail_vbox.add_child(HSeparator.new())

	_picker_confirm = Button.new()
	_picker_confirm.text                  = "Deploy"
	_picker_confirm.custom_minimum_size.y = 48
	_picker_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker_confirm.pressed.connect(_picker_confirm_purchase)
	detail_vbox.add_child(_picker_confirm)

	_build_creep_catalogue()

func _build_creep_catalogue() -> void:
	_creep_catalogue.clear()
	_picker_row_btns.clear()
	_tab_buttons[TAB_CREEPS].clear()
	for c in _picker_rows_vbox.get_children(): c.queue_free()

	if not attack_creep_scenes.is_empty():
		_picker_rows_vbox.add_child(_make_section_label("— Attacking —"))
		for i in attack_creep_scenes.size():
			var lbl  := attack_creep_labels[i] if i < attack_creep_labels.size() else "Attacker %d" % i
			var cost := attack_creep_costs[i]  if i < attack_creep_costs.size()  else 0
			_creep_catalogue.append({"label": lbl, "cost": cost, "scene": attack_creep_scenes[i], "kind": "attack", "desc": ""})
			_add_picker_row(_creep_catalogue.size() - 1, "⚔", lbl, cost)

	if not defend_creep_scenes.is_empty():
		_picker_rows_vbox.add_child(_make_section_label("— Defending —"))
		for i in defend_creep_scenes.size():
			var lbl  := defend_creep_labels[i] if i < defend_creep_labels.size() else "Defender %d" % i
			var cost := defend_creep_costs[i]  if i < defend_creep_costs.size()  else 0
			_creep_catalogue.append({"label": lbl, "cost": cost, "scene": defend_creep_scenes[i], "kind": "defend", "desc": ""})
			_add_picker_row(_creep_catalogue.size() - 1, "🛡", lbl, cost)

	if _creep_catalogue.is_empty():
		_picker_rows_vbox.add_child(_make_placeholder("No creeps configured in Inspector"))

func _add_picker_row(cat_index: int, icon: String, lbl: String, cost: int) -> void:
	var btn := Button.new()
	btn.text                  = "%s %s\n%d 🪙" % [icon, lbl, cost]
	btn.custom_minimum_size.y = BTN_MIN_HEIGHT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.toggle_mode           = true
	btn.focus_mode            = Control.FOCUS_ALL
	var ci := cat_index
	var ri := _picker_row_btns.size()
	btn.pressed.connect(func(): _picker_select(ci))
	btn.focus_entered.connect(_on_button_focused.bind(TAB_CREEPS, ri))
	btn.mouse_entered.connect(func(): btn.grab_focus())
	_picker_rows_vbox.add_child(btn)
	_picker_row_btns.append(btn)
	_tab_buttons[TAB_CREEPS].append(btn)

# ═══════════════════════════════════════════════════════════════
# PICKER LOGIC
# ═══════════════════════════════════════════════════════════════
func _picker_select(index: int) -> void:
	_picker_selected_index = index
	for i in _picker_row_btns.size():
		_picker_row_btns[i].button_pressed = (i == index)
	var entry             := _creep_catalogue[index]
	_picker_name_lbl.text  = entry["label"]
	_picker_desc_lbl.text  = entry.get("desc", "")
	_picker_detail.visible = true
	_refresh_picker_confirm()

func _refresh_picker_confirm() -> void:
	if _picker_selected_index < 0: return
	var entry      := _creep_catalogue[_picker_selected_index]
	var cost       : int  = entry["cost"]
	var gold       : int  = game_manager.get_gold(_player_team_id) if game_manager else 0
	var can_afford : bool = gold >= cost
	_picker_cost_lbl.text    = "Cost: %d 🪙  (you have %d)" % [cost, gold]
	_picker_confirm.text     = "Deploy  %d 🪙" % cost if can_afford \
		else "Need %d 🪙  (have %d)" % [cost, gold]
	_picker_confirm.disabled = not can_afford

func _picker_confirm_purchase() -> void:
	if _picker_selected_index < 0: return
	var entry : Dictionary = _creep_catalogue[_picker_selected_index]
	var cost  : int        = entry["cost"]
	var kind  : String     = entry["kind"]
	if not _check_funds(cost): return

	var spawned := false
	for s in get_tree().get_nodes_in_group("creep_spawner"):
		if not ("team_id" in s) or s.team_id != _player_team_id: continue
		if not s.has_method("spawn_purchased_creep"): continue
		for i in creep_spawn_count:
			var creep : Node = s.spawn_purchased_creep(entry["scene"], player)
			if not is_instance_valid(creep): continue
			if "owner_id" in creep: creep.owner_id = _player_instance_id
			if "team_id"  in creep: creep.team_id  = _player_team_id
			_assign_surround_offset(creep, i, creep_spawn_count)
			var ai_mode := BaseCreep.AIMode.DEFEND if kind == "defend" else BaseCreep.AIMode.ATTACK
			if creep.has_method("set_ai_mode"): creep.set_ai_mode(ai_mode)
			if kind == "defend" and "owner_player" in creep: creep.owner_player = player
		spawned = true
		break

	_show_status(
		("%s %s deployed!" % ["⚔" if kind == "attack" else "🛡", entry["label"]]) \
		if spawned else "⚠ No spawner found for team %d" % _player_team_id
	)
	_picker_selected_index = -1
	for b in _picker_row_btns: b.button_pressed = false
	_picker_detail.visible = false
	_refresh_picker_gold()

# ═══════════════════════════════════════════════════════════════
# AI COMMANDS
# ═══════════════════════════════════════════════════════════════
func _send_creeps_attack() -> void:
	var nearest := _find_nearest_enemy()
	if nearest:
		var dest : Vector3 = nearest.global_position
		_for_each_owned_unit(func(unit: Node) -> void:
			if not unit.has_method("set_ai_mode"): return
			unit.set_ai_mode(BaseCreep.AIMode.ATTACK)
			if "owner_player"    in unit: unit.owner_player    = null
			if "move_target"     in unit: unit.move_target     = dest
			if "has_move_target" in unit: unit.has_move_target = true
		)
		_show_status("⚔ %d zombies attacking nearest enemy!" % _count_owned_units())
	else:
		# No visible enemy — switch to click-to-attack
		_attack_target_mode = true
		if not _play_mode:
			shop_panel.visible = false
		_show_status("⚔ Click where to attack. Right-click to cancel.")

func _apply_ai_mode(mode: int) -> void:
	var patrol_points : Array[Vector3] = []
	if mode == int(BaseCreep.AIMode.PATROL):
		if is_instance_valid(_patrol_editor) and not _patrol_editor._waypoints.is_empty():
			patrol_points = _patrol_editor._waypoints.duplicate()
		else:
			for b in get_tree().get_nodes_in_group("bases"):
				if "team_id" in b and b.team_id == _player_team_id:
					var bp : Vector3 = (b as Node3D).global_position
					var r  := 6.0
					patrol_points = [
						bp + Vector3( r, 0,  r),
						bp + Vector3(-r, 0,  r),
						bp + Vector3(-r, 0, -r),
						bp + Vector3( r, 0, -r),
					]
					break

	var count := 0
	_for_each_owned_unit(func(unit: Node) -> void:
		if not unit.has_method("set_ai_mode"): return
		if mode == int(BaseCreep.AIMode.PATROL) and not patrol_points.is_empty():
			if unit.has_method("set_patrol_points"):
				unit.set_patrol_points(patrol_points)
			elif "patrol_points" in unit:
				unit.patrol_points = patrol_points
		unit.set_ai_mode(mode)
		if "owner_player" in unit:
			unit.owner_player = player if mode == int(BaseCreep.AIMode.DEFEND) else null
		count += 1
	)

	var labels := {
		int(BaseCreep.AIMode.ATTACK): "⚔ Attack — %d zombies attacking",
		int(BaseCreep.AIMode.DEFEND): "🛡 Defend — %d zombies following you",
		int(BaseCreep.AIMode.PATROL): "↺ Patrol — %d zombies patrolling",
		int(BaseCreep.AIMode.STAY):   "■ Stay — %d zombies holding position",
	}
	_show_status(labels.get(mode, "Done") % count)

## Called by player.gd hotkeys (1/2/3/4).
func command_owned_units(mode_index: int) -> void:
	match mode_index:
		0: _send_creeps_attack()
		1: _apply_ai_mode(int(BaseCreep.AIMode.DEFEND))
		2: _apply_ai_mode(int(BaseCreep.AIMode.PATROL))
		3: _apply_ai_mode(int(BaseCreep.AIMode.STAY))

func _picker_select_all() -> void:
	_show_status("Your %d creep(s) selected." % _count_owned_units())

func _find_nearest_enemy() -> Node3D:
	if not is_instance_valid(player): return null
	var origin    : Vector3 = (player as Node3D).global_position
	var best      : Node3D  = null
	var best_dist : float   = 9999.0
	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit) or not ("team_id" in unit): continue
		if int(unit.team_id) == _player_team_id: continue
		var d := origin.distance_to((unit as Node3D).global_position)
		if d < best_dist: best_dist = d; best = unit as Node3D
	return best

func _issue_attack_move(dest: Vector3) -> void:
	_for_each_owned_unit(func(unit: Node) -> void:
		if not unit.has_method("set_ai_mode"): return
		unit.set_ai_mode(BaseCreep.AIMode.ATTACK)
		if "owner_player"    in unit: unit.owner_player    = null
		if "move_target"     in unit: unit.move_target     = dest
		if "has_move_target" in unit: unit.has_move_target = true
	)
	_attack_target_mode = false
	if not _play_mode: shop_panel.visible = true
	_show_status("⚔ Zombies moving to attack position!")

# ═══════════════════════════════════════════════════════════════
# PATROL EDITOR
# ═══════════════════════════════════════════════════════════════
func _init_patrol_editor() -> void:
	_patrol_editor = PatrolEditor.new()
	add_child(_patrol_editor)
	var cam := _td_cam if is_instance_valid(_td_cam) else _fps_cam
	_patrol_editor.init(cam if cam else get_viewport().get_camera_3d(), status_label)
	_patrol_editor.patrol_path_set.connect(_on_patrol_path_set)
	_patrol_editor.editor_closed.connect(_on_patrol_editor_closed)

func _open_patrol_editor() -> void:
	if not is_instance_valid(_patrol_editor): _init_patrol_editor()
	_patrol_editor._camera = _td_cam if is_instance_valid(_td_cam) else _fps_cam
	shop_panel.visible = false
	_patrol_editor.open()

func _on_patrol_editor_closed() -> void:
	shop_panel.visible = true
	var count := _patrol_editor._waypoints.size() if is_instance_valid(_patrol_editor) else 0
	_show_status("Patrol editor closed. %d waypoints saved." % count)
	var btn := _find_send_patrol_button()
	if btn: btn.disabled = (count == 0)

func _on_send_patrol_pressed() -> void:
	if is_instance_valid(_patrol_editor): _patrol_editor.send_patrol()

func _on_clear_patrol_pressed() -> void:
	if is_instance_valid(_patrol_editor): _patrol_editor.clear_waypoints()
	var btn := _find_send_patrol_button()
	if btn: btn.disabled = true
	_show_status("Patrol path cleared.")

func _on_patrol_path_set(points: Array) -> void:
	_for_each_owned_unit(func(unit: Node) -> void:
		if not unit.has_method("set_ai_mode"): return
		if unit.has_method("set_patrol_points"):
			unit.set_patrol_points(points)
		elif "patrol_points" in unit:
			unit.patrol_points = points
		unit.set_ai_mode(BaseCreep.AIMode.PATROL)
		if "owner_player" in unit: unit.owner_player = null
	)
	_show_status("↺ Patrol applied — %d waypoints, %d zombies." \
		% [points.size(), _count_owned_units()])

func _find_send_patrol_button() -> Button:
	return get_node_or_null("%BtnSendPatrol") as Button

# ═══════════════════════════════════════════════════════════════
# TURRET PLACEMENT
# ═══════════════════════════════════════════════════════════════
func _enter_placement_mode(index: int) -> void:
	_placement_mode       = true
	_current_turret_index = index
	_placement_scene      = turret_scenes[index]
	shop_panel.visible    = false
	placement_hint_label.visible = true
	if player and "ui_opened" in player: player.ui_opened = true
	_spawn_ghost(_placement_scene)

func _cancel_placement() -> void:
	_destroy_ghost()
	_placement_mode              = false
	_placement_scene             = null
	_current_turret_index        = -1
	placement_hint_label.visible = false
	if _topdown_active:
		shop_panel.visible = true
	else:
		_close_topdown()

func _place_turret() -> void:
	var hit : Variant = _raycast_ground()
	if not hit is Vector3: return
	if not _is_placement_valid(hit):
		_show_status("⚠ Too far from your base! (max %d units)" % int(MAX_TURRET_DISTANCE))
		return
	var instance := _placement_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(instance)
	instance.global_position = hit
	if "team_id"  in instance: instance.team_id  = _player_team_id
	if "owner_id" in instance: instance.owner_id = _player_instance_id
	_destroy_ghost()
	_placement_mode              = false
	_placement_scene             = null
	_current_turret_index        = -1
	placement_hint_label.visible = false
	if _topdown_active:
		shop_panel.visible = true
	else:
		_close_topdown()

# ═══════════════════════════════════════════════════════════════
# PURCHASE HANDLERS
# ═══════════════════════════════════════════════════════════════
func _check_funds(cost: int) -> bool:
	if not game_manager:
		_show_status("⚠ GameManager not found!"); return false
	if not game_manager.spend_gold(_player_team_id, cost):
		_show_status("⚠ Not enough gold! Need %d 🪙" % cost); return false
	return true

func _on_turret_selected(index: int) -> void:
	var cost := turret_costs[index] if index < turret_costs.size() else 500
	if not _check_funds(cost): return
	_enter_placement_mode(index)

func _on_player_upgrade_selected(index: int) -> void:
	var cost : int = PLAYER_UPGRADE_COSTS[index] if index < PLAYER_UPGRADE_COSTS.size() else 0
	if not _check_funds(cost): return
	var upg : Dictionary = PLAYER_UPGRADES[index]
	if player and player.has_method("apply_upgrade"):
		player.apply_upgrade(upg["stat"], upg["amount"])
	_show_status("⬆ %s applied!" % upg["label"])

func _on_base_upgrade_selected(index: int) -> void:
	var cost : int = BASE_UPGRADE_COSTS[index] if index < BASE_UPGRADE_COSTS.size() else 0
	if not _check_funds(cost): return
	var upg : Dictionary = BASE_UPGRADES[index]
	var applied := false
	for b in get_tree().get_nodes_in_group("bases"):
		if "team_id" in b and b.team_id == _player_team_id:
			if b.has_method("add_health"):
				b.add_health(upg["amount"])
			else:
				if "max_health"     in b: b.max_health     += upg["amount"]
				if "current_health" in b: b.current_health += upg["amount"]
			applied = true
			break
	_show_status("🏯 %s applied!" % upg["label"] if applied else "⚠ Base not found!")

func _on_creep_upgrade_selected(index: int, tid: int) -> void:
	var cost : int = CREEP_UPGRADE_COSTS[index] if index < CREEP_UPGRADE_COSTS.size() else 0
	if not _check_funds(cost): return
	var upg : Dictionary = CREEP_UPGRADES[index].duplicate()
	upg["team_id"] = tid
	if game_manager and game_manager.has_method("add_creep_upgrade"):
		game_manager.add_creep_upgrade(tid, upg)
	_show_status("⬆ T%d %s applied!" % [tid, upg["label"]])

func _assign_surround_offset(creep: Node, slot: int, total: int) -> void:
	if not is_instance_valid(creep) or not "attack_offset" in creep: return
	var angle  : float = (TAU / float(maxi(total, 1))) * float(slot) + randf_range(-CREEP_ANGLE_SPREAD, CREEP_ANGLE_SPREAD)
	var radius : float = CREEP_ORBIT_RADIUS + randf_range(-0.4, 0.6)
	creep.attack_offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

# ═══════════════════════════════════════════════════════════════
# UNIT HELPERS
# ═══════════════════════════════════════════════════════════════
func _is_my_unit(unit: Node) -> bool:
	if not is_instance_valid(unit): return false
	if "owner_id" in unit: return int(unit.owner_id) == _player_instance_id
	return "team_id" in unit and int(unit.team_id) == _player_team_id

func _for_each_owned_unit(cb: Callable) -> void:
	for unit in get_tree().get_nodes_in_group("units"):
		if _is_my_unit(unit): cb.call(unit)

func _count_owned_units() -> int:
	var n := 0
	for unit in get_tree().get_nodes_in_group("units"):
		if _is_my_unit(unit): n += 1
	return n

# ═══════════════════════════════════════════════════════════════
# UI HELPERS
# ═══════════════════════════════════════════════════════════════
func _show_status(text: String) -> void:
	if status_label: status_label.text = text

func _set_hud_visible(show: bool) -> void:
	if not is_instance_valid(hud): return
	for child in hud.get_children(): child.visible = show

func _refresh_gold_label() -> void:
	if not game_manager or not gold_label: return
	gold_label.text = "💰 %d" % game_manager.get_gold(_player_team_id)

func _refresh_button_states() -> void:
	if not game_manager: return
	var gold : int = game_manager.get_gold(_player_team_id)
	for entry in _all_buttons:
		if entry["tab"] == TAB_CREEPS: continue
		(entry["btn"] as Button).disabled = entry["cost"] > gold

func _refresh_picker_gold() -> void:
	if not game_manager or not is_instance_valid(_picker_gold_lbl): return
	var gold : int = game_manager.get_gold(_player_team_id)
	_picker_gold_lbl.text  = "💰 %d" % gold
	_picker_squad_lbl.text = "My Squad: %d" % _count_owned_units()
	for i in _picker_row_btns.size():
		if i >= _creep_catalogue.size(): break
		_picker_row_btns[i].modulate = Color.WHITE \
			if gold >= _creep_catalogue[i]["cost"] else Color(0.55, 0.55, 0.55, 0.85)
	if _picker_selected_index >= 0:
		_refresh_picker_confirm()

func _make_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text                  = label_text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = BTN_MIN_HEIGHT
	btn.focus_mode            = Control.FOCUS_ALL
	return btn

func _make_cmd_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text                  = label_text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = 38
	btn.focus_mode            = Control.FOCUS_ALL
	return btn

func _make_section_label(label_text: String) -> Label:
	var lbl := Label.new()
	lbl.text                 = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	return lbl

func _make_placeholder(label_text: String) -> Label:
	var lbl := Label.new()
	lbl.text                 = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lbl

# ═══════════════════════════════════════════════════════════════
# KEYBOARD NAV
# ═══════════════════════════════════════════════════════════════
func _register_button(tab_index: int, btn: Button, cost: int) -> void:
	var idx : int = (_tab_buttons[tab_index] as Array).size()
	_tab_buttons[tab_index].append(btn)
	_all_buttons.append({"btn": btn, "cost": cost, "tab": tab_index, "idx": idx})
	btn.focus_entered.connect(_on_button_focused.bind(tab_index, idx))
	btn.mouse_entered.connect(func(): btn.grab_focus())

func _on_button_focused(tab: int, idx: int) -> void:
	_focused_tab   = tab
	_focused_index = idx
	_update_tab_hint()

func _on_tab_changed(tab: int) -> void:
	_focused_tab   = tab
	_focused_index = 0
	_update_tab_hint()
	_focus_button()

func _update_tab_hint() -> void:
	var count   : int = _tab_buttons[_focused_tab].size()
	var idx_str : String = "%d / %d" % [_focused_index + 1, count] if count > 0 else "—"
	tab_hint_label.text = "%s   |   %s" % [TAB_NAMES[_focused_tab], idx_str]

func _focus_button() -> void:
	_update_tab_hint()
	var btns : Array = _tab_buttons[_focused_tab]
	if btns.size() > 0:
		_focused_index = clamp(_focused_index, 0, btns.size() - 1)
		(btns[_focused_index] as Button).grab_focus()

func _activate_focused() -> void:
	var btns : Array = _tab_buttons[_focused_tab]
	if _focused_index < btns.size():
		(btns[_focused_index] as Button).emit_signal("pressed")
