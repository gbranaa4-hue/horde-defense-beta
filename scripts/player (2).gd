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

var _upgrade_bonuses : Dictionary = {
	"max_health" : 0.0,
	"move_speed" : 0.0,
	"fire_rate"  : 0.0,
	"damage"     : 0.0,
}

const BASE_WALK_SPEED   : float = 5.0
const BASE_SPRINT_SPEED : float = 9.0

# ===============================
# UI STATE
# ===============================
var ui_opened    : bool    = false
var topdown_mode : bool    = false
var aim_direction: Vector3 = Vector3(0, 0, -1)

# ===============================
# SIGNALS
# ===============================
signal health_changed(current: float, maximum: float)

# ===============================
# NODES
# ===============================
@onready var head           : Node3D        = $Head
@onready var camera         : Camera3D      = $Head/Camera3D
@onready var crosshair      : Control       = $CanvasLayer/Crosshair
@onready var weapon_manager : WeaponManager = $WeaponManager

# ===============================
# INTERNAL
# ===============================
var _pitch   : float = 0.0
var _is_dead : bool  = false

# ===============================
# READY
# ===============================
func _ready() -> void:
	add_to_group("players")
	add_to_group("units")
	owner_id = get_instance_id()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	health_changed.emit(health, max_health)

# ===============================
# INPUT
# ===============================
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
			_toggle_shop()
		KEY_1:
			_command_creeps(0)
		KEY_2:
			_command_creeps(1)
		KEY_3:
			_command_creeps(2)
		KEY_4:
			_command_creeps(3)

# ===============================
# CREEP COMMANDS
# ===============================
func _command_creeps(mode_index: int) -> void:
	var shop := _get_shop()
	if not is_instance_valid(shop): return
	if shop.has_method("command_owned_units"):
		shop.command_owned_units(mode_index)

# ===============================
# PHYSICS
# ===============================
func _physics_process(delta: float) -> void:
	if _is_dead:
		return

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

# ===============================
# FPS MOVEMENT
# ===============================
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

# ===============================
# TOP-DOWN MOVEMENT
# ===============================
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

# ===============================
# TOPDOWN AIM / FIRE
# ===============================
func set_aim_direction(dir: Vector3) -> void:
	aim_direction = dir
	_face_direction(dir)

func topdown_fire(dir: Vector3) -> void:
	aim_direction = dir
	_face_direction(dir)
	if is_instance_valid(weapon_manager):
		weapon_manager.try_shoot()

## Rotate so the player's -Z faces `dir`.
## look_at(pos + dir) makes -Z point toward (pos + dir), which is correct.
## Do NOT negate dir here — that was the old bug causing 180° flip.
func _face_direction(dir: Vector3) -> void:
	if dir.length_squared() < 0.01:
		return
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	if flat.length_squared() < 0.01:
		return
	look_at(global_position + flat, Vector3.UP)

# ===============================
# GRAVITY
# ===============================
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

# ===============================
# MOUSE LOOK
# ===============================
func _apply_mouse_look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	_pitch = clamp(
		_pitch + relative.y * mouse_sensitivity,
		deg_to_rad(-89.0),
		deg_to_rad(89.0)
	)
	head.rotation.x = _pitch

# ===============================
# CROSSHAIR
# ===============================
func _update_crosshair() -> void:
	if not is_instance_valid(crosshair):
		return
	var vp_size        := get_viewport().get_visible_rect().size
	crosshair.position  = (vp_size - crosshair.size) / 2.0
	# Hide FPS crosshair entirely while overhead.
	crosshair.visible   = not topdown_mode and not _is_shop_panel_open()

# ===============================
# SHOP HELPERS
# ===============================
func _toggle_shop() -> void:
	var shop := _get_shop()
	if not is_instance_valid(shop): return
	if ui_opened or _is_shop_panel_open():
		if shop.has_method("close_shop"): shop.close_shop()
	else:
		if shop.has_method("open_shop"):  shop.open_shop()

func _get_shop() -> Node:
	return get_tree().get_first_node_in_group("shop")

func _is_shop_panel_open() -> bool:
	var shop := _get_shop()
	if not is_instance_valid(shop): return false
	if shop.has_method("is_panel_open"): return shop.is_panel_open()
	return false

# ===============================
# COMBAT
# ===============================
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
	walk_speed   = BASE_WALK_SPEED   + _upgrade_bonuses["move_speed"] * BASE_WALK_SPEED
	sprint_speed = BASE_SPRINT_SPEED + _upgrade_bonuses["move_speed"] * BASE_SPRINT_SPEED

	health_changed.emit(health, max_health)

	for b in get_tree().get_nodes_in_group("bases"):
		if "team_id" in b and b.team_id == team_id:
			global_position = b.global_position + Vector3(0, 1.5, 0)
			break

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# ===============================
# UPGRADES
# ===============================
func apply_upgrade(stat: String, amount: float) -> void:
	match stat:
		"max_health":
			_upgrade_bonuses["max_health"] += amount
			max_health += amount
			health      = min(health + amount, max_health)
			health_changed.emit(health, max_health)
		"move_speed":
			_upgrade_bonuses["move_speed"] += amount
			walk_speed   *= (1.0 + amount)
			sprint_speed *= (1.0 + amount)
		"fire_rate":
			_upgrade_bonuses["fire_rate"] += amount
		"damage":
			_upgrade_bonuses["damage"] += amount
