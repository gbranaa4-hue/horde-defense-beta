extends BaseGun
class_name RocketGun

@export var rocket_scene: PackedScene
@export var rocket_speed: float = 28.0
@export var explosion_damage: float = 85.0
@export var explosion_radius: float = 5.5
@export var knockback_force: float = 18.0

func _fire_projectile() -> void:
	if camera == null or rocket_scene == null:
		return
	
	var rocket = rocket_scene.instantiate()
	if not is_instance_valid(rocket):
		return
	
	get_tree().current_scene.add_child(rocket)
	
	var forward = -camera.global_transform.basis.z.normalized()
	rocket.global_position = camera.global_position + forward * 1.8
	
	# Initialize rocket
	if rocket.has_method("init"):
		rocket.init(forward * rocket_speed, self, explosion_damage, explosion_radius, knockback_force)
	else:
		# Fallback
		if "velocity" in rocket: rocket.velocity = forward * rocket_speed
		if "shooter" in rocket: rocket.shooter = self
		if "damage" in rocket: rocket.damage = explosion_damage
