extends Node3D

# ===============================
# CONFIG
# ===============================
@export var tree_scenes: Array[PackedScene] = []
@export var forest_size: Vector2 = Vector2(100, 100)
@export var tree_count: int = 200
@export var min_spacing: float = 3.0

@export var random_scale: bool = true
@export var scale_range: Vector2 = Vector2(0.8, 1.4)

@export var max_slope_angle: float = 35.0

# ===============================
# INTERNAL
# ===============================
var placed_positions: Array[Vector3] = []

# ===============================
# READY
# ===============================
func _ready() -> void:
	generate_forest()

# ===============================
# GENERATE
# ===============================
func generate_forest() -> void:
	if tree_scenes.is_empty():
		push_error("No tree scenes assigned!")
		return

	placed_positions.clear()

	var spawned: int = 0
	var attempts: int = 0
	var max_attempts: int = tree_count * 10

	while spawned < tree_count and attempts < max_attempts:
		attempts += 1

		var pos: Vector3
		if not _get_valid_position(pos):
			continue

		var scene: PackedScene = tree_scenes.pick_random()
		var tree: Node3D = scene.instantiate()

		add_child(tree)
		tree.global_position = pos

		# Random rotation
		tree.rotation.y = randf_range(0.0, TAU)

		# Random scale
		if random_scale:
			var s: float = randf_range(scale_range.x, scale_range.y)
			tree.scale = Vector3.ONE * s

		placed_positions.append(pos)
		spawned += 1

	print("🌲 Forest generated:", spawned, "/", tree_count)

# ===============================
# POSITION CHECK
# ===============================
func _get_valid_position(out_pos: Vector3) -> bool:
	for _i in range(20):
		var x: float = randf_range(-forest_size.x * 0.5, forest_size.x * 0.5)
		var z: float = randf_range(-forest_size.y * 0.5, forest_size.y * 0.5)

		var world_pos: Vector3 = global_position + Vector3(x, 50.0, z)

		var ground_hit := _raycast_to_ground(world_pos)
		if not ground_hit:
			continue

		var pos: Vector3 = ground_hit.position
		var normal: Vector3 = ground_hit.normal

		# ❌ Reject steep slopes
		var angle: float = rad_to_deg(acos(normal.dot(Vector3.UP)))
		if angle > max_slope_angle:
			continue

		if not _is_far_enough(pos):
			continue

		out_pos = pos
		return true

	return false

# ===============================
# RAYCAST
# ===============================
func _raycast_to_ground(from_pos: Vector3) -> Dictionary:
	var space = get_world_3d().direct_space_state

	var result: Dictionary = space.intersect_ray(
		PhysicsRayQueryParameters3D.create(
			from_pos,
			from_pos + Vector3.DOWN * 200.0
		)
	)

	return result

# ===============================
# SPACING
# ===============================
func _is_far_enough(pos: Vector3) -> bool:
	for p in placed_positions:
		if p.distance_to(pos) < min_spacing:
			return false
	return true
