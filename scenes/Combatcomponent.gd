# ============================================================
# CombatComponent.gd
# Owns shooting, aim assist, bullet magnetism
# ============================================================
extends ActorComponent
class_name CombatComponent

@export_group("Aim Assist")
@export var aim_assist_strength : float = 0.18
@export var bullet_magnetism    : float = 0.22

var weapon_manager  : Node = null   # set by player
var camera_comp     : CameraComponent = null

func _ready() -> void:
	initialize(get_parent() as CharacterBody3D)


func try_shoot() -> void:
	if not is_instance_valid(weapon_manager): return
	weapon_manager.try_shoot()

func try_reload() -> void:
	if is_instance_valid(weapon_manager): weapon_manager.try_reload()

func switch_weapon(dir: int) -> void:
	if is_instance_valid(weapon_manager): weapon_manager.switch_weapon(dir)


func get_shoot_origin() -> Vector3:
	if is_instance_valid(camera_comp): return camera_comp.get_shoot_origin()
	return actor.global_position + Vector3.UP * 1.5

func get_shoot_direction() -> Vector3:
	if is_instance_valid(camera_comp):
		var dir := camera_comp.get_shoot_direction()
		return _apply_aim_assist(dir)
	return -actor.global_transform.basis.z

func get_magnetized_direction(dir: Vector3) -> Vector3:
	var best : Node3D = null
	var best_dot : float = 0.92
	for z in actor.get_tree().get_nodes_in_group("zombies"):
		if not (z is Node3D): continue
		var to := ((z as Node3D).global_position - actor.global_position).normalized()
		var dot := dir.dot(to)
		if dot > best_dot:
			best_dot = dot; best = z as Node3D
	if not is_instance_valid(best): return dir
	return dir.lerp(
		(best.global_position - actor.global_position).normalized(),
		bullet_magnetism).normalized()

func _apply_aim_assist(dir: Vector3) -> Vector3:
	var best  : Node3D = null
	var best_score : float = INF
	for z in actor.get_tree().get_nodes_in_group("zombies"):
		if not (z is Node3D): continue
		var to := (z as Node3D).global_position - actor.global_position
		if to.length() > 20.0: continue
		var score := dir.distance_to(to.normalized())
		if score < best_score: best_score = score; best = z as Node3D
	if not is_instance_valid(best): return dir
	return dir.lerp(
		(best.global_position - actor.global_position).normalized(),
		aim_assist_strength).normalized()

func topdown_fire(dir: Vector3) -> void:
	if dir.length_squared() > 0.01:
		var flat := Vector3(dir.x, 0.0, dir.z).normalized()
		actor.look_at(actor.global_position + flat, Vector3.UP)
	try_shoot()

func apply_recoil(amount: float) -> void:
	if is_instance_valid(camera_comp): camera_comp.apply_recoil(amount)
