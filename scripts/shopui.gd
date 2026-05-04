# ============================================================
# shop.gd  —  Complete rewrite
# ============================================================
# KEY BEHAVIOURS
# ─────────────────────────────────────────────────────────────
# • Tab from ground  → arc camera up, show shop panel.
# • Tab while panel open → hide panel, enter top-down play mode
#   (free mouse, WASD movement, left-click fires).
# • Tab while in play mode → reopen shop panel.
# • Escape → return to ground (arc back down, recapture mouse).
# • Patrol editor uses the ACTIVE (top-down) camera for raycasts.
# • Attack button immediately sends owned creeps to nearest enemy.
# • Reload is handled by WeaponManager (R key).
# ============================================================
extends Control
class_name ShopUI

# ───────────────────────────────────────────────────────────────
# CONSTANTS
# ───────────────────────────────────────────────────────────────
const TAB_TURRETS    = 0
const TAB_PLAYER_UPG = 1
const TAB_CREEP_UPG  = 2
const TAB_CREEPS     = 3
const TAB_NAMES      = ["Turrets", "Player Upgrades", "Creep Upgrades", "Creeps"]
const BTN_MIN_HEIGHT = 56

const TOPDOWN_HEIGHT  = 20.0
const SKY_HEIGHT      = 80.0
const TOPDOWN_FOV     = 60.0
const PHASE1_DURATION = 0.45
const PHASE2_DURATION = 0.35

const GHOST_ALPHA      = 0.45
const SHOP_PANEL_ALPHA = 0.82

const MAX_TURRET_DISTANCE = 30.0
const CREEP_ORBIT_RADIUS  = 1.8
const CREEP_ANGLE_SPREAD  = 0.55

const TOPDOWN_MOVE_FORWARD = Vector3(0, 0, -1)
const TOPDOWN_MOVE_BACK    = Vector3(0, 0,  1)
const TOPDOWN_MOVE_LEFT    = Vector3(-1, 0, 0)
const TOPDOWN_MOVE_RIGHT   = Vector3( 1, 0, 0)

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
# HARDCODED UPGRADES
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
# INTERNAL STATE
# ───────────────────────────────────────────────────────────────
var _tab_buttons   : Array             = [[], [], [], []]
var _all_buttons   : Array[Dictionary] = []
var _focused_tab   : int               = 0
var _focused_index : int               = 0

var _placement_mode       : bool        = false
var _placement_scene      : PackedScene = null
var _current_turret_index : int         = -1
var _attack_target_mode   : bool        = false

var _ghost          : Node3D              = null
var _ghost_material : StandardMaterial3D  = null

# Camera arc
var _topdown_cam   : Camera3D = null
var _player_cam    : Camera3D = null
var _cam_phase     : int      = 0
var _cam_phase_t   : float    = 0.0
var _cam_start_pos : Vector3  = Vector3.ZERO
var _cam_start_rot : Vector3  = Vector3.ZERO
var _cam_start_fov : float    = 75.0
var _topdown_active : bool    = false

# Play mode
var _play_mode_active  : bool    = false
var _topdown_shoot_dir : Vector3 = TOPDOWN_MOVE_FORWARD

# Creep picker
var _creep_catalogue       : Array[Dictionary] = []
var _picker_selected_index : int               = -1
var _patrol_editor         : PatrolEditor       = null

# ───────────────────────────────────────────────────────────────
# UI NODE REFS
# ───────────────────────────────────────────────────────────────
var shop_panel           : Panel
var tab_container        : TabContainer
var status_label         : Label
var tab_hint_label       : Label
var gold_label           : Label
var placement_hint_label : Label

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

# Scene refs
var game_manager        : Node
var player              : Node
var main_camera         : Camera3D
var hud                 : Node
var _player_team_id     : int = 1
var _player_instance_id : int = -1

# ───────────────────────────────────────────────────────────────
# READY
# ───────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("shop")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	await get_tree().process_frame

	game_manager = get_tree().get_first_node_in_group("game_manager")
	player       = get_tree().get_first_node_in_group("players")
	main_camera  = get_viewport().get_camera_3d()
	hud          = get_tree().get_first_node_in_group("ui_hud")

	if player:
		_player_team_id     = player.team_id if "team_id" in player else 1
		_player_instance_id = player.get_instance_id()

	# Locate the player's FPS head camera
	if player:
		var head := player.get_node_or_null("Head")
		if head:
			for child in head.get_children():
				if child is Camera3D:
					_player_cam = child
					break
		if not _player_cam:
			for child in player.get_children():
				if child is Camera3D:
					_player_cam = child
					break
	if not _player_cam:
		_player_cam = get_viewport().get_camera_3d()

	_build_shop_ui()
	_build_all_tabs()
	close_shop()
	_init_patrol_editor()

	print("[Shop] ready | player=%s | team=%d | instance=%d" \
		% [str(player), _player_team_id, _player_instance_id])

# ───────────────────────────────────────────────────────────────
# OWNERSHIP HELPERS
# ───────────────────────────────────────────────────────────────
func _is_my_unit(unit: Node) -> bool:
	if not is_instance_valid(unit): return false
	if "owner_id" in unit: return int(unit.owner_id) == _player_instance_id
	return "team_id" in unit and int(unit.team_id) == _player_team_id

func _for_each_owned_unit(callback: Callable) -> void:
	for unit in get_tree().get_nodes_in_group("units"):
		if _is_my_unit(unit): callback.call(unit)

func _count_owned_units() -> int:
	var count := 0
	for unit in get_tree().get_nodes_in_group("units"):
		if _is_my_unit(unit): count += 1
	return count

# ───────────────────────────────────────────────────────────────
# ACTIVE CAMERA HELPER
# Returns the camera currently used for raycasts (topdown or FPS).
# ───────────────────────────────────────────────────────────────
func _active_camera() -> Camera3D:
	if is_instance_valid(_topdown_cam) and _topdown_cam.current:
		return _topdown_cam
	if is_instance_valid(main_camera):
		return main_camera
	return _player_cam

# ───────────────────────────────────────────────────────────────
# MOUSE / CURSOR
# ───────────────────────────────────────────────────────────────
func _sync_mouse() -> void:
	if _topdown_active:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Ground mode mouse is restored in _update_cam_arc phase 4 completion.

# ───────────────────────────────────────────────────────────────
# PROCESS
# ───────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if shop_panel and shop_panel.visible:
		_refresh_button_states()
		_refresh_gold_label()
		_refresh_picker_gold()

	_update_cam_arc(delta)

	# Keep overhead camera locked to player
	if _topdown_cam and player and _cam_phase == 0 and _topdown_active:
		_topdown_cam.global_position = (player as Node3D).global_position + Vector3(0, TOPDOWN_HEIGHT, 0)

	# Ghost turret preview
	if _placement_mode and _ghost and _topdown_active:
		var hit: Variant = _raycast_ground()
		if hit:
			_ghost.global_position = hit
			_set_ghost_tint(_is_placement_valid(hit))
			_ghost.visible = true
		else:
			_ghost.visible = false

	# Top-down play mode — drive movement and aim
	if _play_mode_active and is_instance_valid(player):
		_drive_topdown_movement(delta)
		_update_shoot_dir_from_mouse()

# ───────────────────────────────────────────────────────────────
# TOP-DOWN MOVEMENT
# ───────────────────────────────────────────────────────────────
func _drive_topdown_movement(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move += TOPDOWN_MOVE_FORWARD
	if Input.is_key_pressed(KEY_S): move += TOPDOWN_MOVE_BACK
	if Input.is_key_pressed(KEY_A): move += TOPDOWN_MOVE_LEFT
	if Input.is_key_pressed(KEY_D): move += TOPDOWN_MOVE_RIGHT

	if move != Vector3.ZERO:
		move               = move.normalized()
		_topdown_shoot_dir = move

	if player.has_method("topdown_move"):
		player.topdown_move(move, delta)
	elif "velocity" in player and player.has_method("move_and_slide"):
		var speed : float = player.move_speed if "move_speed" in player else 5.0
		player.velocity.x = move.x * speed if move != Vector3.ZERO else 0.0
		player.velocity.z = move.z * speed if move != Vector3.ZERO else 0.0
		player.move_and_slide()

## Point _topdown_shoot_dir from player toward mouse on the ground plane.
func _update_shoot_dir_from_mouse() -> void:
	var cam := _active_camera()
	if not cam or not is_instance_valid(player): return
	var mouse_pos := get_viewport().get_mouse_position()
	var from      := cam.project_ray_origin(mouse_pos)
	var to        := from + cam.project_ray_normal(mouse_pos) * 300.0
	var result    := get_viewport().get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to))
	if result.is_empty(): return
	var world_pos : Vector3 = result["position"]
	var diff := world_pos - (player as Node3D).global_position
	diff.y = 0.0
	if diff.length_squared() > 0.01:
		_topdown_shoot_dir = diff.normalized()
		_push_aim_to_player()

func _push_aim_to_player() -> void:
	if not is_instance_valid(player): return
	if "aim_direction" in player:
		player.aim_direction = _topdown_shoot_dir
	if player.has_method("set_aim_direction"):
		player.set_aim_direction(_topdown_shoot_dir)

# ───────────────────────────────────────────────────────────────
# PLAY MODE ENTER / EXIT
# ───────────────────────────────────────────────────────────────
func _enter_play_mode() -> void:
	_play_mode_active = true
	if player and "topdown_mode" in player:
		player.topdown_mode = true
	# Release Control focus so WASD isn't eaten by buttons
	var focused := get_viewport().gui_get_focus_owner()
	if focused: focused.release_focus()
	_sync_mouse()
	print("[Shop] play mode ON")

func _exit_play_mode() -> void:
	_play_mode_active = false
	_sync_mouse()
	print("[Shop] play mode OFF")

func _exit_topdown_session() -> void:
	_play_mode_active = false
	if player and "topdown_mode" in player:
		player.topdown_mode = false
	print("[Shop] topdown session ended")

# ───────────────────────────────────────────────────────────────
# TOPDOWN FIRE
# ───────────────────────────────────────────────────────────────
func _topdown_fire() -> void:
	if not is_instance_valid(player): return
	_update_shoot_dir_from_mouse()
	if player.has_method("topdown_fire"):
		player.topdown_fire(_topdown_shoot_dir)
		return
	_push_aim_to_player()
	if player.has_method("shoot"):  player.shoot()
	elif player.has_method("fire"): player.fire()

# ───────────────────────────────────────────────────────────────
# CAMERA ARC
# ───────────────────────────────────────────────────────────────
func _start_cam_arc_open() -> void:
	if not _player_cam or not player: return
	_cam_start_pos = _player_cam.global_position
	_cam_start_rot = _player_cam.global_rotation
	_cam_start_fov = _player_cam.fov

	_topdown_cam     = Camera3D.new()
	_topdown_cam.fov = _cam_start_fov
	get_tree().current_scene.add_child(_topdown_cam)
	_topdown_cam.global_position = _cam_start_pos
	_topdown_cam.global_rotation = _cam_start_rot
	_topdown_cam.current         = true
	_player_cam.current          = false
	main_camera  = _topdown_cam
	_cam_phase   = 1
	_cam_phase_t = 0.0

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _start_cam_arc_close() -> void:
	_cam_phase   = 3
	_cam_phase_t = 0.0

func _update_cam_arc(delta: float) -> void:
	if _cam_phase == 0 or not _topdown_cam or not player: return
	var player3d := player as Node3D
	if not player3d: return

	match _cam_phase:
		1: # Rise to sky
			_cam_phase_t += delta / PHASE1_DURATION
			if _cam_phase_t >= 1.0: _cam_phase_t = 1.0
			var ts      := smoothstep(0.0, 1.0, _cam_phase_t)
			var sky_pos := Vector3(_cam_start_pos.x, _cam_start_pos.y + SKY_HEIGHT, _cam_start_pos.z)
			_topdown_cam.global_position = _cam_start_pos.lerp(sky_pos, ts)
			var rx := lerp_angle(_cam_start_rot.x, deg_to_rad(-90.0), ts)
			_topdown_cam.global_rotation = Vector3(rx, _cam_start_rot.y, 0.0)
			_topdown_cam.fov = lerpf(_cam_start_fov, TOPDOWN_FOV, ts)
			if _cam_phase_t >= 1.0: _cam_phase = 2; _cam_phase_t = 0.0

		2: # Pan to overhead
			_cam_phase_t += delta / PHASE2_DURATION
			if _cam_phase_t >= 1.0: _cam_phase_t = 1.0
			var ts       := smoothstep(0.0, 1.0, _cam_phase_t)
			var overhead := player3d.global_position + Vector3(0, TOPDOWN_HEIGHT, 0)
			var sky_pos  := Vector3(_cam_start_pos.x, _cam_start_pos.y + SKY_HEIGHT, _cam_start_pos.z)
			_topdown_cam.global_position = sky_pos.lerp(overhead, ts)
			_topdown_cam.global_rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
			_topdown_cam.fov = TOPDOWN_FOV
			if _cam_phase_t >= 1.0:
				_cam_phase      = 0
				_topdown_active = true
				# Show shop panel and immediately enter play mode
				shop_panel.visible = true
				if player and "topdown_mode" in player: player.topdown_mode = true
				if player and "ui_opened"    in player: player.ui_opened    = true
				_sync_mouse()
				# Update patrol editor camera now that topdown cam exists
				if is_instance_valid(_patrol_editor):
					_patrol_editor._camera = _topdown_cam

		3: # Pan back to sky
			_cam_phase_t += delta / PHASE2_DURATION
			if _cam_phase_t >= 1.0: _cam_phase_t = 1.0
			var ts       := smoothstep(0.0, 1.0, _cam_phase_t)
			var overhead := player3d.global_position + Vector3(0, TOPDOWN_HEIGHT, 0)
			var sky_pos  := Vector3(_cam_start_pos.x, _cam_start_pos.y + SKY_HEIGHT, _cam_start_pos.z)
			_topdown_cam.global_position = overhead.lerp(sky_pos, ts)
			_topdown_cam.global_rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
			_topdown_cam.fov = TOPDOWN_FOV
			if _cam_phase_t >= 1.0: _cam_phase = 4; _cam_phase_t = 0.0

		4: # Descend to ground
			_cam_phase_t += delta / PHASE1_DURATION
			if _cam_phase_t >= 1.0: _cam_phase_t = 1.0
			var ts      := smoothstep(0.0, 1.0, _cam_phase_t)
			var sky_pos := Vector3(_cam_start_pos.x, _cam_start_pos.y + SKY_HEIGHT, _cam_start_pos.z)
			_topdown_cam.global_position = sky_pos.lerp(_cam_start_pos, ts)
			var rx := lerp_angle(deg_to_rad(-90.0), _cam_start_rot.x, ts)
			_topdown_cam.global_rotation = Vector3(rx, _cam_start_rot.y, 0.0)
			_topdown_cam.fov = lerpf(TOPDOWN_FOV, _cam_start_fov, ts)
			if _cam_phase_t >= 1.0:
				_cam_phase      = 0
				_topdown_active = false
				_exit_topdown_session()
				if _player_cam: _player_cam.current = true
				_topdown_cam.queue_free()
				_topdown_cam = null
				main_camera  = get_viewport().get_camera_3d()
				if not main_camera: main_camera = _player_cam
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				if player and "ui_opened" in player: player.ui_opened = false
				_set_hud_visible(true)

# ───────────────────────────────────────────────────────────────
# GHOST TURRET
# ───────────────────────────────────────────────────────────────
func _spawn_ghost(scene: PackedScene) -> void:
	_destroy_ghost()
	_ghost = scene.instantiate() as Node3D
	if not _ghost: return
	get_tree().current_scene.add_child(_ghost)
	_ghost.set_process(false)
	_ghost.set_physics_process(false)
	if "projectile_scene" in _ghost: _ghost.projectile_scene = null
	_disable_collision_recursive(_ghost)
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.albedo_color        = Color(0.3, 0.6, 1.0, GHOST_ALPHA)
	_ghost_material.transparency        = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode        = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.flags_no_depth_test = false
	_apply_ghost_material_recursive(_ghost)
	_ghost.visible = false

func _set_ghost_tint(valid: bool) -> void:
	if not _ghost_material: return
	_ghost_material.albedo_color = Color(0.3, 0.6, 1.0, GHOST_ALPHA) if valid \
		else Color(1.0, 0.2, 0.2, GHOST_ALPHA)

func _apply_ghost_material_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi    : MeshInstance3D = node as MeshInstance3D
		var slots : int            = max(mi.mesh.get_surface_count() if mi.mesh else 0, 1)
		for i in slots:
			mi.set_surface_override_material(i, _ghost_material)
	for child in node.get_children():
		_apply_ghost_material_recursive(child)

func _disable_collision_recursive(node: Node) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	elif node is PhysicsBody3D:
		(node as PhysicsBody3D).collision_layer = 0
		(node as PhysicsBody3D).collision_mask  = 0
	elif node is Area3D:
		(node as Area3D).collision_layer = 0
		(node as Area3D).collision_mask  = 0
	for child in node.get_children():
		_disable_collision_recursive(child)

func _destroy_ghost() -> void:
	if is_instance_valid(_ghost): _ghost.queue_free()
	_ghost = null
	_ghost_material = null

# ───────────────────────────────────────────────────────────────
# RAYCAST / VALIDATION
# ───────────────────────────────────────────────────────────────
func _raycast_ground() -> Variant:
	var cam := _active_camera()
	if not cam: return null
	var mouse_pos := get_viewport().get_mouse_position()
	var from      := cam.project_ray_origin(mouse_pos)
	var to        := from + cam.project_ray_normal(mouse_pos) * 300.0
	var result    := get_viewport().get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to))
	return result.get("position", null)

func _get_player_base_position() -> Variant:
	for b in get_tree().get_nodes_in_group("bases"):
		if "team_id" in b and b.team_id == _player_team_id:
			return b.global_position
	return null

func _is_placement_valid(world_pos: Vector3) -> bool:
	var base_pos: Variant = _get_player_base_position()
	if base_pos == null: return true
	return world_pos.distance_to(base_pos) <= MAX_TURRET_DISTANCE

func _set_hud_visible(show: bool) -> void:
	if not is_instance_valid(hud): return
	for child in hud.get_children():
		child.visible = show

# ───────────────────────────────────────────────────────────────
# BUILD UI
# ───────────────────────────────────────────────────────────────
func _build_shop_ui() -> void:
	shop_panel = Panel.new()
	shop_panel.anchor_left   = 0.08
	shop_panel.anchor_top    = 0.06
	shop_panel.anchor_right  = 0.92
	shop_panel.anchor_bottom = 0.94
	shop_panel.modulate      = Color(1.0, 1.0, 1.0, SHOP_PANEL_ALPHA)
	shop_panel.visible       = false
	add_child(shop_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	shop_panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	margin.add_child(root_vbox)

	var title_row := HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(title_row)

	var title := Label.new()
	title.text                  = "SHOP"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title_row.add_child(title)

	gold_label = Label.new()
	gold_label.text                 = "💰 0"
	gold_label.add_theme_font_size_override("font_size", 18)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(gold_label)

	var hint := Label.new()
	hint.text                 = "Tab: Toggle Panel   |   Esc: Return to ground   |   Enter: Buy"
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

# ───────────────────────────────────────────────────────────────
# POPULATE TABS
# ───────────────────────────────────────────────────────────────
func _build_all_tabs() -> void:
	_populate_turret_tab()
	_populate_player_upgrade_tab()
	_populate_creep_upgrade_tab()
	_populate_creep_tab()
	await get_tree().process_frame
	for i in range(TAB_CREEPS):
		var scroll := tab_container.get_child(i) as ScrollContainer
		if scroll:
			scroll.queue_sort()
			var vbox := scroll.get_child(0) as VBoxContainer
			if vbox: vbox.queue_sort()

func _get_tab_vbox(tab_index: int) -> VBoxContainer:
	var child := tab_container.get_child(tab_index)
	if child == null:
		push_error("[Shop] tab child null for index %d" % tab_index)
		return null
	if child is ScrollContainer:
		return child.get_child(0) as VBoxContainer
	return child as VBoxContainer

func _populate_turret_tab() -> void:
	var vbox := _get_tab_vbox(TAB_TURRETS)
	if vbox == null: return
	if turret_scenes.is_empty():
		vbox.add_child(_make_placeholder("No turrets configured in Inspector"))
		return
	for i in turret_scenes.size():
		var cost     : int    = turret_costs[i] if i < turret_costs.size() else 500
		var name_str : String = turret_scenes[i].resource_path.get_file().get_basename()
		var btn               := _make_button("🏰 %s — %d 🪙" % [name_str, cost])
		btn.pressed.connect(_on_turret_selected.bind(i))
		vbox.add_child(btn)
		_register_button(TAB_TURRETS, btn, cost)

func _populate_player_upgrade_tab() -> void:
	var vbox := _get_tab_vbox(TAB_PLAYER_UPG)
	if vbox == null: return
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
	if vbox == null: return
	vbox.add_child(_make_section_label("— Your Zombie Upgrades (Team %d) —" % _player_team_id))
	for i in CREEP_UPGRADES.size():
		var upg  : Dictionary = CREEP_UPGRADES[i]
		var cost : int        = CREEP_UPGRADE_COSTS[i] if i < CREEP_UPGRADE_COSTS.size() else 0
		var btn  := _make_button("%s — %d 🪙" % [upg["label"], cost])
		btn.pressed.connect(_on_creep_upgrade_selected.bind(i, _player_team_id))
		vbox.add_child(btn)
		_register_button(TAB_CREEP_UPG, btn, cost)

# ───────────────────────────────────────────────────────────────
# CREEP TAB
# ───────────────────────────────────────────────────────────────
func _populate_creep_tab() -> void:
	var vbox := _get_tab_vbox(TAB_CREEPS)
	if vbox == null: return

	vbox.add_child(_make_section_label("— Creeps —"))

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
	sel_all.text                  = "Select All"
	sel_all.size_flags_horizontal = Control.SIZE_SHRINK_END
	sel_all.pressed.connect(_picker_select_all)
	squad_row.add_child(sel_all)

	var cmd_row := HBoxContainer.new()
	cmd_row.add_theme_constant_override("separation", 6)
	vbox.add_child(cmd_row)

	_picker_cmd_attack = _make_cmd_button("⚔ Attack")
	_picker_cmd_defend = _make_cmd_button("🛡 Defend")
	_picker_cmd_patrol = _make_cmd_button("↺ Patrol")
	_picker_cmd_stay   = _make_cmd_button("■ Stay")

	_picker_cmd_attack.pressed.connect(func(): _send_creeps_attack())
	_picker_cmd_defend.pressed.connect(func(): _apply_mode_to_owned_units(int(BaseCreep.AIMode.DEFEND)))
	_picker_cmd_patrol.pressed.connect(_open_patrol_editor)
	_picker_cmd_stay.pressed.connect(func():   _apply_mode_to_owned_units(int(BaseCreep.AIMode.STAY)))

	for b in [_picker_cmd_attack, _picker_cmd_defend, _picker_cmd_patrol, _picker_cmd_stay]:
		cmd_row.add_child(b)

	cmd_row.add_child(VSeparator.new())

	var btn_edit_path := _make_cmd_button("✏ Edit Path")
	btn_edit_path.pressed.connect(_open_patrol_editor)
	cmd_row.add_child(btn_edit_path)

	var patrol_action_row := HBoxContainer.new()
	patrol_action_row.add_theme_constant_override("separation", 6)
	patrol_action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(patrol_action_row)

	var btn_send_patrol := Button.new()
	btn_send_patrol.text                  = "▶ Send Patrol"
	btn_send_patrol.disabled              = true
	btn_send_patrol.name                  = "BtnSendPatrol"
	btn_send_patrol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_send_patrol.custom_minimum_size.y = 40
	btn_send_patrol.pressed.connect(_on_send_patrol_pressed)
	patrol_action_row.add_child(btn_send_patrol)

	var btn_clear := Button.new()
	btn_clear.text                  = "✕ Clear Path"
	btn_clear.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn_clear.custom_minimum_size.y = 40
	btn_clear.pressed.connect(_on_clear_patrol_pressed)
	patrol_action_row.add_child(btn_clear)

	vbox.add_child(HSeparator.new())

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
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		detail_margin.add_theme_constant_override(side, 14)
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
	for child in _picker_rows_vbox.get_children():
		child.queue_free()

	if not attack_creep_scenes.is_empty():
		_picker_rows_vbox.add_child(_make_section_label("— Attacking —"))
		for i in attack_creep_scenes.size():
			var lbl  := attack_creep_labels[i] if i < attack_creep_labels.size() else "Attacker %d" % i
			var cost := attack_creep_costs[i]  if i < attack_creep_costs.size()  else 0
			_creep_catalogue.append({ "label": lbl, "cost": cost, "scene": attack_creep_scenes[i], "kind": "attack", "desc": "" })
			_add_picker_row(_creep_catalogue.size() - 1, "⚔", lbl, cost)

	if not defend_creep_scenes.is_empty():
		_picker_rows_vbox.add_child(_make_section_label("— Defending —"))
		for i in defend_creep_scenes.size():
			var lbl  := defend_creep_labels[i] if i < defend_creep_labels.size() else "Defender %d" % i
			var cost := defend_creep_costs[i]  if i < defend_creep_costs.size()  else 0
			_creep_catalogue.append({ "label": lbl, "cost": cost, "scene": defend_creep_scenes[i], "kind": "defend", "desc": "" })
			_add_picker_row(_creep_catalogue.size() - 1, "🛡", lbl, cost)

	if _creep_catalogue.is_empty():
		_picker_rows_vbox.add_child(_make_placeholder("No creeps configured in Inspector"))

func _add_picker_row(catalogue_index: int, icon: String, lbl: String, cost: int) -> void:
	var btn := Button.new()
	btn.text                  = "%s %s\n%d 🪙" % [icon, lbl, cost]
	btn.custom_minimum_size.y = BTN_MIN_HEIGHT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.toggle_mode           = true
	btn.focus_mode            = Control.FOCUS_ALL
	var ci := catalogue_index
	btn.pressed.connect(func(): _picker_select(ci))
	btn.focus_entered.connect(_on_button_focused.bind(TAB_CREEPS, _picker_row_btns.size()))
	btn.mouse_entered.connect(_on_button_mouse_entered.bind(TAB_CREEPS, _picker_row_btns.size(), btn))
	_picker_rows_vbox.add_child(btn)
	_picker_row_btns.append(btn)
	_tab_buttons[TAB_CREEPS].append(btn)

# ───────────────────────────────────────────────────────────────
# PICKER LOGIC
# ───────────────────────────────────────────────────────────────
func _picker_select(index: int) -> void:
	_picker_selected_index = index
	for i in _picker_row_btns.size():
		_picker_row_btns[i].button_pressed = (i == index)
	var entry              := _creep_catalogue[index]
	_picker_name_lbl.text   = entry["label"]
	_picker_desc_lbl.text   = entry.get("desc", "")
	_picker_detail.visible  = true
	_refresh_picker_confirm()

func _refresh_picker_confirm() -> void:
	if _picker_selected_index < 0: return
	var entry      : Dictionary = _creep_catalogue[_picker_selected_index]
	var cost       : int        = entry["cost"]
	var gold       : int        = game_manager.get_gold(_player_team_id) if game_manager else 0
	var can_afford : bool       = gold >= cost
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
			var creep: Node = s.spawn_purchased_creep(entry["scene"], player)
			if not is_instance_valid(creep): continue
			if "owner_id" in creep: creep.owner_id = _player_instance_id
			if "team_id"  in creep: creep.team_id  = _player_team_id
			_assign_surround_offset(creep, i, creep_spawn_count)
			if creep.has_method("set_ai_mode"):
				creep.set_ai_mode(
					BaseCreep.AIMode.DEFEND if kind == "defend" else BaseCreep.AIMode.ATTACK)
			if kind == "defend" and "owner_player" in creep:
				creep.owner_player = player
		spawned = true
		break

	_show_status(
		"%s %s deployed!" % ["⚔" if kind == "attack" else "🛡", entry["label"]] \
		if spawned else "⚠ No spawner found for team %d" % _player_team_id)

	_picker_selected_index = -1
	for b in _picker_row_btns: b.button_pressed = false
	_picker_detail.visible = false
	_refresh_picker_gold()

# ───────────────────────────────────────────────────────────────
# AI COMMANDS
# ───────────────────────────────────────────────────────────────

## Attack: immediately find nearest enemy and send all owned creeps toward it.
## Falls back to click-to-target if no enemy is in range.
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
		# No enemy visible — let the player click a destination
		shop_panel.visible  = false
		_attack_target_mode = true
		_sync_mouse()
		_show_status("⚔ No nearby enemy — click where to attack. Right-click to cancel.")

func _find_nearest_enemy() -> Node3D:
	if not is_instance_valid(player): return null
	var origin    : Vector3 = (player as Node3D).global_position
	var best      : Node3D  = null
	var best_dist : float   = 9999.0
	for unit in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(unit): continue
		if not ("team_id" in unit): continue
		if int(unit.team_id) == _player_team_id: continue
		var d := origin.distance_to((unit as Node3D).global_position)
		if d < best_dist:
			best_dist = d
			best      = unit as Node3D
	return best

func _apply_mode_to_owned_units(mode: int) -> void:
	var patrol_points : Array[Vector3] = []
	if mode == BaseCreep.AIMode.PATROL:
		if is_instance_valid(_patrol_editor) and not _patrol_editor._waypoints.is_empty():
			patrol_points = _patrol_editor._waypoints.duplicate()
		else:
			for b in get_tree().get_nodes_in_group("bases"):
				if "team_id" in b and b.team_id == _player_team_id:
					var bp : Vector3 = b.global_position
					var r  : float   = 6.0
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
		if mode == BaseCreep.AIMode.PATROL and not patrol_points.is_empty():
			if unit.has_method("set_patrol_points"):
				unit.set_patrol_points(patrol_points)
			elif "patrol_points" in unit:
				unit.patrol_points = patrol_points
		unit.set_ai_mode(mode)
		if "owner_player" in unit:
			unit.owner_player = player if mode == BaseCreep.AIMode.DEFEND else null
		count += 1
	)

	var labels := {
		BaseCreep.AIMode.ATTACK: "⚔ Attack — %d zombies attacking",
		BaseCreep.AIMode.DEFEND: "🛡 Defend — %d zombies following you",
		BaseCreep.AIMode.PATROL: "↺ Patrol — %d zombies patrolling",
		BaseCreep.AIMode.STAY:   "■ Stay — %d zombies holding position",
	}
	_show_status(labels.get(mode, "Done") % count)

## Called by player.gd hotkeys (1/2/3/4).
func command_owned_units(mode_index: int) -> void:
	match mode_index:
		0: _send_creeps_attack()
		1: _apply_mode_to_owned_units(int(BaseCreep.AIMode.DEFEND))
		2: _apply_mode_to_owned_units(int(BaseCreep.AIMode.PATROL))
		3: _apply_mode_to_owned_units(int(BaseCreep.AIMode.STAY))

func _picker_select_all() -> void:
	var count := _count_owned_units()
	_show_status("Your %d creep(s) selected" % count)

# ───────────────────────────────────────────────────────────────
# PATROL EDITOR
# ───────────────────────────────────────────────────────────────
func _init_patrol_editor() -> void:
	_patrol_editor = PatrolEditor.new()
	add_child(_patrol_editor)
	# Use topdown cam if available, otherwise FPS cam
	var cam := _topdown_cam if is_instance_valid(_topdown_cam) \
		else (_player_cam if is_instance_valid(_player_cam) \
		else get_viewport().get_camera_3d())
	_patrol_editor.init(cam, status_label)
	_patrol_editor.patrol_path_set.connect(_on_patrol_path_set)
	_patrol_editor.editor_closed.connect(_on_patrol_editor_closed)

func _open_patrol_editor() -> void:
	if not is_instance_valid(_patrol_editor): _init_patrol_editor()
	# ALWAYS pass the active topdown camera so raycasts hit the ground correctly
	var cam := _topdown_cam if is_instance_valid(_topdown_cam) \
		else (_player_cam if is_instance_valid(_player_cam) \
		else get_viewport().get_camera_3d())
	_patrol_editor._camera = cam
	shop_panel.visible = false
	_sync_mouse()
	_patrol_editor.open()

func _on_patrol_editor_closed() -> void:
	shop_panel.visible = true
	_sync_mouse()
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

# ───────────────────────────────────────────────────────────────
# BUTTON HELPERS
# ───────────────────────────────────────────────────────────────
func _register_button(tab_index: int, btn: Button, cost: int) -> void:
	var idx : int = _tab_buttons[tab_index].size()
	_tab_buttons[tab_index].append(btn)
	_all_buttons.append({ "btn": btn, "cost": cost, "tab": tab_index, "idx": idx })
	btn.focus_entered.connect(_on_button_focused.bind(tab_index, idx))
	btn.mouse_entered.connect(_on_button_mouse_entered.bind(tab_index, idx, btn))

func _on_button_mouse_entered(_tab: int, _idx: int, btn: Button) -> void:
	btn.grab_focus()

func _on_button_focused(tab: int, idx: int) -> void:
	_focused_tab   = tab
	_focused_index = idx
	_update_tab_hint()

func _on_tab_changed(tab: int) -> void:
	_focused_tab   = tab
	_focused_index = 0
	_update_tab_hint()
	var btns : Array = _tab_buttons[_focused_tab]
	if btns.size() > 0: (btns[0] as Button).grab_focus()

func _update_tab_hint() -> void:
	var count   : int    = _tab_buttons[_focused_tab].size()
	var idx_str : String = "%d / %d" % [_focused_index + 1, count] if count > 0 else "—"
	tab_hint_label.text = "%s   |   %s" % [TAB_NAMES[_focused_tab], idx_str]

func _activate_focused() -> void:
	var btns : Array = _tab_buttons[_focused_tab]
	if _focused_index < btns.size():
		(btns[_focused_index] as Button).emit_signal("pressed")

func _refresh_button_states() -> void:
	if not game_manager: return
	var gold : int = game_manager.get_gold(_player_team_id)
	for entry in _all_buttons:
		if entry["tab"] == TAB_CREEPS: continue
		(entry["btn"] as Button).disabled = entry["cost"] > gold

func _refresh_gold_label() -> void:
	if not game_manager or not gold_label: return
	gold_label.text = "💰 %d" % game_manager.get_gold(_player_team_id)

# ───────────────────────────────────────────────────────────────
# SHOP OPEN / CLOSE / TOGGLE
# ───────────────────────────────────────────────────────────────
func toggle_shop() -> void:
	if _cam_phase != 0: return   # Arc is in progress — ignore

	if not _topdown_active:
		# Ground → start arc up, open shop
		open_shop()

	elif shop_panel.visible:
		# Panel open → hide it, enter play mode
		shop_panel.visible = false
		if player and "ui_opened" in player: player.ui_opened = false
		_enter_play_mode()

	else:
		# Play mode → reopen panel
		_exit_play_mode()
		shop_panel.visible = true
		if player and "ui_opened" in player: player.ui_opened = true
		_refresh_gold_label()
		_sync_mouse()

func open_shop() -> void:
	if _cam_phase != 0: return

	if _topdown_active:
		shop_panel.visible = true
		if player and "ui_opened" in player: player.ui_opened = true
		tab_container.current_tab = _focused_tab
		_update_tab_hint()
		_refresh_gold_label()
		_sync_mouse()
		return

	if player and "ui_opened" in player: player.ui_opened = true
	_set_hud_visible(true)
	shop_panel.visible = false
	_start_cam_arc_open()
	tab_container.current_tab = _focused_tab
	_update_tab_hint()
	_refresh_gold_label()

func close_shop() -> void:
	shop_panel.visible = false
	if player and "ui_opened" in player: player.ui_opened = false
	_set_hud_visible(true)

func _exit_topdown() -> void:
	if not _topdown_active or _cam_phase != 0: return
	_play_mode_active = false
	shop_panel.visible = false
	_set_hud_visible(true)
	_start_cam_arc_close()

func is_panel_open() -> bool:
	return shop_panel != null and shop_panel.visible

# ───────────────────────────────────────────────────────────────
# INPUT  (keyboard)
# ───────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo): return

	match event.keycode:
		KEY_TAB:
			toggle_shop()
			get_viewport().set_input_as_handled()

		KEY_ESCAPE:
			if _attack_target_mode:
				_attack_target_mode = false
				shop_panel.visible  = true
				_sync_mouse()
				_show_status("Attack cancelled.")
			elif _placement_mode:
				_cancel_placement()
			elif _topdown_active:
				_exit_play_mode()
				_exit_topdown()

		KEY_ENTER, KEY_KP_ENTER:
			if shop_panel.visible:
				_activate_focused()

		KEY_UP:
			if shop_panel.visible:
				_focused_index = max(0, _focused_index - 1)
				_update_tab_hint()
				var btns : Array = _tab_buttons[_focused_tab]
				if _focused_index < btns.size():
					(btns[_focused_index] as Button).grab_focus()

		KEY_DOWN:
			if shop_panel.visible:
				_focused_index = min(_tab_buttons[_focused_tab].size() - 1, _focused_index + 1)
				_update_tab_hint()
				var btns : Array = _tab_buttons[_focused_tab]
				if _focused_index < btns.size():
					(btns[_focused_index] as Button).grab_focus()

		KEY_LEFT:
			if shop_panel.visible:
				_focused_tab   = max(0, _focused_tab - 1)
				_focused_index = 0
				tab_container.current_tab = _focused_tab
				_update_tab_hint()
				var btns : Array = _tab_buttons[_focused_tab]
				if btns.size() > 0: (btns[0] as Button).grab_focus()

		KEY_RIGHT:
			if shop_panel.visible:
				_focused_tab   = min(TAB_NAMES.size() - 1, _focused_tab + 1)
				_focused_index = 0
				tab_container.current_tab = _focused_tab
				_update_tab_hint()
				var btns : Array = _tab_buttons[_focused_tab]
				if btns.size() > 0: (btns[0] as Button).grab_focus()

# ───────────────────────────────────────────────────────────────
# UNHANDLED INPUT  (mouse clicks)
# Using _unhandled_input so clicks that miss UI children are caught.
# ───────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed): return

	# ── Play mode: left-click = fire ────────────────────────────────────────
	if _play_mode_active and not _placement_mode and not _attack_target_mode:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_topdown_fire()
			get_viewport().set_input_as_handled()
			return

	# ── Attack-target mode: click to designate attack position ───────────────
	if _attack_target_mode:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				var hit : Variant = _raycast_ground()
				if hit:
					var dest : Vector3 = hit
					_for_each_owned_unit(func(unit: Node) -> void:
						if not unit.has_method("set_ai_mode"): return
						unit.set_ai_mode(BaseCreep.AIMode.ATTACK)
						if "owner_player"    in unit: unit.owner_player    = null
						if "move_target"     in unit: unit.move_target     = dest
						if "has_move_target" in unit: unit.has_move_target = true
					)
					_attack_target_mode = false
					shop_panel.visible  = true
					_sync_mouse()
					_show_status("⚔ Zombies moving to attack position!")
			MOUSE_BUTTON_RIGHT:
				_attack_target_mode = false
				shop_panel.visible  = true
				_sync_mouse()
				_show_status("Attack cancelled.")
		get_viewport().set_input_as_handled()
		return

	# ── Placement mode ───────────────────────────────────────────────────────
	if _placement_mode:
		match event.button_index:
			MOUSE_BUTTON_LEFT:  _place_turret()
			MOUSE_BUTTON_RIGHT: _cancel_placement()
		get_viewport().set_input_as_handled()
		return

# ───────────────────────────────────────────────────────────────
# PURCHASE HANDLERS
# ───────────────────────────────────────────────────────────────
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
	var cost : int       = PLAYER_UPGRADE_COSTS[index] if index < PLAYER_UPGRADE_COSTS.size() else 0
	if not _check_funds(cost): return
	var upg : Dictionary = PLAYER_UPGRADES[index]
	if player and player.has_method("apply_upgrade"):
		player.apply_upgrade(upg["stat"], upg["amount"])
	_show_status("⬆ %s applied!" % upg["label"])

func _on_base_upgrade_selected(index: int) -> void:
	var cost : int       = BASE_UPGRADE_COSTS[index] if index < BASE_UPGRADE_COSTS.size() else 0
	if not _check_funds(cost): return
	var upg : Dictionary = BASE_UPGRADES[index]
	var applied := false
	for b in get_tree().get_nodes_in_group("bases"):
		if "team_id" in b and b.team_id == _player_team_id:
			if b.has_method("add_health"):
				b.add_health(upg["amount"])
				applied = true
			else:
				if "max_health"     in b: b.max_health     += upg["amount"]
				if "current_health" in b: b.current_health += upg["amount"]
				applied = true
			break
	_show_status("🏯 %s applied!" % upg["label"] if applied else "⚠ Base not found!")

func _on_creep_upgrade_selected(index: int, tid: int) -> void:
	var cost : int       = CREEP_UPGRADE_COSTS[index] if index < CREEP_UPGRADE_COSTS.size() else 0
	if not _check_funds(cost): return
	var upg : Dictionary = CREEP_UPGRADES[index].duplicate()
	upg["team_id"] = tid
	if game_manager and game_manager.has_method("add_creep_upgrade"):
		game_manager.add_creep_upgrade(tid, upg)
	_show_status("⬆ T%d %s applied!" % [tid, upg["label"]])

func _assign_surround_offset(creep: Node, slot_index: int, total_slots: int) -> void:
	if not is_instance_valid(creep): return
	if not "attack_offset" in creep: return
	var base_angle : float = (TAU / max(total_slots, 1)) * slot_index
	var angle      : float = base_angle + randf_range(-CREEP_ANGLE_SPREAD, CREEP_ANGLE_SPREAD)
	var radius     : float = CREEP_ORBIT_RADIUS + randf_range(-0.4, 0.6)
	creep.attack_offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

# ───────────────────────────────────────────────────────────────
# TURRET PLACEMENT
# ───────────────────────────────────────────────────────────────
func _enter_placement_mode(index: int) -> void:
	_placement_mode       = true
	_current_turret_index = index
	_placement_scene      = turret_scenes[index]
	shop_panel.visible    = false
	placement_hint_label.visible = true
	if player and "ui_opened" in player: player.ui_opened = true
	_sync_mouse()
	_spawn_ghost(_placement_scene)

func _cancel_placement() -> void:
	_destroy_ghost()
	_placement_mode       = false
	_placement_scene      = null
	_current_turret_index = -1
	placement_hint_label.visible = false
	if _topdown_active:
		shop_panel.visible = true
		if player and "ui_opened" in player: player.ui_opened = false
		_sync_mouse()
	else:
		_exit_topdown()

func _place_turret() -> void:
	var hit : Variant = _raycast_ground()
	if not hit: return
	if not _is_placement_valid(hit):
		_show_status("⚠ Too far from your base! (max %d units)" % int(MAX_TURRET_DISTANCE))
		return
	var instance := _placement_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(instance)
	instance.global_position = hit
	if "team_id"  in instance: instance.team_id  = _player_team_id
	if "owner_id" in instance: instance.owner_id = _player_instance_id
	_destroy_ghost()
	_placement_mode       = false
	_placement_scene      = null
	_current_turret_index = -1
	placement_hint_label.visible = false
	if _topdown_active:
		shop_panel.visible = true
		if player and "ui_opened" in player: player.ui_opened = false
		_sync_mouse()
	else:
		_exit_topdown()

# ───────────────────────────────────────────────────────────────
# HELPERS
# ───────────────────────────────────────────────────────────────
func _show_status(text: String) -> void:
	if status_label: status_label.text = text

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

func _refresh_picker_gold() -> void:
	if not game_manager or not is_instance_valid(_picker_gold_lbl): return
	var gold : int = game_manager.get_gold(_player_team_id)
	_picker_gold_lbl.text = "💰 %d" % gold

	var owned_count := _count_owned_units()
	_picker_squad_lbl.text = "My Squad: %d" % owned_count

	for i in _picker_row_btns.size():
		if i >= _creep_catalogue.size(): break
		_picker_row_btns[i].modulate = Color.WHITE if gold >= _creep_catalogue[i]["cost"] \
			else Color(0.55, 0.55, 0.55, 0.85)
	if _picker_selected_index >= 0:
		_refresh_picker_confirm()
