extends Node3D

# ===============================
# EXPORTS
# ===============================
@export var damage: float = 20.0
@export var fire_rate: float = 0.2
@export var max_ammo: int = 30
@export var reload_time: float = 1.5
@export var range: float = 100.0

# ===============================
# STATE
# ===============================
var ammo: int = 0
var can_shoot: bool = true
var is_reloading: bool = false
var camera: Camera3D = null
var player: Node = null
var _time_since_last_shot: float = 0.0

# ===============================
# SIGNALS
# ===============================
signal ammo_changed(current: int, maximum: int)

# ===============================
# READY
# ===============================
func _ready() -> void:
	ammo = max_ammo
	set_process(false)
	print("[Gun] ready:", name, " | ammo:", ammo)

# ===============================
# EQUIP / UNEQUIP
# ===============================
func equip(cam: Camera3D, p: Node = null) -> void:
	camera = cam
	player = p
	ammo = max_ammo
	can_shoot = true
	is_reloading = false
	_time_since_last_shot = 0.0
	ammo_changed.emit(ammo, max_ammo)
	set_process(true)
	print("[Gun] equipped:", name)

func unequip() -> void:
	camera = null
	is_reloading = false
	set_process(false)
	print("[Gun] unequipped:", name)

# ===============================
# PROCESS — fire rate cooldown
# ===============================
func _process(delta: float) -> void:
	if not can_shoot and not is_reloading:
		_time_since_last_shot += delta
		if _time_since_last_shot >= fire_rate:
			can_shoot = true

# ===============================
# SHOOT — raycast hitscan
# ===============================
func shoot() -> void:
	if is_reloading:
		print("[Gun] reloading, can't shoot")
		return
	if not can_shoot:
		print("[Gun] on cooldown")
		return
	if ammo <= 0:
		print("[Gun] out of ammo — auto reloading")
		reload()
		return
	if not camera:
		push_warning("[Gun] no camera assigned — call equip() first")
		return

	ammo -= 1
	can_shoot = false
	_time_since_last_shot = 0.0
	ammo_changed.emit(ammo, max_ammo)
	print("[Gun] shot fired | ammo left:", ammo)

	_do_raycast()

func _do_raycast() -> void:
	var space := get_world_3d().direct_space_state
	if not space:
		push_warning("[Gun] no physics space found")
		return

	# Shoot from center of camera view
	var origin: Vector3 = camera.global_position
	var aim_dir: Vector3 = -camera.global_transform.basis.z
	var end: Vector3 = origin + aim_dir * range

	var query := PhysicsRayQueryParameters3D.create(origin, end)
	# Exclude the player's own body from the raycast
	if player and player is CollisionObject3D:
		query.exclude = [player.get_rid()]

	var result: Dictionary = space.intersect_ray(query)

	if result.is_empty():
		print("[Gun] raycast hit nothing")
		return

	var hit: Node = result["collider"]
	print("[Gun] raycast hit:", hit.name)

	# Walk up tree in case we hit a child node (CollisionShape, MeshInstance etc.)
	var target: Node = hit
	while is_instance_valid(target) and not target.has_method("take_damage"):
		target = target.get_parent()

	if is_instance_valid(target) and target.has_method("take_damage"):
		print("[Gun] dealing", damage, "damage to:", target.name)
		target.take_damage(damage, player)
	else:
		print("[Gun] hit", hit.name, "but it has no take_damage method")

# ===============================
# RELOAD
# ===============================
func reload() -> void:
	if is_reloading or ammo == max_ammo:
		return
	is_reloading = true
	can_shoot = false
	print("[Gun] reloading:", name)
	await get_tree().create_timer(reload_time).timeout
	ammo = max_ammo
	is_reloading = false
	can_shoot = true
	ammo_changed.emit(ammo, max_ammo)
	print("[Gun] reload complete:", name)
