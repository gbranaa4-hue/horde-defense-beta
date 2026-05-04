extends Node3D
class_name IceProjectile

# ===============================
# CONFIG
# ===============================
@export var speed: float = 18.0
@export var damage: float = 4.0
@export var lifetime: float = 3.0
@export var freeze_duration: float = 1.5
@export var team_id: int = 1

var direction: Vector3 = Vector3.ZERO
var _timer: float = 0.0

# ===============================
# NODES
# ===============================
var mesh_instance: MeshInstance3D
var trail: GPUParticles3D

# ===============================
# READY
# ===============================
func _ready() -> void:
	_build_ice_shard()
	_build_trail()

# ===============================
# PROCESS
# ===============================
func _process(delta: float) -> void:
	_timer += delta
	if _timer >= lifetime:
		queue_free()
		return

	translate(direction * speed * delta)

	var hit = _check_hit()
	if hit:
		_on_hit(hit)

# ===============================
# ICE SHARD VISUAL
# ===============================
func _build_ice_shard() -> void:
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)

	# 🔷 Create crystal-like shape
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.12
	mesh.height = 0.6
	mesh.radial_segments = 6
	mesh_instance.mesh = mesh

	# ❄️ Ice material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.9, 1.0, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.1
	mat.roughness = 0.05
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.8, 1.0)
	mat.emission_energy = 0.6

	mesh_instance.material_override = mat

	# Point forward
	mesh_instance.rotation_degrees.x = 90

# ===============================
# TRAIL (frost particles)
# ===============================
func _build_trail() -> void:
	trail = GPUParticles3D.new()
	add_child(trail)

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, -1)
	mat.spread = 20.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.5
	mat.scale_min = 0.05
	mat.scale_max = 0.15
	mat.lifetime = 0.4

	mat.color = Color(0.7, 0.9, 1.0, 0.7)

	trail.process_material = mat
	trail.amount = 20
	trail.lifetime = 0.4
	trail.emitting = true

# ===============================
# HIT DETECTION
# ===============================
func _check_hit():
	var space = get_world_3d().direct_space_state

	var result = space.intersect_ray(
		PhysicsRayQueryParameters3D.create(
			global_position,
			global_position + direction * 0.6
		)
	)

	if result and result.has("collider"):
		return result.collider

	return null

# ===============================
# ON HIT
# ===============================
func _on_hit(target: Node) -> void:
	# Damage
	if target.has_method("take_damage"):
		target.take_damage(damage, self)

	# ❄️ Freeze effect
	if target.has_method("apply_freeze"):
		target.apply_freeze(freeze_duration)

	_spawn_ice_burst()
	queue_free()

# ===============================
# IMPACT EFFECT
# ===============================
func _spawn_ice_burst() -> void:
	var burst := GPUParticles3D.new()
	get_tree().current_scene.add_child(burst)

	burst.global_position = global_position

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 180
	mat.initial_velocity_min = 2
	mat.initial_velocity_max = 6
	mat.scale_min = 0.1
	mat.scale_max = 0.25
	mat.lifetime = 0.5
	mat.color = Color(0.7, 0.9, 1.0)

	burst.process_material = mat
	burst.amount = 30
	burst.one_shot = true
	burst.emitting = true

	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(burst):
		burst.queue_free()
