




extends CharacterBody3D

@export_group("Health")
@export var max_health: float = 100.0

@export_group("Movement")
@export var speed: float = 8.0

var current_health: float

signal health_changed(new_health, max_health)
signal died

func _ready():
	current_health = max_health
	health_changed.emit(current_health, max_health)
	add_to_group("players")
	print("Player ready at: ", global_position)

func _physics_process(_delta):
	# Get input
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	print("Input: ", input_dir)  # Debug
	
	# Convert to 3D direction relative to player rotation
	var direction = (transform.basis.x * input_dir.x + transform.basis.z * -input_dir.y).normalized()
	print("Direction: ", direction)  # Debug
	
	if direction.length() > 0.01:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= 9.8 * _delta
	else:
		velocity.y = 0
	
	print("Velocity: ", velocity)  # Debug
	
	move_and_slide()

func take_damage(amount: float, _attacker = null):
	if current_health <= 0:
		return
	
	current_health -= amount
	current_health = clamp(current_health, 0.0, max_health)
	
	health_changed.emit(current_health, max_health)
	_flash_damage()
	
	if current_health <= 0:
		_die()

func _die():
	died.emit()
	set_physics_process(false)
	queue_free()

func _flash_damage():
	var mesh = _find_mesh(self)
	if mesh:
		var tween = create_tween()
		tween.tween_property(mesh, "modulate", Color.RED, 0.05)
		tween.tween_property(mesh, "modulate", Color.WHITE, 0.1)

func _find_mesh(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			return child
		var found = _find_mesh(child)
		if found:
			return found
	return null
