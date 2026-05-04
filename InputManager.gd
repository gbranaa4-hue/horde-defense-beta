extends Node

@onready var player = get_tree().get_first_node_in_group("players")

func _physics_process(_delta: float) -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_click_ray()

func _click_ray() -> void:
	if player == null:
		return

	var cam := player.get_node_or_null("Head/Camera3D") as Camera3D
	if cam == null:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var from      := cam.project_ray_origin(mouse_pos)
	var to        := from + cam.project_ray_normal(mouse_pos) * 1000.0

	var space  := cam.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.from               = from
	params.to                 = to
	params.collide_with_bodies = true
	params.collide_with_areas  = true
	params.collision_mask      = 1
	params.exclude             = [player.get_rid()]

	var result := space.intersect_ray(params)
	if result.is_empty():
		print("Ray missed")
		return

	var node := result.collider as Node
	if node == null:
		return

	print("Ray hit: ", node.name)

	if node.is_in_group("towers"):
		print("🔥 Turret clicked: ", node.name)
		_debug_sphere(result.position)
		var ui := get_tree().get_first_node_in_group("ui")
		if is_instance_valid(ui):
			ui.open(node)

func _debug_sphere(pos: Vector3) -> void:
	var mesh     := SphereMesh.new()
	mesh.radius   = 0.2
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	get_tree().current_scene.add_child(instance)
	instance.global_position = pos
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(instance):
		instance.queue_free()
