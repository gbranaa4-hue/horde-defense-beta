# ============================================================
# flamethrower.gd
# Continuous cone-spray flame weapon extending BaseGun
# - Fixed: ammo -> current_ammo (matches BaseGun rename)
# - Fixed: broken URL references on camera/proj globals
# - Fixed: stray 'w' typo before ammo check
# - Fixed: MOUSE_MODE_CAPTURED guard on shoot()
# - Fixed: is_instance_valid checks throughout
# ============================================================
extends BaseGun
class_name Flamethrower

# ===============================
# EXPORTS
# ===============================
@export var cone_angle            : float      = 25.0
@export var projectile_speed      : float      = 20.0
@export var tick_rate             : float      = 0.08
@export var rays_per_tick         : int        = 6
@export var flame_projectile_scene: PackedScene = null
@export var flame_spawn_offset    : float      = 1.3

# ===============================
# STATE
# ===============================
var firing : bool = false

# ===============================
# SHOOT / STOP
# ===============================
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

# ===============================
# CONTINUOUS FIRE LOOP
# ===============================
func _fire_continuous() -> void:
	while firing and current_ammo > 0 and is_instance_valid(camera):
		current_ammo -= 1
		ammo_changed.emit(current_ammo, max_ammo)

		for i in rays_per_tick:
			_spawn_flame_projectile()

		await get_tree().create_timer(tick_rate).timeout

	firing = false

	if current_ammo <= 0 and not reloading:
		start_reload()

# ===============================
# SPAWN FLAME PROJECTILE
# ===============================
func _spawn_flame_projectile() -> void:
	if flame_projectile_scene == null:
		push_warning("[Flamethrower] No flame_projectile_scene assigned.")
		return
	if not is_instance_valid(camera):
		return

	var instance := flame_projectile_scene.instantiate()
	if not instance is Area3D:
		push_error("[Flamethrower] Flame projectile root must be Area3D!")
		instance.queue_free()
		return

	var proj := instance as FlameProjectile

	get_tree().current_scene.add_child(proj)

	# Cone spread
	var forward := -camera.global_transform.basis.z
	var right   :=  camera.global_transform.basis.x
	var up      :=  camera.global_transform.basis.y

	var h_spread    := deg_to_rad(randf_range(-cone_angle, cone_angle))
	var v_spread    := deg_to_rad(randf_range(-cone_angle * 0.6, cone_angle * 0.6))
	var spread_dir  := forward.rotated(up, h_spread).rotated(right, v_spread).normalized()

	proj.global_position = camera.global_position + spread_dir * flame_spawn_offset
	proj.velocity        = spread_dir * projectile_speed
	proj.shooter         = self
	proj.damage          = damage
