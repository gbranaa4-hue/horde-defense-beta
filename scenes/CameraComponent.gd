# ============================================================
# CameraComponent.gd
# Owns all camera logic: FPS look, topdown, transitions, zoom
# ============================================================
extends ActorComponent
class_name CameraComponent

# ── Camera node refs (assigned by player after scene ready) ──
var fps_pivot  : Node3D   = null
var fps_camera : Camera3D = null
var td_pivot   : Node3D   = null
var td_camera  : Camera3D = null

# ── Exports ───────────────────────────────────────────────────
@export_group("Mouse")
@export var mouse_sensitivity : float = 0.15
@export var mouse_smoothing   : float = 18.0
@export var max_look_up       : float = 89.0
@export var max_look_down     : float = -89.0

@export_group("Camera FX")
@export var headbob_amount : float = 0.05
@export var headbob_speed  : float = 10.0
@export var sway_amount    : float = 1.5
@export var sway_smoothing : float = 8.0
@export var tilt_amount    : float = 3.0

@export_group("TopDown")
@export var topdown_height       : float = 22.0
@export var topdown_angle        : float = -70.0
@export var td_aim_smoothing     : float = 14.0
@export var td_flip_facing       : bool  = false
@export var td_zoom_min          : float = 20.0
@export var td_zoom_max          : float = 28.0
@export var td_zoom_speed        : float = 1.2
@export var td_enemy_scan_radius : float = 25.0

@export_group("FPS")
@export var eye_height : float = 1.65

# ── State ─────────────────────────────────────────────────────
var mouse_input   : Vector2 = Vector2.ZERO
var smooth_mouse  : Vector2 = Vector2.ZERO
var recoil        : float   = 0.0
var headbob_timer : float   = 0.0
var _combat_zoom  : float   = 22.0
var _td_aim_angle : float   = 0.0

enum Mode { FPS, TOPDOWN }
var current_mode  : Mode = Mode.FPS

# ── Debug ─────────────────────────────────────────────────────
@export var debug_mouse : bool = false
var _dbg_mouse_count : int   = 0
var _dbg_mouse_timer : float = 0.0

# ── Signals ───────────────────────────────────────────────────
signal mode_changed(new_mode: Mode)

func _ready() -> void:
	initialize(get_parent() as CharacterBody3D)


# ── Called from player after cameras are resolved ─────────────
func setup_cameras(fps_piv: Node3D, fps_cam: Camera3D,
		td_piv: Node3D, td_cam: Camera3D) -> void:
	fps_pivot  = fps_piv
	fps_camera = fps_cam
	td_pivot   = td_piv
	td_camera  = td_cam

	fps_camera.current   = true
	fps_camera.position  = Vector3.ZERO
	fps_camera.rotation  = Vector3.ZERO
	fps_pivot.position   = Vector3(0.0, eye_height, 0.0)

	td_camera.current    = false
	td_camera.rotation   = Vector3.ZERO
	td_pivot.position    = Vector3(0.0, topdown_height, 0.0)
	td_pivot.rotation_degrees = Vector3(topdown_angle, 0.0, 0.0)
	call_deferred("_init_td_look")

func _init_td_look() -> void:
	if is_instance_valid(td_camera) and is_instance_valid(actor):
		td_camera.global_position = actor.global_position + Vector3(0.0, topdown_height, 0.0)
		td_camera.look_at(actor.global_position + Vector3(0.0, 0.8, 0.0), Vector3.FORWARD)


# ── FPS process ───────────────────────────────────────────────
func tick_fps(delta: float, velocity: Vector3, move_input: Vector2) -> void:
	_handle_mouse_look(delta)
	_handle_camera_fx(delta, velocity, move_input)
	_update_fov(delta)
	recoil = lerp(recoil, 0.0, delta * 12.0)

	if debug_mouse:
		_dbg_mouse_timer += delta
		if _dbg_mouse_timer > 1.0:
			_dbg_mouse_timer = 0.0
			print("[CameraComponent] mouse events/s=%d | mode=%s | captured=%s" % [
				_dbg_mouse_count, Mode.keys()[current_mode],
				str(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)])
			_dbg_mouse_count = 0


# ── TopDown process ───────────────────────────────────────────
func tick_topdown(delta: float) -> void:
	if not is_instance_valid(td_camera) or not is_instance_valid(actor): return
	_update_dynamic_zoom(delta)


# ── Mouse look ────────────────────────────────────────────────
func add_mouse_input(relative: Vector2) -> void:
	mouse_input += relative
	if debug_mouse: _dbg_mouse_count += 1

func _handle_mouse_look(delta: float) -> void:
	smooth_mouse = smooth_mouse.lerp(mouse_input, mouse_smoothing * delta)
	var rel      := smooth_mouse
	mouse_input   = Vector2.ZERO
	if rel.length_squared() < 0.00001: return
	actor.rotate_y(deg_to_rad(-rel.x * mouse_sensitivity))
	if is_instance_valid(fps_pivot):
		fps_pivot.rotation_degrees.x -= rel.y * mouse_sensitivity
		fps_pivot.rotation_degrees.x  = clamp(
			fps_pivot.rotation_degrees.x, max_look_down, max_look_up)
		fps_pivot.rotation_degrees.x  += recoil


# ── Camera FX ─────────────────────────────────────────────────
func _handle_camera_fx(delta: float, velocity: Vector3, move_input: Vector2) -> void:
	if not is_instance_valid(fps_camera): return
	var spd2d := Vector2(velocity.x, velocity.z).length()
	# Headbob
	if spd2d > 0.5 and actor.is_on_floor():
		headbob_timer += delta * headbob_speed
		var target_bob : float = sin(headbob_timer) * headbob_amount
		fps_camera.position.y = lerp(fps_camera.position.y, target_bob, 10.0 * delta)
	else:
		fps_camera.position.y = lerp(fps_camera.position.y, 0.0, 10.0 * delta)
	# Sway
	fps_camera.rotation_degrees.y = lerp(fps_camera.rotation_degrees.y,
		-smooth_mouse.x * 0.01 * sway_amount, sway_smoothing * delta)
	fps_camera.rotation_degrees.z = lerp(fps_camera.rotation_degrees.z,
		-move_input.x * tilt_amount, 6.0 * delta)
	fps_camera.rotation.z = 0.0  # prevent drift


# ── FOV ───────────────────────────────────────────────────────
func _update_fov(delta: float) -> void:
	if not is_instance_valid(fps_camera): return
	var target := 55.0 if Input.is_action_pressed("p1_aim") \
		else (85.0 if Input.is_action_pressed("p1_sprint") else 75.0)
	fps_camera.fov = lerp(fps_camera.fov, target, delta * 10.0)


# ── Dynamic zoom ──────────────────────────────────────────────
func _update_dynamic_zoom(delta: float) -> void:
	var score := 0.0
	score += actor.velocity.length() * 0.04
	for z in actor.get_tree().get_nodes_in_group("zombies"):
		if not (z is Node3D): continue
		var d := actor.global_position.distance_to((z as Node3D).global_position)
		if d < td_enemy_scan_radius:
			score += (1.0 - d / td_enemy_scan_radius) * 0.3
	score = clamp(score, 0.0, 1.0)
	var target_zoom : float = lerp(td_zoom_min, td_zoom_max, score)
	_combat_zoom = lerp(_combat_zoom, target_zoom, td_zoom_speed * delta)
	td_camera.global_position = actor.global_position + Vector3(0.0, _combat_zoom, 0.0)
	td_camera.look_at(actor.global_position + Vector3(0.0, 0.8, 0.0), Vector3.FORWARD)
	td_pivot.global_position  = td_camera.global_position


# ── Mode switching ────────────────────────────────────────────
func set_mode(mode: Mode, ssm: Node = null) -> void:
	current_mode = mode
	if mode == Mode.TOPDOWN:
		fps_pivot.rotation = Vector3.ZERO
		fps_camera.current = false
		td_camera.current  = true
		_switch_camera_rid(td_camera, ssm)
		td_pivot.global_position   = actor.global_position + Vector3(0.0, topdown_height, 0.0)
		td_pivot.global_rotation   = Vector3.ZERO
		td_camera.rotation_degrees = Vector3(topdown_angle, 0.0, 0.0)
	else:
		td_camera.current  = false
		fps_camera.current = true
		fps_pivot.rotation = Vector3.ZERO
		_switch_camera_rid(fps_camera, ssm)
	mode_changed.emit(mode)

func _switch_camera_rid(cam: Camera3D, ssm: Node) -> void:
	if is_instance_valid(ssm) and ssm.has_method("switch_player_camera"):
		ssm.switch_player_camera(actor, cam)
		return
	var my_world := actor.get_world_3d()
	for vp_node in _find_subviewports(actor.get_tree().root):
		var vp := vp_node as SubViewport
		if is_instance_valid(vp) and not vp.own_world_3d and vp.world_3d == my_world:
			var vp_rid  : RID = vp.get_viewport_rid()
			var cam_rid : RID = cam.get_camera_rid()
			RenderingServer.viewport_attach_camera(vp_rid, cam_rid)
			return
	cam.make_current()

func _find_subviewports(node: Node) -> Array:
	var result : Array = []
	if node is SubViewport: result.append(node)
	for child in node.get_children():
		result.append_array(_find_subviewports(child))
	return result

func is_topdown() -> bool: return current_mode == Mode.TOPDOWN
func get_shoot_origin() -> Vector3:
	if current_mode == Mode.FPS: return fps_camera.global_position
	return actor.global_position + Vector3.UP * 1.5
func get_shoot_direction() -> Vector3:
	if current_mode == Mode.FPS: return -fps_camera.global_transform.basis.z
	var mpos   := actor.get_viewport().get_mouse_position()
	var origin := td_camera.project_ray_origin(mpos)
	var dir    := td_camera.project_ray_normal(mpos)
	var plane  := Plane(Vector3.UP, actor.global_position.y)
	var hit     = plane.intersects_ray(origin, dir)
	return (hit - actor.global_position).normalized() if hit != null \
		else -actor.global_transform.basis.z

func apply_recoil(amount: float) -> void: recoil -= amount
