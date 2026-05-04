# ============================================================
# base_gun.gd
# Hitscan weapon base class
# - shoot() no longer blocked on MOUSE_MODE_CAPTURED (WeaponManager
#   already gates FPS clicks; double-gating caused drop-frame misses)
# - ADS: right-click zooms FOV in; release restores it
# - Excludes player from raycast
# - Team check before applying damage
# ============================================================
extends Node3D
class_name BaseGun

# ===============================
# EXPORTS
# ===============================
@export var max_ammo      : int   = 30
@export var fire_rate     : float = 0.2
@export var reload_time   : float = 2.0
@export var damage        : float = 10.0

## FOV when aiming down sights (degrees). 0 = disable ADS zoom.
@export var ads_fov       : float = 50.0
## How quickly the FOV lerps in/out (higher = snappier).
@export var ads_fov_speed : float = 10.0

# ===============================
# STATE
# ===============================
var current_ammo  : int      = 0
var can_shoot     : bool     = true
var reloading     : bool     = false
var camera        : Camera3D = null
var player        : Node     = null

var _is_aiming    : bool     = false
var _default_fov  : float    = 75.0   # saved on equip

# ===============================
# SIGNALS
# ===============================
signal ammo_changed(current: int, maximum: int)

# ===============================
# READY
# ===============================
func _ready() -> void:
	current_ammo = max_ammo

# ===============================
# EQUIP / UNEQUIP
# ===============================
func equip(cam: Camera3D, ply: Node) -> void:
	camera       = cam
	player       = ply
	can_shoot    = true
	reloading    = false
	_is_aiming   = false
	if is_instance_valid(camera):
		_default_fov = camera.fov
	ammo_changed.emit(current_ammo, max_ammo)

func unequip() -> void:
	# Restore FOV before holstering
	if is_instance_valid(camera) and _is_aiming:
		camera.fov = _default_fov
	_is_aiming = false
	camera = null
	player = null

# ===============================
# ADS INPUT
# ===============================
func _input(event: InputEvent) -> void:
	# ADS only works in FPS (captured) mode
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if not is_instance_valid(camera) or ads_fov <= 0.0:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_is_aiming = event.pressed
			get_viewport().set_input_as_handled()

# ===============================
# PROCESS — smooth FOV lerp
# ===============================
func _process(delta: float) -> void:
	if not is_instance_valid(camera) or ads_fov <= 0.0:
		return
	var target_fov : float = ads_fov if _is_aiming else _default_fov
	camera.fov = lerpf(camera.fov, target_fov, clampf(ads_fov_speed * delta, 0.0, 1.0))

# ===============================
# SHOOT
# ===============================
func shoot() -> void:
	# NOTE: Mouse-mode check removed — WeaponManager already gates FPS
	# clicks on MOUSE_MODE_CAPTURED. Double-gating dropped shots on
	# fast double-clicks because the mode query could flicker.
	if not can_shoot or reloading:
		return
	if not is_instance_valid(camera):
		push_warning("[BaseGun] shoot() called but no camera assigned.")
		return

	if current_ammo <= 0:
		start_reload()
		return

	can_shoot     = false
	current_ammo -= 1
	ammo_changed.emit(current_ammo, max_ammo)

	_fire_projectile()

	await get_tree().create_timer(fire_rate).timeout
	can_shoot = true

	if current_ammo <= 0 and not reloading:
		start_reload()

# ===============================
# HITSCAN RAY
# ===============================
func _fire_projectile() -> void:
	if not is_instance_valid(camera):
		return

	var space_state := camera.get_world_3d().direct_space_state
	var from        := camera.global_position
	var dir         := -camera.global_transform.basis.z
	var to          := from + dir * 2000.0

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	query.collide_with_areas  = true

	var excludes : Array[RID] = []
	if is_instance_valid(player) and player.has_method("get_rid"):
		excludes.append(player.get_rid())
	query.exclude = excludes

	var result := space_state.intersect_ray(query)
	if result:
		print("[BaseGun] Hit: ", result.collider.name)
		apply_damage(result.collider, damage)
	else:
		print("[BaseGun] Ray missed.")

# ===============================
# DAMAGE
# ===============================
func apply_damage(hit: Node, dmg: float) -> void:
	if not is_instance_valid(hit):
		return
	var target := _resolve_target(hit)
	if target == null:
		return
	if _is_friendly(target):
		return
	target.take_damage(dmg, player)

func _resolve_target(node: Node) -> Node:
	var current := node
	while is_instance_valid(current):
		if current.has_method("take_damage"):
			return current
		current = current.get_parent()
	return null

# ===============================
# RELOAD
# ===============================
func reload() -> void:
	start_reload()

func start_reload() -> void:
	if reloading or current_ammo >= max_ammo:
		return
	reloading = true
	ammo_changed.emit(current_ammo, max_ammo)
	await get_tree().create_timer(reload_time).timeout
	current_ammo = max_ammo
	reloading    = false
	ammo_changed.emit(current_ammo, max_ammo)

# ===============================
# TEAM CHECK
# ===============================
func _is_friendly(target: Node) -> bool:
	if not is_instance_valid(player) or not is_instance_valid(target):
		return false
	if not ("team_id" in target) or not ("team_id" in player):
		return false
	return target.team_id == player.team_id
