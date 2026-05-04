extends Node3D
# ===============================
# STATS
# ===============================
@export var range: float = 15.0
@export var fire_rate: float = 0.6
@export var base_damage: float = 15.0
@export var projectile_scene: PackedScene
@export var team_id: int = 1

var damage: float = 0.0
var level: int = 1
var max_level: int = 5
var target: Node3D = null
var fire_timer: float = 0.0


# ===============================
# EXPOSED UI PROPERTY (FIXED)
# ===============================
func get_upgrade_cost() -> int:
	return int(20 * level)


# IMPORTANT: explicit typed getter wrapper (fixes inference issues)
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
# TARGETING
# ===============================
func _find_target() -> void:
	var closest_enemy: Node3D = null
	var closest_dist: float = range

	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u):
			continue

		if u == self:
			continue

		# ❌ NEVER target bases
		if u.is_in_group("bases"):
			continue

		# ❌ NEVER target turrets
		if u.is_in_group("towers"):
			continue

		# ✅ MUST have team_id or skip
		if not ("team_id" in u):
			continue

		var u_team: int = u.team_id

		# ✅ same team = ignore
		if u_team == team_id:
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

	var p = projectile_scene.instantiate()
	get_tree().current_scene.add_child(p)

	p.global_position = muzzle.global_position
	p.direction = (target.global_position - muzzle.global_position).normalized()
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
# UPGRADE SYSTEM
# ===============================
func upgrade() -> void:
	if level >= max_level:
		push_warning("Turret already max level")
		return

	level += 1
	damage += 5.0
	fire_rate = max(0.15, fire_rate * 0.9)

	emit_signal("turret_upgraded", self)


# ===============================
# UI INTERACTION
# ===============================
func interact() -> void:
	emit_signal("turret_selected", self)
