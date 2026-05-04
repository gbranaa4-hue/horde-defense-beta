extends Node3D
class_name IceTurret

# ===============================
# STATS
# ===============================
@export var range: float = 14.0
@export var fire_rate: float = 0.7
@export var base_damage: float = 8.0
@export var projectile_scene: PackedScene
@export var team_id: int = 1

# ❄ Freeze effect
@export var slow_amount: float = 0.4     # 40% slow
@export var slow_duration: float = 1.5   # seconds
@export var freeze_chance: float = 0.15  # 15% full freeze

var damage: float = 0.0
var level: int = 1
var max_level: int = 5
var target: Node3D = null
var fire_timer: float = 0.0


# ===============================
# COST
# ===============================
func get_upgrade_cost() -> int:
	return int(30 * level)

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
# TARGETING (same logic)
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
# SHOOTING
# ===============================
func _shoot() -> void:
	if projectile_scene == null:
		return
	if not is_instance_valid(target):
		return

	var p: Node3D = projectile_scene.instantiate()
	get_tree().current_scene.add_child(p)

	p.global_position = muzzle.global_position

	var dir: Vector3 = (target.global_position - muzzle.global_position).normalized()

	p.direction = dir
	p.damage = damage
	p.team_id = team_id

	# ❄ PASS FREEZE DATA TO PROJECTILE
	p.slow_amount = slow_amount
	p.slow_duration = slow_duration
	p.freeze = randf() < freeze_chance


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
# UPGRADE SYSTEM
# ===============================
func upgrade() -> void:
	if level >= max_level:
		push_warning("Ice turret max level")
		return

	level += 1

	damage += 2.0
	slow_amount = min(0.75, slow_amount + 0.05)
	slow_duration += 0.2
	fire_rate = max(0.3, fire_rate * 0.95)

	emit_signal("turret_upgraded", self)


# ===============================
# UI
# ===============================
func interact() -> void:
	emit_signal("turret_selected", self)
