var shop_camera: Camera3D

func _ready():
	shop_camera = Camera3D.new()
	shop_camera.name = "ShopCamera"
	shop_camera.current = false  # only active when shop opens
	shop_camera.orthogonal = true
	shop_camera.size = 50  # adjusts zoom
	shop_camera.position = Vector3(map_center_x, 50, map_center_z)  # above map
	shop_camera.rotation_degrees = Vector3(-90, 0, 0)  # look straight down
	add_child(shop_camera)
