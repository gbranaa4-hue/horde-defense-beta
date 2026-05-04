extends Node3D
class_name RocketProjectile

# ===============================
# CONFIG
# ===============================
@export var explosion_radius: float = 6.0
@export var explosion_damage: float = 90.0
@export var knockback_force: float = 22.0
@export var lifetime: float = 5.0

@export_group("Travel")
@export var speed_multiplier: float = 0.45
@export var gravity_scale: float = 4.0
@export var max_travel_speed: float = 40.0

@export_group("Damage Falloff")
@export var min_falloff: float = 0.05
@export var falloff_exponent: float = 2.0
@export var direct_hit_bonus: float = 1.5

@export_group("Knockback")
@export var knockback_vertical_bias: float = 0.5
@export var knockback_falloff: bool = true

@export_group("Sound")
@export var fly_stream: AudioStream = null
@export var explosion_stream: AudioStream = null
@export var fly_volume_db: float = 0.0
@export var explosion_volume_db: float = 0.0

@export_group("VFX")
@export var flash_scale: Vector3 = Vector3(4, 4, 4)
@export var flash_duration: float = 0.15
@export var flash_fade_duration: float = 0.25
@export var flash_color: Color = Color(1.0, 0.8, 0.5)
@export var flash_energy: float = 12.0
@export var light_range: float = 5.0
@export var light_energy: float = 8.0

# ===============================
# STATE
# ===============================
var velocity: Vector3 = Vector3.ZERO
var shooter: Node = null
var _exploded: bool = false
var _last_position: Vector3
var _fly_player: AudioStreamPlayer3D
var _explosion_player: AudioStreamPlayer3D

# ===============================
# INIT
# ===============================
func init(new_velocity: Vector3, new_shooter: Node,
		dmg: float, radius: float, knockback: float) -> void:
	velocity = new_velocity * speed_multiplier
	shooter = new_shooter
	explosion_damage = dmg
	explosion_radius = radius
	knockback_force = knockback

# ===============================
# READY
# ===============================
func _ready() -> void:
	_last_position = global_position
	_create_visuals()
	_build_audio()

	if is_instance_valid(_fly_player) and fly_stream:
		_fly_player.play()

	get_tree().create_timer(lifetime).timeout.connect(explode)

# ===============================
# PHYSICS
# ===============================
func _physics_process(delta: float) -> void:
	if _exploded:
		return

	velocity.y -= gravity_scale * delta

	if velocity.length() > max_travel_speed:
		velocity = velocity.normalized() * max_travel_speed

	var new_pos: Vector3 = global_position + velocity * delta

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(_last_position, new_pos)
	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		query.exclude = [shooter.get_rid()]

	var hit := space.intersect_ray(query)
	if hit:
		global_position = hit.position
		explode()
		return

	global_position = new_pos
	_last_position = global_position

	var dir: Vector3 = velocity.normalized()
	var up: Vector3 = Vector3.UP
	if abs(dir.dot(up)) > 0.98:
		up = Vector3.FORWARD
	look_at(global_position + dir, up)

# ===============================
# EXPLOSION
# ===============================
func explode() -> void:
	if _exploded:
		return
	_exploded = true

	if is_instance_valid(_fly_player):
		_fly_player.stop()

	_apply_splash_damage()
	_spawn_explosion_vfx()
	_play_explosion_sound()
	queue_free()

# ===============================
# SPLASH DAMAGE
# ===============================
func _apply_splash_damage() -> void:
	var space := get_world_3d().direct_space_state

	var shape := SphereShape3D.new()
	shape.radius = explosion_radius

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = global_transform
	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		query.exclude = [shooter.get_rid()]

	var results := space.intersect_shape(query)

	for result in results:
		var body: Node3D = result.collider as Node3D
		if not is_instance_valid(body) or body == shooter:
			continue
		if _is_friendly(body):
			continue

		var body_pos: Vector3 = body.global_position
		var dist: float = global_position.distance_to(body_pos)
		var normalized: float = clamp(dist / explosion_radius, 0.0, 1.0)

		var falloff: float = clamp(
			pow(1.0 - normalized, falloff_exponent),
			min_falloff,
			1.0
		)

		if dist < 0.5:
			falloff = min(falloff * direct_hit_bonus, 1.0)

		var dir: Vector3 = (body_pos - global_position).normalized()

		if body.has_method("take_damage"):
			body.take_damage(explosion_damage * falloff, shooter)

		if body is CharacterBody3D:
			var cb: CharacterBody3D = body as CharacterBody3D
			var kick: Vector3 = dir
			kick.y += knockback_vertical_bias
			var kick_strength: float = knockback_force * (falloff if knockback_falloff else 1.0)
			cb.velocity += kick.normalized() * kick_strength

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
# AUDIO
# ===============================
func _build_audio() -> void:
	_fly_player = AudioStreamPlayer3D.new()
	_fly_player.stream = fly_stream
	_fly_player.autoplay = false
	_fly_player.volume_db = fly_volume_db
	_fly_player.max_distance = 40.0
	add_child(_fly_player)

	_explosion_player = AudioStreamPlayer3D.new()
	_explosion_player.stream = explosion_stream
	_explosion_player.autoplay = false
	_explosion_player.volume_db = explosion_volume_db
	_explosion_player.max_distance = 60.0
	add_child(_explosion_player)

func _play_explosion_sound() -> void:
	if not is_instance_valid(_explosion_player) or not explosion_stream:
		return
	var exp := _explosion_player
	var exp_pos := global_position
	remove_child(exp)
	get_tree().root.add_child(exp)
	exp.global_position = exp_pos
	exp.play()
	get_tree().create_timer(explosion_stream.get_length()).timeout.connect(
		func(): if is_instance_valid(exp): exp.queue_free()
	)

# ===============================
# EXPLOSION VFX
# ===============================
func _spawn_explosion_vfx() -> void:
	var root := Node3D.new()
	get_tree().current_scene.add_child(root)
	root.global_position = global_position

	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = flash_color
	mat.emission_energy_multiplier = flash_energy
	mesh.material_override = mat
	root.add_child(mesh)

	var light := OmniLight3D.new()
	light.light_energy = light_energy
	light.omni_range = light_range
	root.add_child(light)

	var t := root.create_tween()
	t.tween_property(mesh, "scale", flash_scale, flash_duration)
	t.tween_property(mat, "emission_energy_multiplier", 0.0, flash_fade_duration)
	t.tween_property(light, "light_energy", 0.0, flash_fade_duration)
	t.chain().tween_callback(root.queue_free)

# ===============================
# ROCKET VISUAL
# ===============================
func _create_visuals() -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = 0.5
	mesh.mesh = cyl
	mesh.rotation_degrees.x = -90

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.3, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.1)
	mat.emission_energy_multiplier = 3.0
	mesh.material_override = mat
	add_child(mesh)
