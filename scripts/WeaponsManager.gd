# ============================================================
# weapon_manager.gd
# Handles equipping, switching, shooting, and reloading guns.
# Shooting is NOT gated on MOUSE_MODE_CAPTURED so top-down fire
# works. The shop's _unhandled_input fires via player.topdown_fire()
# → weapon_manager.try_shoot(), bypassing this _input entirely.
# ============================================================
extends Node
class_name WeaponManager

# ===============================
# EXPORTS
# ===============================
@export var weapons              : Array[BaseGun]         = []
@export var switch_sound         : AudioStreamPlayer      = null
@export var default_gun_position : Vector3                = Vector3(0.2, -0.2, -0.6)
@export var weapon_holder        : Node3D                 = null

# ===============================
# STATE
# ===============================
var current_index  : int     = -1
var current_weapon : BaseGun = null
var camera         : Camera3D = null
var player         : Node     = null
var _is_firing: bool = false
# ===============================
# SIGNALS
# ===============================
signal weapon_changed(current_gun: BaseGun)
signal weapon_equipped(gun: BaseGun, index: int, total: int)

# ===============================
# READY
# ===============================
func _ready() -> void:
	await get_tree().process_frame

	player = _find_player()
	if player == null:
		push_error("[WeaponManager] No player found in parent chain.")
		return

	camera = _find_camera(player)
	if camera == null:
		push_error("[WeaponManager] No Camera3D found on player.")
		return

	if weapon_holder == null:
		weapon_holder = camera

	if weapons.is_empty():
		_collect_guns(self)

	if weapons.is_empty():
		push_error("[WeaponManager] No BaseGun children found.")
		return

	print("[WeaponManager] %d gun(s) loaded." % weapons.size())

	for gun in weapons:
		_set_active_recursive(gun, false)

	equip(0)

# ===============================
# INPUT
# Owns weapon switching (scroll wheel) and reload (R).
# FPS left-click shooting is handled here.
# Top-down shooting is handled by shop.gd → player.topdown_fire() → try_shoot().
# ===============================
func _input(event: InputEvent) -> void:
	print("WM INPUT:", event)
	if _is_shop_open():
		return

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				# FPS mode only — top-down click is consumed by shop._unhandled_input first
				if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
					try_shoot()
			MOUSE_BUTTON_WHEEL_UP:
				switch_weapon(-1)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				switch_weapon(1)
				get_viewport().set_input_as_handled()

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				try_reload()
				get_viewport().set_input_as_handled()

# ===============================
# WEAPON SWITCHING
# ===============================
func switch_weapon(dir: int) -> void:
	if weapons.is_empty():
		return
	var new_index : int = posmod(current_index + dir, weapons.size())
	if new_index != current_index:
		equip(new_index)

func switch_to(index: int) -> void:
	if index < 0 or index >= weapons.size():
		push_warning("[WeaponManager] switch_to: index %d out of range." % index)
		return
	if index != current_index:
		equip(index)

func next_weapon() -> void: switch_weapon(1)
func prev_weapon() -> void: switch_weapon(-1)

# ===============================
# EQUIP
# ===============================
func equip(index: int) -> void:
	if index < 0 or index >= weapons.size():
		return

	if current_index != -1:
		var old : BaseGun = weapons[current_index]
		old.unequip()
		_set_active_recursive(old, false)

	current_index  = index
	var gun : BaseGun = weapons[current_index]
	current_weapon = gun

	if gun.get_parent() != weapon_holder:
		if gun.get_parent():
			gun.get_parent().remove_child(gun)
		weapon_holder.add_child(gun)

	gun.transform = Transform3D.IDENTITY
	gun.position  = default_gun_position
	gun.rotation  = Vector3.ZERO
	gun.scale     = Vector3.ONE

	_set_active_recursive(gun, true)
	gun.equip(camera, player)
	_play_switch_sound()

	print("[WeaponManager] Equipped: %s (%d/%d)" % [gun.name, current_index + 1, weapons.size()])
	weapon_changed.emit(gun)
	weapon_equipped.emit(gun, current_index, weapons.size())

# ===============================
# ACTIONS
# ===============================
func try_shoot() -> void:
	var gun := get_current_weapon()
	if gun == null:
		return
	# If out of ammo, auto-reload instead of dry-firing
	if "current_ammo" in gun and gun.current_ammo <= 0:
		try_reload()
		return
	gun.shoot()

func try_reload() -> void:
	var gun := get_current_weapon()
	if gun == null:
		return
	if gun.has_method("reload"):
		gun.reload()
	else:
		push_warning("[WeaponManager] Current gun has no reload() method.")

func get_current_weapon() -> BaseGun:
	if current_index < 0 or weapons.is_empty():
		return null
	return weapons[current_index]

func get_weapon_count() -> int:
	return weapons.size()

func has_weapon_at(index: int) -> bool:
	return index >= 0 and index < weapons.size()

# ===============================
# SWITCH SOUND
# ===============================
func _play_switch_sound() -> void:
	if not is_instance_valid(switch_sound):
		return
	switch_sound.stop()
	switch_sound.play()

# ===============================
# RECURSIVE ACTIVATION
# ===============================
func _set_active_recursive(node: Node, active: bool) -> void:
	if node is Node3D:
		(node as Node3D).visible = active
	node.set_process(active)
	node.set_physics_process(active)
	for child in node.get_children():
		_set_active_recursive(child, active)

# ===============================
# AUTO COLLECT GUNS
# ===============================
func _collect_guns(root: Node) -> void:
	for child in root.get_children():
		if child is BaseGun:
			weapons.append(child)
		else:
			_collect_guns(child)

# ===============================
# FIND PLAYER + CAMERA
# ===============================
func _find_player() -> Node:
	var n : Node = get_parent()
	while is_instance_valid(n):
		if n.get("team_id") != null:
			return n
		n = n.get_parent()
	return null

func _find_camera(root: Node) -> Camera3D:
	if root is Camera3D:
		return root as Camera3D
	for child in root.get_children():
		var result := _find_camera(child)
		if result:
			return result
	return null

func _is_shop_open() -> bool:
	if not is_instance_valid(player):
		return false
	if player.has_method("_is_shop_panel_open"):
		return player._is_shop_panel_open()
	return false
