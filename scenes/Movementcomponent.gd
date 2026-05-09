# ============================================================
# MovementComponent.gd
# Handles FPS + TopDown movement, dash, gravity, jump
# ============================================================
extends ActorComponent
class_name MovementComponent

# ── Exports ──────────────────────────────────────────────────
@export_group("Movement")
@export var walk_speed    : float = 7.0
@export var sprint_speed  : float = 11.0
@export var acceleration  : float = 14.0
@export var air_control   : float = 4.0
@export var jump_velocity : float = 6.5
@export var gravity_force : float = 20.0

@export_group("Dash")
@export var dash_speed    : float = 18.0
@export var dash_time     : float = 0.15
@export var dash_cooldown : float = 0.8

# ── State ─────────────────────────────────────────────────────
var move_input   : Vector2  = Vector2.ZERO
var wish_dir     : Vector3  = Vector3.ZERO
var _dash_active : bool     = false
var _dash_timer  : float    = 0.0
var _dash_cd     : float    = 0.0
var _dash_dir    : Vector3  = Vector3.ZERO

# ── Signals ───────────────────────────────────────────────────
signal jumped
signal landed
signal dashed

# ── Dependencies (set by player) ──────────────────────────────
var camera_component  : Node = null   # CameraComponent ref
var ability_component : Node = null   # AbilityComponent ref

func _ready() -> void:
	initialize(get_parent() as CharacterBody3D)


# ── Called from player._physics_process ──────────────────────
func tick_fps(delta: float) -> void:
	if not is_instance_valid(actor): return
	_apply_gravity(delta)
	_handle_fps_movement(delta)

func tick_topdown(delta: float) -> void:
	if not is_instance_valid(actor): return
	_apply_gravity(delta)
	_handle_topdown_movement(delta)

func tick_idle(delta: float) -> void:
	if not is_instance_valid(actor): return
	_apply_gravity(delta)
	actor.velocity.x = move_toward(actor.velocity.x, 0.0, acceleration * delta * 10.0)
	actor.velocity.z = move_toward(actor.velocity.z, 0.0, acceleration * delta * 10.0)


# ── Gravity ───────────────────────────────────────────────────
func _apply_gravity(delta: float) -> void:
	if not actor.is_on_floor():
		actor.velocity.y -= gravity_force * delta
	elif actor.velocity.y < 0.0:
		actor.velocity.y = 0.0


# ── FPS Movement ──────────────────────────────────────────────
func _handle_fps_movement(delta: float) -> void:
	var strafe := 0.0
	var fwd    := 0.0

	if Input.is_key_pressed(KEY_D): strafe += 1.0
	if Input.is_key_pressed(KEY_A): strafe -= 1.0
	if Input.is_key_pressed(KEY_W): fwd    += 1.0
	if Input.is_key_pressed(KEY_S): fwd    -= 1.0

	move_input = Vector2(strafe, fwd)

	var forward := -actor.global_transform.basis.z
	var right   :=  actor.global_transform.basis.x
	wish_dir     = (forward * fwd + right * strafe)
	wish_dir.y   = 0.0
	if wish_dir.length_squared() > 0.01:
		wish_dir = wish_dir.normalized()

	var spd  := _effective_speed()
	var ctrl := acceleration if actor.is_on_floor() else air_control
	actor.velocity.x = move_toward(actor.velocity.x, wish_dir.x * spd, ctrl * delta * 10.0)
	actor.velocity.z = move_toward(actor.velocity.z, wish_dir.z * spd, ctrl * delta * 10.0)

	if Input.is_action_just_pressed("p1_jump") and actor.is_on_floor():
		actor.velocity.y = jump_velocity
		jumped.emit()


# ── TopDown Movement ──────────────────────────────────────────
func _handle_topdown_movement(delta: float) -> void:
	if _dash_cd > 0.0: _dash_cd -= delta
	if _dash_active:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			_dash_active = false
		else:
			actor.velocity.x = _dash_dir.x * dash_speed
			actor.velocity.z = _dash_dir.z * dash_speed
			return

	var strafe := 0.0
	var fwd    := 0.0
	if Input.is_key_pressed(KEY_D): strafe += 1.0
	if Input.is_key_pressed(KEY_A): strafe -= 1.0
	if Input.is_key_pressed(KEY_W): fwd    += 1.0
	if Input.is_key_pressed(KEY_S): fwd    -= 1.0

	move_input = Vector2(strafe, fwd)
	wish_dir   = Vector3(strafe, 0.0, -fwd)
	if wish_dir.length_squared() > 0.01:
		wish_dir = wish_dir.normalized()

	# Dash
	if Input.is_action_just_pressed("p1_dash") and _dash_cd <= 0.0 \
			and wish_dir.length_squared() > 0.01:
		_dash_active = true
		_dash_timer  = dash_time
		_dash_cd     = dash_cooldown
		_dash_dir    = wish_dir
		dashed.emit()
		return

	var spd := _effective_speed()
	if wish_dir.length_squared() > 0.01:
		actor.velocity.x = lerp(actor.velocity.x, wish_dir.x * spd, acceleration * delta)
		actor.velocity.z = lerp(actor.velocity.z, wish_dir.z * spd, acceleration * delta)
	else:
		actor.velocity.x = lerp(actor.velocity.x, 0.0, 18.0 * delta)
		actor.velocity.z = lerp(actor.velocity.z, 0.0, 18.0 * delta)


# ── Topdown aim toward cursor ─────────────────────────────────
func face_cursor(delta: float, td_camera: Camera3D, td_aim_smoothing: float,
		td_flip_facing: bool, aim_angle: float) -> float:
	if not is_instance_valid(td_camera): return aim_angle
	var mpos   := actor.get_viewport().get_mouse_position()
	var origin := td_camera.project_ray_origin(mpos)
	var ray    := td_camera.project_ray_normal(mpos)
	var plane  := Plane(Vector3.UP, actor.global_position.y)
	var hit     = plane.intersects_ray(origin, ray)
	if hit == null: return aim_angle
	var target  : Vector3 = hit
	target.y = actor.global_position.y
	var dir := target - actor.global_position
	if dir.length_squared() < 0.001: return aim_angle
	var target_angle := atan2(-dir.x, -dir.z) + (PI if td_flip_facing else 0.0)
	var new_angle    := lerp_angle(aim_angle, target_angle, td_aim_smoothing * delta)
	actor.rotation.y  = new_angle
	return new_angle


# ── Shop-driven movement (called by shop.gd) ──────────────────
func topdown_move(dir: Vector3, _delta: float) -> void:
	var spd := _effective_speed()
	if dir.length_squared() > 0.01:
		actor.velocity.x = dir.x * spd
		actor.velocity.z = dir.z * spd
	else:
		var dt := get_physics_process_delta_time()
		actor.velocity.x = move_toward(actor.velocity.x, 0.0, spd * dt * 10.0)
		actor.velocity.z = move_toward(actor.velocity.z, 0.0, spd * dt * 10.0)


# ── Helpers ───────────────────────────────────────────────────
func _effective_speed() -> float:
	var spd := sprint_speed if Input.is_action_pressed("p1_sprint") else walk_speed
	if is_instance_valid(ability_component):
		if ability_component.has_method("get_speed_multiplier"):
			spd *= ability_component.get_speed_multiplier()
	return spd

func is_dashing() -> bool: return _dash_active
