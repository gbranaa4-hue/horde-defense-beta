# rocket_projectile.gd
# Rockets pass through the shooter (no self-collision) but still
# deal splash damage + knockback to them on detonation.
extends Node3D
class_name RocketProjectile

# ── CONFIG ──────────────────────────────────────────────────
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

# ── STATE ───────────────────────────────────────────────────
var velocity: Vector3 = Vector3.ZERO
var shooter: Node = null
var _exploded: bool = false
var _last_position: Vector3
var _fly_player: AudioStreamPlayer3D
var _explosion_player: AudioStreamPlayer3D

# ── INIT ────────────────────────────────────────────────────
func init(new_velocity: Vector3, new_shooter: Node,
		dmg: float, radius: float, knockback: float) -> void:
	velocity         = new_velocity * speed_multiplier
	shooter          = new_shooter
	explosion_damage = dmg
	explosion_radius = radius
	knockback_force  = knockback

# ── LIFECYCLE ───────────────────────────────────────────────
func _ready() -> void:
	_last_position = global_position
	_create_visuals()
	_build_audio()
	if is_instance_valid(_fly_player) and fly_stream:
		_fly_player.play()
	get_tree().create_timer(lifetime).timeout.connect(explode)

# ── PHYSICS ─────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if _exploded:
		return

	velocity.y -= gravity_scale * delta
	if velocity.length() > max_travel_speed:
		velocity = velocity.normalized() * max_travel_speed

	var new_pos: Vector3 = global_position + velocity * delta

	# Ray excludes shooter so the rocket passes through without colliding.
	# The splash query does NOT exclude the shooter — self-damage is intentional.
	var space := get_world_3d().direct_space_state
	var ray   := PhysicsRayQueryParameters3D.create(_last_position, new_pos)
	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		ray.exclude = [shooter.get_rid()]

	var hit := space.intersect_ray(ray)
	if hit:
		global_position = hit.position
		explode()
		return

	global_position = new_pos
	_last_position  = global_position
	_orient_to_velocity()

func _orient_to_velocity() -> void:
	var dir: Vector3 = velocity.normalized()
	var up:  Vector3 = Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	look_at(global_position + dir, up)

# ── EXPLOSION ───────────────────────────────────────────────
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

# ── SPLASH DAMAGE ───────────────────────────────────────────
func _apply_splash_damage() -> void:
	var space := get_world_3d().direct_space_state

	var shape := SphereShape3D.new()
	shape.radius = explosion_radius

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape     = shape
	query.transform = global_transform
	# Shooter is NOT excluded — they take splash damage and knockback.

	var damaged: Dictionary = {}

	for result in space.intersect_shape(query):
		var body: Node = result.collider
		if not is_instance_valid(body):
			continue

		var target := _resolve_target(body)
		if target == null or damaged.has(target):
			continue

		# Allow shooter through; only block non-shooter teammates.
		if not _is_shooter(target) and _is_friendly(target):
			continue

		damaged[target] = true
		_damage_target(target)

func _damage_target(target: Node) -> void:
	var dist:       float = global_position.distance_to(target.global_position)
	var normalized: float = clamp(dist / explosion_radius, 0.0, 1.0)
	var falloff:    float = clamp(pow(1.0 - normalized, falloff_exponent), min_falloff, 1.0)
	if dist < 0.5:
		falloff = min(falloff * direct_hit_bonus, 1.0)

	var dir: Vector3 = (target.global_position - global_position).normalized()
	target.take_damage(explosion_damage * falloff, shooter)

	if target is CharacterBody3D:
		# Apply vertical bias before normalizing so the kick arc is correct.
		var kick     := Vector3(dir.x, dir.y + knockback_vertical_bias, dir.z).normalized()
		var strength := knockback_force * (falloff if knockback_falloff else 1.0)
		(target as CharacterBody3D).velocity += kick * strength

# ── TREE HELPERS ────────────────────────────────────────────
# Walk up the tree to find the node that owns take_damage().
func _resolve_target(node: Node) -> Node:
	var current := node
	while is_instance_valid(current):
		if current.has_method("take_damage"):
			return current
		current = current.get_parent()
	return null

# True if node IS the shooter or is a descendant of the shooter.
func _is_shooter(node: Node) -> bool:
	if not is_instance_valid(shooter):
		return false
	var current := node
	while is_instance_valid(current):
		if current == shooter:
			return true
		current = current.get_parent()
	return false

# True if target shares a team with shooter (both must expose team_id).
func _is_friendly(target: Node) -> bool:
	if not is_instance_valid(shooter):
		return false
	var s_team := _get_team_id(shooter)
	var t_team := _get_team_id(target)
	return s_team != -1 and t_team != -1 and s_team == t_team

func _get_team_id(node: Node) -> int:
	var current := node
	while is_instance_valid(current):
		if "team_id" in current:
			return current.team_id
		current = current.get_parent()
	return -1

# ── AUDIO ───────────────────────────────────────────────────
func _build_audio() -> void:
	_fly_player       = _make_audio_player(fly_stream,       fly_volume_db,       40.0)
	_explosion_player = _make_audio_player(explosion_stream, explosion_volume_db, 60.0)

func _make_audio_player(stream: AudioStream, vol_db: float, max_dist: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream       = stream
	p.autoplay     = false
	p.volume_db    = vol_db
	p.max_distance = max_dist
	add_child(p)
	return p

func _play_explosion_sound() -> void:
	if not is_instance_valid(_explosion_player) or not explosion_stream:
		return
	# Re-parent to scene root so the sound outlives the projectile node.
	var p   := _explosion_player
	var pos := global_position
	remove_child(p)
	get_tree().root.add_child(p)
	p.global_position = pos
	p.play()
	get_tree().create_timer(explosion_stream.get_length()).timeout.connect(
		func(): if is_instance_valid(p): p.queue_free()
	)

# ── VFX ─────────────────────────────────────────────────────
func _spawn_explosion_vfx() -> void:
	var root := Node3D.new()
	get_tree().current_scene.add_child(root)
	root.global_position = global_position

	var mat := StandardMaterial3D.new()
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled           = true
	mat.emission                   = flash_color
	mat.emission_energy_multiplier = flash_energy

	var sphere := SphereMesh.new()
	sphere.radius = 0.2

	var mesh := MeshInstance3D.new()
	mesh.mesh              = sphere
	mesh.material_override = mat
	root.add_child(mesh)

	var light := OmniLight3D.new()
	light.light_energy = light_energy
	light.omni_range   = light_range
	root.add_child(light)

	var t := root.create_tween()
	t.tween_property(mesh,  "scale",                       flash_scale, flash_duration)
	t.tween_property(mat,   "emission_energy_multiplier",  0.0,         flash_fade_duration)
	t.tween_property(light, "light_energy",                0.0,         flash_fade_duration)
	t.chain().tween_callback(root.queue_free)

func _create_visuals() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.8, 0.3, 0.1)
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.4, 0.1)
	mat.emission_energy_multiplier = 3.0

	var cyl := CylinderMesh.new()
	cyl.top_radius    = 0.04
	cyl.bottom_radius = 0.04
	cyl.height        = 0.5

	var mesh := MeshInstance3D.new()
	mesh.mesh               = cyl
	mesh.material_override  = mat
	mesh.rotation_degrees.x = -90
	add_child(mesh)
