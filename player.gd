# ============================================================
# player.gd
# ============================================================
extends CharacterBody3D

# ===============================
# EXPORTS
# ===============================
@export var walk_speed        : float = 5.0
@export var sprint_speed      : float = 9.0
@export var jump_velocity     : float = 5.0
@export var mouse_sensitivity : float = 0.002
@export var gravity           : float = 20.0
@export var gold_on_death     : int   = 100

# ===============================
# IDENTITY
# ===============================
var team_id  : int = 1
var owner_id : int = -1

# ===============================
# STATS
# ===============================
var max_health : float = 100.0
var health     : float = 100.0

const BASE_WALK_SPEED   : float = 5.0
const BASE_SPRINT_SPEED : float = 9.0

var _upgrade_bonuses : Dictionary = {
	"max_health" : 0.0,
	"move_speed" : 0.0,
	"fire_rate"  : 0.0,
	"damage"     : 0.0,
}

# ===============================
# STATE FLAGS
# ===============================
var ui_opened     : bool    = false
var topdown_mode  : bool    = false
var aim_direction : Vector3 = Vector3(0, 0, -1)
var _pitch        : float   = 0.0
var _is_dead      : bool    = false

# ===============================
# SIGNALS
# ===============================
signal health_changed(current: float, maximum: float)

# ===============================
# NODE REFS
# ===============================
@onready var head           : Node3D        = $Head
@onready var camera         : Camera3D      = $Head/Camera3D
@onready var crosshair      : Control       = $CanvasLayer/Crosshair
@onready var weapon_manager : WeaponManager = $WeaponManager

# ===============================
# ANIMATION
# ===============================
var _anim_tree : AnimationTree = null

# Blend-space: X = strafe (-1 left → +1 right), Y = forward/back (-1 fwd → +1 back)
const ANIM_LOCOMOTION := "parameters/Locomotion/blend_position"
const ANIM_JUMP       := "parameters/jump/request"
const ANIM_SHOOT      := "parameters/shoot_shot/request"
const ANIM_DEATH      := "parameters/OneShot/request"

# ================================================================
# READY
# ================================================================
func _ready() -> void:
	add_to_group("players")
	add_to_group("units")
	owner_id = get_instance_id()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	health_changed.emit(health, max_health)
	_setup_anim_tree()


func _setup_anim_tree() -> void:
	_anim_tree = get_node_or_null("AnimationTree") as AnimationTree
	if _anim_tree == null:
		for child in get_children():
			if child is AnimationTree:
				_anim_tree = child
				break
	if _anim_tree:
		_anim_tree.active = true
		print("[Player] AnimationTree found: ", _anim_tree.get_path())
	else:
		push_warning("[Player] AnimationTree not found — animations won't play.")

# ================================================================
# INPUT
# ================================================================
func _input(event: InputEvent) -> void:
	if _is_dead:
		return

	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and not topdown_mode:
			_apply_mouse_look(event.relative)
		return

	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	match event.keycode:
		KEY_TAB:
			var shop := _get_shop()
			if is_instance_valid(shop) and shop.has_method("toggle_shop"):
				shop.toggle_shop()
		KEY_1: _command_creeps(0)
		KEY_2: _command_creeps(1)
		KEY_3: _command_creeps(2)
		KEY_4: _command_creeps(3)


func _command_creeps(mode_index: int) -> void:
	var shop := _get_shop()
	if not is_instance_valid(shop): return
	if shop.has_method("command_owned_units"):
		shop.command_owned_units(mode_index)

# ================================================================
# PHYSICS
# ================================================================
func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	var was_on_floor := is_on_floor()
	_apply_gravity(delta)

	if _is_shop_panel_open():
		velocity.x = move_toward(velocity.x, 0.0, walk_speed)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed)
	elif topdown_mode:
		_handle_topdown_movement()
	else:
		_handle_fps_movement()

	move_and_slide()
	_update_crosshair()
	_update_animations(was_on_floor)

# ================================================================
# ANIMATION
# ================================================================
func _update_animations(was_on_floor: bool) -> void:
	if not is_instance_valid(_anim_tree):
		return

	# Project world velocity onto the player's local axes.
	# local_vel.z > 0  →  moving backward  (blend_y > 0 → "walk backwards" in tree)
	# local_vel.z < 0  →  moving forward   (blend_y < 0 → "walk forward"   in tree)
	# local_vel.x > 0  →  strafing right   (blend_x > 0)
	# local_vel.x < 0  →  strafing left    (blend_x < 0)
	var flat_vel  := Vector3(velocity.x, 0.0, velocity.z)
	var local_vel := global_transform.basis.inverse() * flat_vel
	var max_speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed

	var blend_x := clampf(local_vel.x / max_speed, -1.0, 1.0)
	var blend_y := clampf(local_vel.z / max_speed, -1.0, 1.0)   # +Z local = backward

	_anim_tree.set(ANIM_LOCOMOTION, Vector2(blend_x, blend_y))

	# Fire jump animation on the frame we leave the ground going upward.
	if was_on_floor and not is_on_floor() and velocity.y > 0.0:
		_anim_tree.set(ANIM_JUMP, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


# Call this from WeaponManager (or wherever) when a shot is fired.
func play_shoot_anim() -> void:
	if is_instance_valid(_anim_tree):
		_anim_tree.set(ANIM_SHOOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

# ================================================================
# FPS MOVEMENT
# In Godot, the camera looks down -Z (forward). basis.z points BEHIND
# the player, so:
#   forward  → dir -= basis.z
#   backward → dir += basis.z
#   left     → dir -= basis.x
#   right    → dir += basis.x
# ================================================================
func _handle_fps_movement() -> void:
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var basis := global_transform.basis
	var dir   := Vector3.ZERO

	if Input.is_action_pressed("move_forward"):  dir += basis.z
	if Input.is_action_pressed("move_backward"): dir -= basis.z
	if Input.is_action_pressed("move_left"):     dir += basis.x
	if Input.is_action_pressed("move_right"):    dir -= basis.x

	dir.y = 0.0
	if dir.length_squared() > 0.0:
		dir = dir.normalized()

	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

# ================================================================
# TOP-DOWN MOVEMENT
# ================================================================
func _handle_topdown_movement() -> void:
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var dir   := Vector3.ZERO

	if Input.is_key_pressed(KEY_W): dir.z -= 1.0
	if Input.is_key_pressed(KEY_S): dir.z += 1.0
	if Input.is_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): dir.x += 1.0

	if dir.length_squared() > 0.0:
		dir = dir.normalized()

	velocity.x = dir.x * speed
	velocity.z = dir.z * speed


# Called externally by a top-down controller.
func topdown_move(dir: Vector3, _delta: float) -> void:
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	if dir.length_squared() > 0.0:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

# ================================================================
# TOP-DOWN AIM / FIRE
# ================================================================
func set_aim_direction(dir: Vector3) -> void:
	aim_direction = dir
	_face_direction(dir)


func topdown_fire(dir: Vector3) -> void:
	aim_direction = dir
	_face_direction(dir)
	if is_instance_valid(weapon_manager):
		weapon_manager.try_shoot()


func _face_direction(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.01:
		return
	look_at(global_position + flat.normalized(), Vector3.UP)

# ================================================================
# GRAVITY
# ================================================================
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

# ================================================================
# MOUSE LOOK
# ================================================================
func _apply_mouse_look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	_pitch = clamp(
		_pitch + relative.y * mouse_sensitivity,
		deg_to_rad(-89.0),
		deg_to_rad(89.0)
	)
	head.rotation.x = _pitch

# ================================================================
# CROSSHAIR
# ================================================================
func _update_crosshair() -> void:
	if not is_instance_valid(crosshair):
		return
	var vp_size       := get_viewport().get_visible_rect().size
	crosshair.position = (vp_size - crosshair.size) / 2.0
	crosshair.visible  = not topdown_mode and not _is_shop_panel_open()

# ================================================================
# SHOP HELPERS
# ================================================================
func _get_shop() -> Node:
	return get_tree().get_first_node_in_group("shop")


func _is_shop_panel_open() -> bool:
	var shop := _get_shop()
	if not is_instance_valid(shop): return false
	if shop.has_method("is_panel_open"): return shop.is_panel_open()
	return false

# ================================================================
# COMBAT
# ================================================================
func take_damage(amount: float, instigator: Node = null) -> void:
	if _is_dead: return
	health = max(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die(instigator)


func _die(_instigator: Node = null) -> void:
	if _is_dead: return
	_is_dead     = true
	ui_opened    = false
	topdown_mode = false
	velocity     = Vector3.ZERO

	if is_instance_valid(_anim_tree):
		_anim_tree.set(ANIM_DEATH, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

	_award_gold_to_enemy()
	await get_tree().create_timer(3.0).timeout
	_respawn()


func _award_gold_to_enemy() -> void:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if not is_instance_valid(gm) or not gm.has_method("add_gold"): return
	var enemy_team := 2 if team_id == 1 else 1
	gm.add_gold(enemy_team, gold_on_death)


func _respawn() -> void:
	_is_dead     = false
	topdown_mode = false
	max_health   = 100.0 + _upgrade_bonuses["max_health"]
	health       = max_health
	walk_speed   = BASE_WALK_SPEED   * (1.0 + _upgrade_bonuses["move_speed"])
	sprint_speed = BASE_SPRINT_SPEED * (1.0 + _upgrade_bonuses["move_speed"])
	health_changed.emit(health, max_health)

	for b in get_tree().get_nodes_in_group("bases"):
		if "team_id" in b and b.team_id == team_id:
			global_position = b.global_position + Vector3(0, 1.5, 0)
			break

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# ================================================================
# UPGRADES
# ================================================================
func apply_upgrade(stat: String, amount: float) -> void:
	match stat:
		"max_health":
			_upgrade_bonuses["max_health"] += amount
			max_health += amount
			health      = min(health + amount, max_health)
			health_changed.emit(health, max_health)
		"move_speed":
			_upgrade_bonuses["move_speed"] += amount
			walk_speed   = BASE_WALK_SPEED   * (1.0 + _upgrade_bonuses["move_speed"])
			sprint_speed = BASE_SPRINT_SPEED * (1.0 + _upgrade_bonuses["move_speed"])
		"fire_rate":
			_upgrade_bonuses["fire_rate"] += amount
		"damage":
			_upgrade_bonuses["damage"] += amount
