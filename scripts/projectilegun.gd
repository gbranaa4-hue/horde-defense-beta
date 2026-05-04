extends BaseGun
class_name ProjectileGun

@export var bullet_scene: PackedScene
@export var bullet_speed: float = 60.0

func _fire_projectile() -> void:
	if camera == null or bullet_scene == null:
		return

	# ===============================
	# 1. GET TRUE SCREEN CENTER
	# ===============================
	var viewport := camera.get_viewport()
	var screen_center := viewport.get_visible_rect().size * 0.5

	# ===============================
	# 2. CAMERA RAY (THIS IS AIM)
	# ===============================
	var ray_origin := camera.project_ray_origin(screen_center)
	var ray_dir := camera.project_ray_normal(screen_center)
	var ray_end := ray_origin + ray_dir * 2000.0

	# ===============================
	# 3. RAYCAST
	# ===============================
	var space := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)

	if player and player is CollisionObject3D:
		query.exclude = [player.get_rid()]

	var result := space.intersect_ray(query)

	var target_point := ray_end
	if result:
		target_point = result.position

	# ===============================
	# 4. SPAWN BULLET AT CAMERA
	# ===============================
	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)

	bullet.global_position = ray_origin

	# ===============================
	# 5. PERFECT DIRECTION
	# ===============================
	var direction := (target_point - ray_origin).normalized()

	if bullet.has_method("init"):
		bullet.init(direction * bullet_speed, self, damage)
