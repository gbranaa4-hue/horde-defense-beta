extends Area3D
class_name FlameProjectile

# ===============================
# CONFIG
# ===============================
@export var velocity: Vector3 = Vector3.ZERO
@export var damage: float = 8.0
@export var lifetime: float = 1.4
@export var fly_stream: AudioStream = null
@export var impact_stream: AudioStream = null
@export var fly_volume_db: float = 0.0
@export var impact_volume_db: float = 0.0

# Shared across ALL FlameProjectile instances
static var _last_fly_player: AudioStreamPlayer3D = null

# ===============================
# STATE
# ===============================
var shooter: Node = null

var _timer: float = 0.0
var _expired: bool = false
var _mesh: MeshInstance3D
var _light: OmniLight3D
var _particles: GPUParticles3D
var _fly_player: AudioStreamPlayer3D
var _impact_player: AudioStreamPlayer3D

# ===============================
# READY
# ===============================
func _ready() -> void:
	collision_layer = 0
	collision_mask  = 0b00000011
	monitoring  = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	_build_visuals()
	_build_audio()

	# Cut previous projectile's fly sound
	if is_instance_valid(_last_fly_player):
		_last_fly_player.stop()
		_last_fly_player.queue_free()
		_last_fly_player = null

	if is_instance_valid(_fly_player) and fly_stream:
		_fly_player.play()
		_last_fly_player = _fly_player

# ===============================
# PHYSICS
# ===============================
func _physics_process(delta: float) -> void:
	if _expired:
		return

	global_position += velocity * delta
	_timer += delta
	_light.light_energy = lerp(_light.light_energy, 3.0 + randf() * 1.2, 0.35)

	if _timer >= lifetime:
		_expire()

# ===============================
# HIT
# ===============================
func _on_body_entered(body: Node) -> void:
	if _expired:
		return
	if body == shooter:
		return
	if _is_friendly(body):
		return

	var target := _resolve_damageable(body)
	if target:
		target.take_damage(damage, shooter)

	_expire()

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
func _is_friendly(body: Node) -> bool:
	if not is_instance_valid(shooter):
		return false
	var shooter_team: int = shooter.get("team_id") if shooter.get("team_id") != null else -1
	var target_team: int = body.get("team_id") if body.get("team_id") != null else -1
	if shooter_team == -1 or target_team == -1:
		return false
	return shooter_team == target_team

# ===============================
# EXPIRE
# ===============================
func _expire() -> void:
	if _expired:
		return
	_expired = true
	set_physics_process(false)
	monitoring = false
	_particles.emitting = false
	_light.light_energy = 0.0
	_mesh.visible = false

	# Reparent fly player so it finishes naturally
	if is_instance_valid(_fly_player) and fly_stream:
		var fly := _fly_player
		var fly_pos := global_position
		remove_child(fly)
		get_tree().root.add_child(fly)
		fly.global_position = fly_pos
		get_tree().create_timer(fly_stream.get_length()).timeout.connect(
			func(): if is_instance_valid(fly): fly.queue_free()
		)

	# Reparent impact player so it survives queue_free
	if is_instance_valid(_impact_player) and impact_stream:
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
	_fly_player.max_distance = 20.0
	add_child(_fly_player)

	_impact_player = AudioStreamPlayer3D.new()
	_impact_player.stream = impact_stream
	_impact_player.autoplay = false
	_impact_player.volume_db = impact_volume_db
	_impact_player.max_distance = 20.0
	add_child(_impact_player)

# ===============================
# VISUALS
# ===============================
func _build_visuals() -> void:
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.18
	col.shape = sphere
	add_child(col)

	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height  = 0.12
	_mesh.mesh = sm

	var mat := StandardMaterial3D.new()
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.45, 0.05)
	mat.emission_energy_multiplier = 6.0
	mat.albedo_color               = Color(1.0, 0.6, 0.1)
	_mesh.material_override = mat
	add_child(_mesh)

	_light = OmniLight3D.new()
	_light.light_color    = Color(1.0, 0.4, 0.05)
	_light.light_energy   = 3.5
	_light.omni_range     = 1.8
	_light.shadow_enabled = false
	add_child(_light)

	_particles = GPUParticles3D.new()
	_particles.emitting      = true
	_particles.amount        = 18
	_particles.lifetime      = 0.35
	_particles.explosiveness = 0.0
	_particles.randomness    = 0.6
	_particles.one_shot      = false
	_particles.local_coords  = false

	var pm := ParticleProcessMaterial.new()
	pm.direction            = Vector3(0.0, 1.0, 0.0)
	pm.spread               = 30.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity              = Vector3(0.0, 0.4, 0.0)
	pm.scale_min            = 0.04
	pm.scale_max            = 0.10

	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.6, 0.1, 1.0))
	gradient.add_point(1.0, Color(0.8, 0.1, 0.0, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = gradient
	pm.color_ramp = grad_tex
	_particles.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)

	var pmat := StandardMaterial3D.new()
	pmat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.emission_enabled           = true
	pmat.emission                   = Color(1.0, 0.3, 0.0)
	pmat.emission_energy_multiplier = 3.0
	pmat.billboard_mode             = BaseMaterial3D.BILLBOARD_ENABLED
	pmat.albedo_color               = Color(1.0, 0.5, 0.05, 1.0)
	quad.material = pmat

	_particles.draw_pass_1 = quad
	add_child(_particles)
