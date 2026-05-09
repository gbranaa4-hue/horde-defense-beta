# ============================================================
# SplitScreenManager.gd
# ============================================================
extends Node

const PLAYER_SCENE_PATH := "res://scenes/Player.tscn"
const HUD_SCENE_PATH    := "res://scenes/ui.tscn"

@export var player_scene : PackedScene
@export var hud_scene    : PackedScene
@export var level_root   : Node
@export var spawn_points : Array[Node] = []
@export var player_count : int = 1

var _containers : Array[SubViewportContainer] = []
var _viewports  : Array[SubViewport]          = []
var _players    : Array[Node]                 = []
var _cameras    : Array[Camera3D]             = []
var _spawned    := false


# ============================================================
func _ready() -> void:
	add_to_group("splitscreen_manager")

	var ctrl := Control.new()
	ctrl.name         = "ViewportRoot"
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ctrl)

	await get_tree().process_frame
	_boot()


func _boot() -> void:
	if _spawned:
		return
	_spawned = true

	# Pull count from GameSettings autoload
	var gs := get_node_or_null("/root/GameSettings")
	if is_instance_valid(gs) and "player_count" in gs:
		player_count = gs.player_count

	if player_count <= 0:
		player_count = 1

	# Load scenes
	if not is_instance_valid(player_scene):
		player_scene = load(PLAYER_SCENE_PATH)
	if not is_instance_valid(hud_scene):
		hud_scene = load(HUD_SCENE_PATH)

	if not is_instance_valid(player_scene):
		push_error("[SplitScreen] player_scene not found: " + PLAYER_SCENE_PATH)
		return

	_clear()

	var size := get_viewport().get_visible_rect().size
	print("[SplitScreen] Starting | players=%d | screen=%s" % [player_count, str(size)])

	for i in range(player_count):
		var vp := _make_viewport(i, player_count, size)
		_spawn(i, vp)

	# Wait two frames so all @onready refs in player are valid before attaching cameras
	await get_tree().process_frame
	await get_tree().process_frame
	_attach_cameras()

	await get_tree().physics_frame
	await _apply_spawn_positions()


# ============================================================
# VIEWPORT
# ============================================================
func _make_viewport(idx: int, total: int, size: Vector2) -> SubViewport:
	var hw := int(size.x * 0.5)
	var hh := int(size.y * 0.5)

	var container := SubViewportContainer.new()
	container.name    = "VP_Container_P%d" % (idx + 1)
	container.stretch = true

	match total:
		1:
			container.position = Vector2.ZERO
			container.size     = size
		2:
			container.position = Vector2(hw * idx, 0)
			container.size     = Vector2(hw, size.y)
		_:
			var row := idx / 2
			var col := idx % 2
			container.position = Vector2(hw * col, hh * row)
			container.size     = Vector2(hw, hh)

	get_node("ViewportRoot").add_child(container)
	_containers.append(container)

	var vp_w := int(size.x) if total == 1 else hw
	var vp_h := int(size.y) if total <= 2 else hh

	var vp := SubViewport.new()
	vp.name                      = "VP_P%d" % (idx + 1)
	vp.size                      = Vector2i(vp_w, vp_h)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d              = false
	vp.world_3d                  = get_viewport().world_3d
	vp.handle_input_locally      = false

	container.add_child(vp)
	_viewports.append(vp)

	return vp


# ============================================================
# ATTACH CAMERAS
# Camera stays in player scene tree (so @onready refs stay valid).
# RenderingServer links it to the SubViewport so Terrain3D renders.
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
			push_error("[SplitScreen] P%d: No Camera3D found." % (i + 1))
			_cameras.append(null)
			continue

		# Detach from main viewport, attach to SubViewport
		cam.current = false
		RenderingServer.viewport_attach_camera(vp.get_viewport_rid(), cam.get_camera_rid())
		# Terrain3D needs current=true to render in the attached viewport
		cam.current = true

		_cameras.append(cam)
		print("[SplitScreen] P%d camera attached OK" % (i + 1))


# ============================================================
# DEVICE
# ============================================================
func _device(idx: int) -> int:
	if idx == 0:
		return -1
	var pads := Input.get_connected_joypads()
	if idx - 1 < pads.size():
		return pads[idx - 1]
	return -99


# ============================================================
# SPAWN POINT
# ============================================================
func _spawn_pos(idx: int) -> Vector3:
	var valid : Array = []
	for sp in spawn_points:
		if is_instance_valid(sp) and sp is Node3D:
			valid.append(sp)
	if valid.size() > 0:
		return (valid[idx % valid.size()] as Node3D).global_position
	push_warning("[SplitScreen] No valid spawn points — fallback for P%d" % (idx + 1))
	return Vector3(float(idx) * 3.0, 1.0, 0.0)


# ============================================================
# APPLY SPAWN POSITIONS
# ============================================================
func _apply_spawn_positions() -> void:
	for i in range(_players.size()):
		var p := _players[i]
		if not is_instance_valid(p):
			continue
		p.set_physics_process(false)
		if "velocity" in p:
			p.velocity = Vector3.ZERO
		p.global_position = _spawn_pos(i)

	await get_tree().physics_frame

	for p in _players:
		if is_instance_valid(p):
			if "velocity" in p:
				p.velocity = Vector3.ZERO
			p.set_physics_process(true)


# ============================================================
# SPAWN PLAYER
# ============================================================
func _spawn(idx: int, vp: SubViewport) -> void:
	var pid    := idx + 1
	var device := _device(idx)

	var player : Node = player_scene.instantiate()
	player.set("player_id", pid)
	player.set("device_id", device)
	player.set("team_id",   pid)
	player.set_meta("player_id", pid)

	inputsetup.setup_player_inputs(pid, device)

	var root : Node = level_root if is_instance_valid(level_root) \
			else get_tree().current_scene
	root.add_child(player)
	player.global_position = _spawn_pos(idx)

	# ── HUD ──
	if not is_instance_valid(hud_scene):
		push_warning("[SplitScreen] P%d: no hud_scene — skipping UI." % pid)
		_players.append(player)
		return

	var hud_root : Node = hud_scene.instantiate()
	vp.add_child(hud_root)

	var hud : Node = hud_root.get_node_or_null("Control")
	if is_instance_valid(hud):
		if hud.has_method("bind_player"):
			hud.bind_player(player)
			print("[SplitScreen] P%d HUD bound OK" % pid)
		else:
			push_error("[SplitScreen] P%d: Control missing bind_player()" % pid)
	else:
		push_error("[SplitScreen] P%d: 'Control' not found in HUD" % pid)

	var shop : Node = hud_root.get_node_or_null("Control/SHOPUI")
	if is_instance_valid(shop):
		if player.has_method("bind_shop"):
			player.bind_shop(shop)
			print("[SplitScreen] P%d shop bound OK" % pid)
		else:
			push_error("[SplitScreen] P%d: player missing bind_shop()" % pid)
	else:
		push_error("[SplitScreen] P%d: Control/SHOPUI not found" % pid)

	_players.append(player)
	print("[SplitScreen] P%d spawned | device=%d | team=%d | pos=%s" % [
		pid, device, pid, str(player.global_position)
	])


# ============================================================
# CAMERA FALLBACK
# ============================================================
func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node as Camera3D
	for child in node.get_children():
		var result := _find_camera(child)
		if result:
			return result
	return null


# ============================================================
# SHOP INPUT TOGGLE
# ============================================================
func set_viewport_input(player_idx: int, enabled: bool) -> void:
	if player_idx >= 0 and player_idx < _viewports.size():
		_viewports[player_idx].handle_input_locally = enabled


# ============================================================
# PUBLIC API
# ============================================================
func get_player(idx: int) -> Node:
	if idx >= 0 and idx < _players.size():
		return _players[idx]
	return null

func get_all_players() -> Array[Node]:
	return _players.duplicate()

func restart() -> void:
	_spawned = false
	_clear()
	await get_tree().process_frame
	_boot()


# ============================================================
# CLEANUP
# ============================================================
func _clear() -> void:
	for p in _players:
		if is_instance_valid(p):
			p.queue_free()
	_players.clear()
	for c in _containers:
		if is_instance_valid(c):
			c.queue_free()
	_containers.clear()
	_viewports.clear()
	_cameras.clear()
