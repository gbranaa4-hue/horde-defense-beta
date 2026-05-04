extends Node3D

@export var area_size := 200.0

@export var tree_count := 4000
@export var grass_count := 40000
@export var rock_count := 1200

@export var ground_mask := 1
@export var collision_distance := 25.0

# 🏠 base protection
@export var base_position : Vector3 = Vector3.ZERO
@export var base_radius : float = 25.0

var noise := FastNoiseLite.new()
var biome_noise := FastNoiseLite.new()
var player : Node3D


func _ready():
	randomize()
	setup_noise()
	player = get_viewport().get_camera_3d()
	generate_world()


# =========================
# NOISE
# =========================
func setup_noise():
	noise.seed = randi()
	noise.frequency = 0.035
	noise.fractal_octaves = 3

	biome_noise.seed = randi()
	biome_noise.frequency = 0.01


# =========================
# WORLD
# =========================
func generate_world():
	create_trees()
	create_grass()
	create_rocks()


# =========================
# GROUND
# =========================
func get_ground_y(x, z):
	var space = get_world_3d().direct_space_state

	var query = PhysicsRayQueryParameters3D.create(
		Vector3(x, 200, z),
		Vector3(x, -200, z)
	)
	query.collision_mask = ground_mask

	var result = space.intersect_ray(query)
	return result.position.y if result else 0.0


# =========================
# TREE MESH (PINE)
# =========================
func create_tree_mesh():
	var mesh := ArrayMesh.new()

	# trunk
	var trunk := CylinderMesh.new()
	trunk.height = 6.0
	trunk.top_radius = 0.2
	trunk.bottom_radius = 0.4

	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		trunk.surface_get_arrays(0)
	)

	# leaves (cone via cylinder)
	var cone := CylinderMesh.new()
	cone.height = 5.0
	cone.bottom_radius = 2.0
	cone.top_radius = 0.0

	var arr = cone.surface_get_arrays(0)
	var verts = arr[Mesh.ARRAY_VERTEX]

	for i in verts.size():
		verts[i].y += 5.0

	arr[Mesh.ARRAY_VERTEX] = verts

	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arr
	)

	return mesh


# =========================
# TREES
# =========================
func create_trees():
	# ======================
	# TRUNK MULTIMESH
	# ======================
	var trunk_mm_i = MultiMeshInstance3D.new()
	add_child(trunk_mm_i)

	var trunk_mm = MultiMesh.new()
	trunk_mm.transform_format = MultiMesh.TRANSFORM_3D
	trunk_mm.instance_count = tree_count

	var trunk_mesh = CylinderMesh.new()
	trunk_mesh.height = 6.0
	trunk_mesh.top_radius = 0.2
	trunk_mesh.bottom_radius = 0.4

	trunk_mm.mesh = trunk_mesh
	trunk_mm_i.multimesh = trunk_mm

	var trunk_mat = StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.22, 0.1)
	trunk_mm_i.material_override = trunk_mat


	# ======================
	# LEAF MULTIMESH
	# ======================
	var leaf_mm_i = MultiMeshInstance3D.new()
	add_child(leaf_mm_i)

	var leaf_mm = MultiMesh.new()
	leaf_mm.transform_format = MultiMesh.TRANSFORM_3D
	leaf_mm.instance_count = tree_count

	var cone = CylinderMesh.new()
	cone.height = 5.0
	cone.bottom_radius = 2.0
	cone.top_radius = 0.0

	leaf_mm.mesh = cone
	leaf_mm_i.multimesh = leaf_mm

	var leaf_mat = StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.1, 0.4, 0.1)
	leaf_mm_i.material_override = leaf_mat


	# ======================
	# SPAWN LOOP
	# ======================
	for i in tree_count:
		var x = randf_range(-area_size, area_size)
		var z = randf_range(-area_size, area_size)

		# 🏠 base exclusion
		if Vector2(x, z).distance_to(Vector2(base_position.x, base_position.z)) < base_radius:
			continue

		if biome_noise.get_noise_2d(x, z) < -0.3:
			continue
		if noise.get_noise_2d(x, z) < -0.1:
			continue

		var y = get_ground_y(x, z)
		var pos = Vector3(x, y, z)

		var rot = randf() * TAU
		var scale = randf_range(1.0, 2.5)

		# TRUNK TRANSFORM
		var t_trunk = Transform3D()
		t_trunk.origin = pos
		t_trunk.basis = Basis().rotated(Vector3.UP, rot)
		t_trunk.basis = t_trunk.basis.scaled(Vector3.ONE * scale)

		trunk_mm.set_instance_transform(i, t_trunk)

		# LEAVES TRANSFORM (offset upward)
		var t_leaf = t_trunk
		t_leaf.origin.y += 5.0 * scale

		leaf_mm.set_instance_transform(i, t_leaf)

		# 🚧 collision near player
		if player and player.global_position.distance_to(pos) < collision_distance:
			spawn_tree_collision(pos)


func spawn_tree_collision(pos):
	var body = StaticBody3D.new()
	var shape = CollisionShape3D.new()

	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.6
	capsule.height = 6.0

	shape.shape = capsule
	body.add_child(shape)

	body.position = pos
	add_child(body)


# =========================
# GRASS
# =========================
func create_grass():
	var mm_i = MultiMeshInstance3D.new()
	add_child(mm_i)

	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = grass_count

	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.5, 1.0)

	mm.mesh = mesh
	mm_i.multimesh = mm
	mm_i.material_override = grass_shader()

	for i in grass_count:
		var x = randf_range(-area_size, area_size)
		var z = randf_range(-area_size, area_size)

		if Vector2(x, z).distance_to(Vector2(base_position.x, base_position.z)) < base_radius:
			continue

		if biome_noise.get_noise_2d(x, z) < 0.0:
			continue
		if noise.get_noise_2d(x * 2.0, z * 2.0) < -0.2:
			continue

		var y = get_ground_y(x, z)

		var t = Transform3D()
		t.origin = Vector3(x, y, z)
		t.basis = Basis().rotated(Vector3.UP, randf() * TAU)
		t.basis = t.basis.scaled(Vector3.ONE * randf_range(0.7, 1.8))

		mm.set_instance_transform(i, t)


func grass_shader():
	var s = Shader.new()
	s.code = """
	shader_type spatial;

	uniform float wind_strength = 0.3;
	uniform float wind_speed = 3.0;

	void vertex() {
		float wave = sin(TIME * wind_speed + VERTEX.x * 5.0) * wind_strength;
		VERTEX.x += wave * UV.y;
	}

	void fragment() {
		ALBEDO = vec3(0.2, 0.7, 0.2);
	}
	"""
	var m = ShaderMaterial.new()
	m.shader = s
	return m


# =========================
# ROCKS
# =========================
func create_rocks():
	var mm_i = MultiMeshInstance3D.new()
	add_child(mm_i)

	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = rock_count

	var mesh = SphereMesh.new()
	mesh.radius = 1.0

	mm.mesh = mesh
	mm_i.multimesh = mm

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.4, 0.4)
	mm_i.material_override = mat

	for i in rock_count:
		var x = randf_range(-area_size, area_size)
		var z = randf_range(-area_size, area_size)

		if Vector2(x, z).distance_to(Vector2(base_position.x, base_position.z)) < base_radius:
			continue

		if biome_noise.get_noise_2d(x, z) > 0.4:
			continue

		var y = get_ground_y(x, z)
		var pos = Vector3(x, y, z)

		var t = Transform3D()
		t.origin = pos
		t.basis = Basis().rotated(Vector3.UP, randf() * TAU)
		t.basis = t.basis.scaled(Vector3.ONE * randf_range(0.8, 2.5))

		mm.set_instance_transform(i, t)

		# 🚧 rock collision near player
		if player and player.global_position.distance_to(pos) < collision_distance:
			spawn_rock_collision(pos)


func spawn_rock_collision(pos):
	var body = StaticBody3D.new()
	var shape = CollisionShape3D.new()

	var sphere = SphereShape3D.new()
	sphere.radius = 1.2

	shape.shape = sphere
	body.add_child(shape)

	body.position = pos
	add_child(body)
