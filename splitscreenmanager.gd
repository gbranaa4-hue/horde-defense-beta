# ============================================================
# SplitScreenManager.gd (Godot 4.6)
# ============================================================
# Reads player_count and team_assignments from GameSettings.
# Only spawns human players — AI is handled by AIPlayer.gd.
# Device assignment: detects connected gamepads and assigns
# them to players in order. First player always gets KBM (-1)
# unless no keyboard is expected (future: configurable).
# ============================================================
extends Node

const PLAYER_SCENE_PATH := "res://scenes/Player.tscn"
const HUD_SCENE_PATH    := "res://scenes/ui.tscn"

@export var player_scene : PackedScene
@export var hud_scene    : PackedScene
@export var level_root   : Node
@export var spawn_points : Array[Node3D] = []

var _containers : Array[SubViewportContainer] = []
var _viewports  : Array[SubViewport]          = []
var _players    : Array[Node]                 = []
var _spawned    : bool                        = false

# Resolved at boot from GameSettings
var _player_count     : int        = 1
var _team_assignments : Dictionary = {}   # player_idx (0-based) -> team_id


# ============================================================
func _ready() -> void:
	add_to_group("splitscreen_manager")

	var ctrl := Control.new()
	ctrl.name         = "ViewportRoot"
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ctrl)

	await get_tree().process_frame
	await _boot()


# ============================================================
# BOOT
# ============================================================
func _boot() -> void:
	if _spawned:
		return
	_spawned = true

	_load_settings()

	if not player_scene:
		player_scene = load(PLAYER_SCENE_PATH)
		if not player_scene:
			push_error("[SSM] Missing player scene: " + PLAYER_SCENE_PATH)
			return

	if not hud_scene:
		hud_scene = load(HUD_SCENE_PATH)
		if not hud_scene:
			push_warning("[SSM] Missing HUD scene — continuing without UI")

	_clear()

	var screen_size := get_viewport().get_visible_rect().size
	print("[SSM] Starting | players=%d | screen=%s" % [_player_count, str(screen_size)])
	for i in range(_player_count):
		print("[SSM]   P%d → team=%d | device=%s" % [
			i + 1,
			_team_assignments.get(i, i + 1),
			str(_device(i))
		])

	for i in range(_player_count):
		var vp := _make_viewport(i, _player_count, screen_size)
		_spawn(i, vp)

	await get_tree().process_frame
	await get_tree().process_frame
	_attach_cameras()
	# Register topdown cameras — must run after _ready() so _td_camera exists
	await get_tree().process_frame
	_register_topdown_cameras()

	await get_tree().physics_frame
	await _apply_spawn_positions()


# ============================================================
# LOAD SETTINGS FROM GameSettings AUTOLOAD
# ============================================================
func _load_settings() -> void:
	var gs := get_node_or_null("/root/GameSettings")
	if not is_instance_valid(gs):
		push_warning("[SSM] GameSettings not found — defaulting to 1 player.")
		_player_count     = 1
		_team_assignments = { 0: 1 }
		return

	_player_count = max(gs.player_count, 1)

	# Copy team assignments, filling any gaps with alternating teams
	_team_assignments = {}
	for i in range(_player_count):
		_team_assignments[i] = gs.team_assignments.get(i, (i % 2) + 1)

	print("[SSM] Loaded from GameSettings | players=%d | ai_enabled=%s | ai_team=%d" % [
		_player_count,
		str(gs.get("ai_enabled") if "ai_enabled" in gs else false),
		int(gs.get("ai_team_id") if "ai_team_id" in gs else 2)
	])


# ============================================================
# VIEWPORT CREATION
# ============================================================
func _make_viewport(idx: int, total: int, size: Vector2) -> SubViewport:
	var hw := int(size.x * 0.5)
	var hh := int(size.y * 0.5)

	var container := SubViewportContainer.new()
	container.name          = "VP_Container_P%d" % (idx + 1)
	container.stretch       = true
	container.clip_contents = true
	container.mouse_filter  = Control.MOUSE_FILTER_PASS

	match total:
		1:
			container.position = Vector2.ZERO
			container.size     = size
		2:
			container.position = Vector2(hw * idx, 0)
			container.size     = Vector2(hw, size.y)
		_:
			container.position = Vector2(hw * (idx % 2), hh * int(idx / 2))
			container.size     = Vector2(hw, hh)

	get_node("ViewportRoot").add_child(container)
	_containers.append(container)

	var vp := SubViewport.new()
	vp.name                      = "VP_P%d" % (idx + 1)
	vp.size                      = Vector2i(
		int(size.x) if total == 1 else hw,
		int(size.y) if total <= 2 else hh
	)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d              = false
	vp.world_3d                  = get_viewport().world_3d
	vp.handle_input_locally      = false
	vp.audio_listener_enable_3d  = false

	container.add_child(vp)
	_viewports.append(vp)
	return vp


# ============================================================
# ATTACH CAMERAS
# ============================================================
func _attach_cameras() -> void:
	for i in range(_players.size()):
		var player := _players[i]
		var vp     := _viewports[i]
		if not is_instance_valid(player) or not is_instance_valid(vp):
			continue

		var cam : Camera3D = player.get_node_or_null("Head/Camera3D")
		if not is_instance_valid(cam):
			cam = _find_camera(player)
		if not is_instance_valid(cam):
			push_error("[SSM] P%d: No Camera3D found" % (i + 1))
			continue

		cam.current = false
		RenderingServer.viewport_attach_camera(vp.get_viewport_rid(), cam.get_camera_rid())
		cam.current = true
		print("[SSM] P%d camera attached OK" % (i + 1))

	_attach_audio_listeners()


# Called by player.set_topdown_mode() to switch which camera the SubViewport renders
func switch_player_camera(player: Node, new_cam: Camera3D) -> void:
	if not is_instance_valid(player):
		push_error("[SSM] switch_player_camera: invalid player"); return
	if not is_instance_valid(new_cam):
		push_error("[SSM] switch_player_camera: invalid camera"); return
	var idx := _players.find(player)
	if idx < 0:
		push_error("[SSM] switch_player_camera: player not in _players list"); return
	if idx >= _viewports.size():
		push_error("[SSM] switch_player_camera: no viewport for idx %d" % idx); return
	var vp := _viewports[idx]
	if not is_instance_valid(vp):
		push_error("[SSM] switch_player_camera: viewport invalid"); return
	var vp_rid  := vp.get_viewport_rid()
	var cam_rid := new_cam.get_camera_rid()
	print("[SSM] P%d switching camera → %s | vp_rid=%s | cam_rid=%s" % [
		idx+1, new_cam.name, str(vp_rid), str(cam_rid)])
	RenderingServer.viewport_attach_camera(vp_rid, cam_rid)
	print("[SSM] P%d camera switch done" % (idx+1))


# Run after _ready() so _td_camera exists. Creates one if missing.
func _register_topdown_cameras() -> void:
	for i in range(_players.size()):
		var player := _players[i]
		if not is_instance_valid(player): continue

		var td : Camera3D = player.get_node_or_null("TopdownCamera")

		if not is_instance_valid(td):
			# Player _ready() may not have run yet — create it here
			push_warning("[SSM] P%d: TopdownCamera missing, creating from SSM" % (i+1))
			td           = Camera3D.new()
			td.name      = "TopdownCamera"
			td.current   = false
			td.fov       = 60.0
			td.near      = 0.1
			td.far       = 500.0
			player.add_child(td)
			# Store ref on player script
			if "set" in player:
				player.set("_td_camera", td)

		if is_instance_valid(td):
			# Position above player right now
			var height : float = float(player.get("topdown_height") if "topdown_height" in player else 18.0)
			var pitch  : float = float(player.get("topdown_pitch")  if "topdown_pitch"  in player else deg_to_rad(-75.0))
			td.global_position = player.global_position + Vector3(0, height, 0)
			td.global_rotation = Vector3(pitch, 0.0, 0.0)
			print("[SSM] P%d TopdownCamera ready | pos=%s" % [i+1, str(td.global_position)])


# ============================================================
# AUDIO LISTENERS
# ============================================================
func _attach_audio_listeners() -> void:
	for i in range(_players.size()):
		var player := _players[i]
		if not is_instance_valid(player): continue

		var head : Node3D = player.get_node_or_null("Head")
		if not is_instance_valid(head):
			push_warning("[SSM] P%d: No Head node — audio listener skipped" % (i + 1))
			continue

		var old := head.get_node_or_null("AudioListener3D")
		if is_instance_valid(old): old.queue_free()

		var listener      := AudioListener3D.new()
		listener.name     = "AudioListener3D"
		head.add_child(listener)
		listener.make_current()
		print("[SSM] P%d audio listener attached" % (i + 1))


# ============================================================
# DEVICE ASSIGNMENT
# ============================================================
func _device(player_idx: int) -> int:
	# Player index 0 always gets KBM
	if player_idx == 0:
		return -1

	# Subsequent players get gamepads in order
	var pads := Input.get_connected_joypads()
	var pad_idx := player_idx - 1
	if pad_idx < pads.size():
		return pads[pad_idx]

	# No gamepad available — assign no-input device
	push_warning("[SSM] P%d: no gamepad available (pad_idx=%d, connected=%d)" % [
		player_idx + 1, pad_idx, pads.size()
	])
	return -99


# ============================================================
# SPAWN PLAYER
# ============================================================
func _spawn(idx: int, vp: SubViewport) -> void:
	var pid    : int = idx + 1
	var device : int = _device(idx)
	var tid    : int = _team_assignments.get(idx, (idx % 2) + 1)

	var player := player_scene.instantiate()
	player.set_meta("player_id", pid)
	player.set("player_id", pid)
	player.set("device_id", device)
	player.set("team_id",   tid)

	inputsetup.setup_player_inputs(pid, device)

	var root := level_root if is_instance_valid(level_root) else get_tree().current_scene
	root.add_child(player)
	player.global_position = _spawn_pos_for_team(tid)

	# HUD + Shop
	if is_instance_valid(hud_scene):
		var hud_root := hud_scene.instantiate()
		vp.add_child(hud_root)

		var hud := hud_root.get_node_or_null("Control")
		if is_instance_valid(hud) and hud.has_method("bind_player"):
			hud.bind_player(player)
			player.set("hud", hud)
			print("[SSM] P%d HUD bound OK" % pid)
		else:
			push_error("[SSM] P%d: HUD bind failed" % pid)

		var shop := hud_root.get_node_or_null("Control/SHOPUI")
		if is_instance_valid(shop) and player.has_method("bind_shop"):
			player.bind_shop(shop)
			print("[SSM] P%d shop bound OK" % pid)
		else:
			push_error("[SSM] P%d: shop bind failed" % pid)

	_players.append(player)
	print("[SSM] P%d spawned | device=%d | team=%d | pos=%s" % [
		pid, device, tid, str(player.global_position)
	])


# ============================================================
# SPAWN POSITIONS
# ============================================================
func _spawn_pos_for_team(tid: int) -> Vector3:
	var valid : Array[Node3D] = []
	for sp in spawn_points:
		if is_instance_valid(sp):
			valid.append(sp)

	# Prefer a spawn point tagged with matching team_id meta
	for sp in valid:
		if sp.has_meta("team_id") and int(sp.get_meta("team_id")) == tid:
			return sp.global_position

	# Fall back to index: team 1 → index 0, team 2 → index 1
	if not valid.is_empty():
		var fallback_idx := clampi(tid - 1, 0, valid.size() - 1)
		return valid[fallback_idx].global_position

	# Last resort: find the team's own base and spawn near it
	for b in get_tree().get_nodes_in_group("bases"):
		if is_instance_valid(b) and "team_id" in b and int(b.get("team_id")) == tid:
			return (b as Node3D).global_position + Vector3(0.0, 1.5, 3.0)

	push_warning("[SSM] No spawn points or bases found for team %d" % tid)
	return Vector3((tid - 1) * 3.0, 1.0, 0.0)


func _apply_spawn_positions() -> void:
	for p in _players:
		if not is_instance_valid(p): continue
		p.set_physics_process(false)
		if "velocity" in p: p.velocity = Vector3.ZERO
		var tid : int = p.get("team_id") if "team_id" in p else 1
		p.global_position = _spawn_pos_for_team(tid)

	await get_tree().physics_frame

	for p in _players:
		if not is_instance_valid(p): continue
		if "velocity" in p: p.velocity = Vector3.ZERO
		p.set_physics_process(true)


# ============================================================
# CAMERA FALLBACK
# ============================================================
func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D: return node as Camera3D
	for child in node.get_children():
		var cam := _find_camera(child)
		if cam: return cam
	return null


# ============================================================
# VIEWPORT INPUT CONTROL
# ============================================================
func set_viewport_input(player_idx: int, shop_open: bool) -> void:
	if player_idx < 0 or player_idx >= _viewports.size(): return
	for i in _viewports.size():
		_viewports[i].handle_input_locally = (shop_open and i == player_idx)


# ============================================================
# PUBLIC API
# ============================================================
func get_player(idx: int) -> Node:
	return _players[idx] if idx >= 0 and idx < _players.size() else null

func get_all_players() -> Array[Node]:
	return _players.duplicate()


# ============================================================
# RESTART / CLEAR
# ============================================================
func restart() -> void:
	_spawned = false
	_clear()
	await get_tree().process_frame
	await _boot()


func _clear() -> void:
	for p in _players:
		if is_instance_valid(p): p.queue_free()
	_players.clear()
	for c in _containers:
		if is_instance_valid(c): c.queue_free()
	_containers.clear()
	_viewports.clear()
