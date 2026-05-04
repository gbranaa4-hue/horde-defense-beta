extends BaseGun
class_name RocketGun

@export var rocket_scene: PackedScene
@export var rocket_speed: float = 28.0
@export var explosion_damage: float = 85.0
@export var explosion_radius: float = 5.5
@export var knockback_force: float = 18.0
@export var spawn_offset: float = 1.8

func _fire_projectile() -> void:
	if camera == null or rocket_scene == null:
		return

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

	var spawn_pos := ray_origin + ray_dir * spawn_offset
	var direction := (target_point - spawn_pos).normalized()

	var rocket = rocket_scene.instantiate()
	if not is_instance_valid(rocket):
		return

	get_tree().current_scene.add_child(rocket)
	rocket.global_position = spawn_pos

	if rocket.has_method("init"):
		rocket.init(direction * rocket_speed, self, explosion_damage, explosion_radius, knockback_force)
	else:
		if "velocity" in rocket: rocket.velocity = direction * rocket_speed
		if "shooter"  in rocket: rocket.shooter  = self
		if "damage"   in rocket: rocket.damage    = explosion_damage
