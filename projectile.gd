extends Node3D

# ===============================
# PROJECTILE STATS
# ===============================
@export var speed: float = 25.0
@export var damage: float = 15.0
@export var lifetime: float = 3.0
@export var hit_radius: float = 0.4

# ===============================
# TEAM SYSTEM
# ===============================
var team_id: int = 1

# ===============================
# STATE
# ===============================
var direction: Vector3 = Vector3.ZERO
var time_alive: float = 0.0

# ===============================
func _ready():
	# Simple visible projectile for debugging
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	mesh_instance.mesh = sphere
	add_child(mesh_instance)

# ===============================
func _physics_process(delta: float):
	if direction == Vector3.ZERO:
		return

	time_alive += delta
	if time_alive >= lifetime:
		queue_free()
		return

	global_position += direction.normalized() * speed * delta
	_check_hit()

# ===============================
func _check_hit():
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = hit_radius

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = 0xFFFFFFFF

	var results := space.intersect_shape(query)

	for r in results:
		var body: Object = r.get("collider")
		if not is_instance_valid(body):
			continue

		var target := _find_damage_target(body)
		if target == null:
			continue

		# 🔒 FRIENDLY FIRE CHECK
		if is_friendly(target):
			print("🚫 Projectile avoided teammate:", target.name)
			continue

		if target.has_method("take_damage"):
			target.take_damage(damage, self)
			print("💥 Projectile hit:", target.name)
			queue_free()
			return

# ===============================
func _find_damage_target(body: Object) -> Node:
	if body == null:
		return null
	if body.has_method("take_damage"):
		return body
	if body.get_parent() and body.get_parent().has_method("take_damage"):
		return body.get_parent()
	return null

# ===============================
func is_friendly(target: Node) -> bool:
	if not is_instance_valid(target):
		return false
	if not ("team_id" in target):
		return false
	return target.team_id == team_id
