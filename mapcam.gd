extends Node3D

var shop_camera: Camera3D
var map_center_x: float = 0.0
var map_center_z: float = 0.0

func _ready() -> void:
	var map: Node3D = get_tree().get_root().get_node_or_null("MapRoot") as Node3D
	if map:
		var aabb: AABB = map.get_aabb()
		map_center_x = aabb.position.x + aabb.size.x / 2.0
		map_center_z = aabb.position.z + aabb.size.z / 2.0
	else:
		push_warning("MapRoot not found, using origin as center.")

	shop_camera = Camera3D.new()
	shop_camera.name = "ShopCamera"
	shop_camera.current = false
	shop_camera.projection = 1  # 1 = ORTHOGONAL (raw int, enum constant broken in GDScript)
	shop_camera.size = 50.0
	shop_camera.position = Vector3(map_center_x, 50.0, map_center_z)
	shop_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(shop_camera)
