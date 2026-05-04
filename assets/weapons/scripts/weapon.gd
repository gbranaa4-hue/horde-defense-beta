extends Node3D

@export var damage := 25.0
@export var fire_rate := 0.15
@export var max_ammo := 30
@export var reload_time := 1.5
@export var range := 1000.0

var current_ammo: int
var can_shoot := true
var is_reloading := false

signal ammo_changed(current_ammo, max_ammo)
signal reload_started
signal reload_finished

func _ready():
	current_ammo = max_ammo
	emit_signal("ammo_changed", current_ammo, max_ammo)

func shoot():
	if not can_shoot or is_reloading:
		return
	if current_ammo <= 0:
		reload()
		return

	current_ammo -= 1
	can_shoot = false
	emit_signal("ammo_changed", current_ammo, max_ammo)

	_fire_ray()

	await get_tree().create_timer(fire_rate).timeout
	can_shoot = true
	if current_ammo <= 0:
		reload()

func _fire_ray():
	var player = get_parent()
	var camera = player.get_node("CameraPivot/Camera3D")
	var from = camera.global_position
	var to = from - camera.global_transform.basis.z * range

	var space_state = get_world_3d().direct_space_state
	var params = PhysicsRayQueryParameters3D.new()
	params.from = from
	params.to = to
	params.exclude = [player]
	params.collision_mask = 2

	var result = space_state.intersect_ray(params)
	if result:
		var target = result.collider
		if target.has_method("take_damage"):
			target.take_damage(damage, player)

func reload():
	if is_reloading or current_ammo == max_ammo:
		return
	is_reloading = true
	emit_signal("reload_started")
	await get_tree().create_timer(reload_time).timeout
	current_ammo = max_ammo
	is_reloading = false
	emit_signal("ammo_changed", current_ammo, max_ammo)
	emit_signal("reload_finished")
