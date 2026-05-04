extends Node3D
class_name FireTurret

# ===============================
# STATS
# ===============================
@export var range: float = 13.0          # slightly shorter (fire = close range)
@export var fire_rate: float = 0.25      # faster firing
@export var base_damage: float = 6.0     # lower per hit (DOT style)
@export var projectile_scene: PackedScene
@export var team_id: int = 1

# Optional: fire flavor
@export var spread: float = 0.08         # small random spray
@export var burst_count: int = 2         # shoots multiple flames

var damage: float = 0.0
var level: int = 1
var max_level: int = 5
var target: Node3D = null
var fire_timer: float = 0.0


# ===============================
# COST
# ===============================
func get_upgrade_cost() -> int:
	return int(25 * level) # slightly more expensive than normal turret

func get_cost() -> int:
	return get_upgrade_cost()


# ===============================
# REFERENCES
# ===============================
@onready var muzzle: Node3D = $Muzzle


# ===============================
# SIGNALS
# ===============================
signal turret_selected(turret)
signal turret_upgraded(turret)


# ===============================
# READY
# ===============================
func _ready() -> void:
	add_to_group("turrets")
	add_to_group("towers")

	damage = base_damage
	fire_timer = 0.0


# ===============================
# PROCESS
# ===============================
func _process(delta: float) -> void:
	fire_timer -= delta

	_find_target()

	if is_instance_valid(target):
		_face_target()

		if fire_timer <= 0.0:
			_shoot()
			fire_timer = fire_rate


# ===============================
# TARGETING (same as yours)
# ===============================
func _find_target() -> void:
	var closest_enemy: Node3D = null
	var closest_dist: float = range

	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue

		if u == self:
			continue

		if u.is_in_group("bases"):
			continue

		if u.is_in_group("towers"):
			continue

		if not ("team_id" in u):
			continue

		if u.team_id == team_id:
			continue

		var d: float = global_position.distance_to(u.global_position)

		if d < closest_dist:
			closest_dist = d
			closest_enemy = u

	target = closest_enemy


# ===============================
# SHOOTING (FIRE VERSION)
# ===============================
func _shoot() -> void:
	if projectile_scene == null:
		return
	if not is_instance_valid(target):
		return

	for i in burst_count:
		var p: Node3D = projectile_scene.instantiate()
		get_tree().current_scene.add_child(p)

		p.global_position = muzzle.global_position

		var dir: Vector3 = (target.global_position - muzzle.global_position).normalized()

		# 🔥 add spread for flame effect
		dir.x += randf_range(-spread, spread)
		dir.y += randf_range(-spread * 0.5, spread * 0.5)
		dir.z += randf_range(-spread, spread)
		dir = dir.normalized()

		p.direction = dir
		p.damage = damage
		p.team_id = team_id


# ===============================
# AIMING
# ===============================
func _face_target() -> void:
	if not is_instance_valid(target):
		return

	var look_pos: Vector3 = target.global_position
	look_pos.y = global_position.y
	look_at(look_pos, Vector3.UP)


# ===============================
# UPGRADE SYSTEM (fire scaling)
# ===============================
func upgrade() -> void:
	if level >= max_level:
		push_warning("Fire turret max level")
		return

	level += 1

	damage += 2.0                # smaller per level
	fire_rate = max(0.1, fire_rate * 0.92)  # faster over time
	range += 0.5                # slight range growth

	emit_signal("turret_upgraded", self)


# ===============================
# UI INTERACTION
# ===============================
func interact() -> void:
	emit_signal("turret_selected", self)
