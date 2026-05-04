extends Node3D
class_name LaserBolt

# ===============================
# CONFIG
# ===============================
@export var speed: float = 80.0
@export var lifetime: float = 2.0
@export var color: Color = Color(1.0, 0.2, 0.1)
@export var fly_stream: AudioStream = null
@export var impact_stream: AudioStream = null
@export var fly_volume_db: float = 0.0
@export var impact_volume_db: float = 0.0

# ===============================
# INTERNAL
# ===============================
var velocity: Vector3 = Vector3.ZERO
var shooter: Node = null
var damage: float = 25.0

var _mesh: MeshInstance3D
var _trail: GPUParticles3D
var _time: float = 0.0
var _dead: bool = false
var _fly_player: AudioStreamPlayer3D
var _impact_player: AudioStreamPlayer3D

# ===============================
# INIT
# ===============================
func init(v: Vector3, s: Node, d: float) -> void:
	velocity = v
	shooter = s
	damage = d

# ===============================
# READY
# ===============================
func _ready() -> void:
	_build_visuals()
	_build_audio()

	if is_instance_valid(_fly_player) and fly_stream:
		_fly_player.play()

	await get_tree().create_timer(lifetime).timeout
	_die(false)

# ===============================
# PHYSICS
# ===============================
func _physics_process(delta: float) -> void:
	if _dead or velocity.length_squared() < 0.01:
		return

	_time += delta

	var from := global_position
	global_position += velocity * delta

	# Subtle energy sway
	var side := velocity.cross(Vector3.UP).normalized()
	global_position += side * sin(_time * 40.0) * 0.02

	# Rotation
	var dir := velocity.normalized()
	var up := Vector3.UP
	if abs(dir.dot(up)) > 0.98:
		up = Vector3.FORWARD
	look_at(global_position + dir, up)

	_check_collision(from, global_position)

# ===============================
# HIT DETECTION
# ===============================
func _check_collision(from: Vector3, to: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)

	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		query.exclude = [shooter.get_rid()]

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return

	var collider = hit.get("collider")
	if not is_instance_valid(collider):
		return

	if _is_friendly(collider):
		return

	var target := _resolve_damageable(collider)
	if target:
		target.take_damage(damage, shooter)

	_die(true)

# ===============================
# DAMAGE RESOLUTION
# ===============================
func _resolve_damageable(node: Node) -> Node:
	var current: Node = node
	while is_instance_valid(current):
		if current.has_method("take_damage"):
			return current
		current = current.get_parent()
	return null

# ===============================
# TEAM CHECK
# ===============================
func _die(was_hit: bool) -> void:
	if _dead:
		return
	_dead = true
	set_physics_process(false)
	_trail.emitting = false
	_mesh.visible = false

	# Reparent fly player so it isn't killed with the bolt
	if is_instance_valid(_fly_player):
		var fly := _fly_player
		var fly_pos := global_position
		remove_child(fly)
		get_tree().root.add_child(fly)
		fly.global_position = fly_pos
		# Let it finish on its own, then clean up
		get_tree().create_timer(fly_stream.get_length()).timeout.connect(
			func(): if is_instance_valid(fly): fly.queue_free()
		)

	# Impact sound
	if was_hit and is_instance_valid(_impact_player) and impact_stream:
		var impact := _impact_player
		var impact_pos := global_position
		remove_child(impact)
		get_tree().root.add_child(impact)
		impact.global_position = impact_pos
		impact.play()
		get_tree().create_timer(impact_stream.get_length()).timeout.connect(
			func(): if is_instance_valid(impact): impact.queue_free()
		)

	queue_free()

# ===============================
# AUDIO
# ===============================
func _build_audio() -> void:
	_fly_player = AudioStreamPlayer3D.new()
	_fly_player.stream = fly_stream
	_fly_player.autoplay = false
	_fly_player.volume_db = fly_volume_db
	_fly_player.max_distance = 30.0
	add_child(_fly_player)

	_impact_player = AudioStreamPlayer3D.new()
	_impact_player.stream = impact_stream
	_impact_player.autoplay = false
	_impact_player.volume_db = impact_volume_db
	_impact_player.max_distance = 30.0
	add_child(_impact_player)

# ===============================
# VISUALS
# ===============================
func _build_visuals() -> void:
	_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = 0.8
	_mesh.mesh = cyl
	_mesh.rotation_degrees.x = 90

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 8.0
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.9
	_mesh.material_override = mat
	add_child(_mesh)

	_trail = GPUParticles3D.new()
	_trail.amount = 10
	_trail.lifetime = 0.1
	_trail.local_coords = false

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 3.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.2
	pm.scale_min = 0.02
	pm.scale_max = 0.05
	pm.color = color

	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	pm.color_ramp = grad_tex

	_trail.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.25)
	_trail.draw_pass_1 = quad
	_trail.emitting = true
	add_child(_trail) 
func _is_friendly(collider: Node) -> bool:
	if not is_instance_valid(shooter):
		return false
	var shooter_team: int = shooter.get("team_id") if shooter.get("team_id") != null else -1
	var target_team: int = collider.get("team_id") if collider.get("team_id") != null else -1
	if shooter_team == -1 or target_team == -1:
		return false
	return shooter_team == target_team
