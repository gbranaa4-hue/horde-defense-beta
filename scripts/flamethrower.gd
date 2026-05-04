extends BaseGun
class_name Flamethrower

@export var cone_angle:             float       = 25.0
@export var projectile_speed:       float       = 20.0
@export var tick_rate:              float       = 0.08
@export var rays_per_tick:          int         = 6
@export var flame_projectile_scene: PackedScene = null
@export var flame_spawn_offset:     float       = 1.3

var firing: bool = false
var _aim_origin:    Vector3 = Vector3.ZERO
var _aim_direction: Vector3 = Vector3.FORWARD

func shoot() -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if firing or reloading or not is_instance_valid(camera):
		return
	if current_ammo <= 0:
		start_reload()
		return
	firing = true
	_fire_continuous()

func stop_shoot() -> void:
	firing = false

func unequip() -> void:
	firing = false
	super.unequip()

func _fire_continuous() -> void:
	while firing and current_ammo > 0 and is_instance_valid(camera):
		_cache_aim()
		current_ammo -= 1
		ammo_changed.emit(current_ammo, max_ammo)
		for i in rays_per_tick:
			_spawn_flame_projectile()
		await get_tree().create_timer(tick_rate).timeout
	firing = false
	if current_ammo <= 0 and not reloading:
		start_reload()

func _cache_aim() -> void:
	var viewport := camera.get_viewport()
	var screen_center := viewport.get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(screen_center)
	var ray_dir := camera.project_ray_normal(screen_center)
	var ray_end := ray_origin + ray_dir * 2000.0

	var space := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	if player and player is CollisionObject3D:
		query.exclude = [player.get_rid()]

	var result := space.intersect_ray(query)
	var target_point: Vector3 = ray_end
	if not result.is_empty():
		target_point = result.position

	_aim_origin = ray_origin
	var spawn_pos := ray_origin + ray_dir * flame_spawn_offset
	_aim_direction = (target_point - spawn_pos).normalized()

func _spawn_flame_projectile() -> void:
	if flame_projectile_scene == null or not is_instance_valid(camera):
		return

	var instance := flame_projectile_scene.instantiate()
	if not instance is FlameProjectile:
		push_error("[Flamethrower] Flame projectile root must be FlameProjectile (Area3D)!")
		instance.queue_free()
		return

	var proj := instance as FlameProjectile
	get_tree().current_scene.add_child(proj)

	var right := camera.global_transform.basis.x
	var up    := camera.global_transform.basis.y
	var h     := deg_to_rad(randf_range(-cone_angle,       cone_angle))
	var v     := deg_to_rad(randf_range(-cone_angle * 0.6, cone_angle * 0.6))
	var spread_dir := _aim_direction.rotated(up, h).rotated(right, v).normalized()

	proj.global_position = _aim_origin + spread_dir * flame_spawn_offset
	proj.velocity        = spread_dir * projectile_speed
	proj.shooter         = self
	proj.damage          = damage
