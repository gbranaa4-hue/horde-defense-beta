extends Node

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_click()

func _handle_click():
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var from = cam.project_ray_origin(mouse_pos)
	var to = from + cam.project_ray_normal(mouse_pos) * 1000

	var space_state = cam.get_world_3d().direct_space_state

	# Create ray query parameters
	var ray_params = PhysicsRayQueryParameters3D.new()
	ray_params.from = from
	ray_params.to = to
	ray_params.exclude = []
	ray_params.collision_mask = 1      # Make sure turrets are on this physics layer
	ray_params.collide_with_bodies = true
	ray_params.collide_with_areas = true

	var result = space_state.intersect_ray(ray_params)

	if result:
		var clicked_node = result.collider
		if clicked_node and clicked_node.is_in_group("towers"):
			var ui = get_tree().get_first_node_in_group("ui")
			if is_instance_valid(ui):
				ui.open(clicked_node)
			else:
				print("UI not found!")
