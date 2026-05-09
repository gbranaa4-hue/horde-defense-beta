# ============================================================
# inputsetup.gd — AUTOLOAD (name: inputsetup)
# ============================================================
# Call inputsetup.setup_player_inputs(player_id, device_id)
# BEFORE add_child() so actions exist when _ready() fires.
#
# device_id:
#   -1  = keyboard + mouse (player 1 by convention)
#   >=0 = gamepad index
#   -99 = no device (actions registered but never fire)
# ============================================================
extends Node


func setup_player_inputs(player_id: int, device_id: int) -> void:
	_clear_player_actions(player_id)

	match device_id:
		-1:
			_setup_kbm(player_id)
		-99:
			_register_empty_actions(player_id)
		_:
			if device_id >= 0:
				_setup_gamepad(player_id, device_id)


# ============================================================
# KBM — player 1 by convention
# ============================================================
func _setup_kbm(pid: int) -> void:
	_add_key(pid, "move_forward",  KEY_W)
	_add_key(pid, "move_backward", KEY_S)
	_add_key(pid, "move_left",     KEY_A)
	_add_key(pid, "move_right",    KEY_D)
	_add_key(pid, "jump",          KEY_SPACE)
	_add_key(pid, "sprint",        KEY_SHIFT)
	_add_key(pid, "reload",        KEY_R)
	_add_key(pid, "shop",          KEY_TAB)
	_add_mouse_btn(pid, "shoot",   MOUSE_BUTTON_LEFT)
	_add_mouse_btn(pid, "aim",     MOUSE_BUTTON_RIGHT)
	# weapon switch handled via scroll wheel in _input(), no action needed
	_register_empty_action(pid, "prev_weapon")
	_register_empty_action(pid, "next_weapon")


# ============================================================
# GAMEPAD
# ============================================================
func _setup_gamepad(pid: int, device: int) -> void:
	_add_joy_axis(pid, "move_forward",  device, JOY_AXIS_LEFT_Y,      false)
	_add_joy_axis(pid, "move_backward", device, JOY_AXIS_LEFT_Y,      true)
	_add_joy_axis(pid, "move_left",     device, JOY_AXIS_LEFT_X,      false)
	_add_joy_axis(pid, "move_right",    device, JOY_AXIS_LEFT_X,      true)
	_add_joy_btn (pid, "jump",          device, JOY_BUTTON_A)
	_add_joy_btn (pid, "sprint",        device, JOY_BUTTON_LEFT_STICK)
	_add_joy_btn (pid, "reload",        device, JOY_BUTTON_X)
	_add_joy_btn (pid, "shop",          device, JOY_BUTTON_Y)
	_add_joy_axis(pid, "shoot",         device, JOY_AXIS_TRIGGER_RIGHT, true)
	_add_joy_axis(pid, "aim",           device, JOY_AXIS_TRIGGER_LEFT,  true)
	_add_joy_btn (pid, "prev_weapon",   device, JOY_BUTTON_DPAD_LEFT)
	_add_joy_btn (pid, "next_weapon",   device, JOY_BUTTON_DPAD_RIGHT)


# ============================================================
# EMPTY ACTIONS — register so _act() never crashes
# ============================================================
func _register_empty_actions(pid: int) -> void:
	var names := [
		"move_forward", "move_backward", "move_left", "move_right",
		"jump", "sprint", "reload", "shop", "shoot", "aim",
		"prev_weapon", "next_weapon"
	]
	for n in names:
		_register_empty_action(pid, n)

func _register_empty_action(pid: int, name: String) -> void:
	var action := _action(pid, name)
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


# ============================================================
# HELPERS
# ============================================================
func _action(pid: int, name: String) -> String:
	return "p%d_%s" % [pid, name]

func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)

func _clear_player_actions(pid: int) -> void:
	var names := [
		"move_forward", "move_backward", "move_left", "move_right",
		"jump", "sprint", "reload", "shop", "shoot", "aim",
		"prev_weapon", "next_weapon"
	]
	for n in names:
		var action := _action(pid, n)
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)

func _add_key(pid: int, name: String, keycode: Key) -> void:
	var action := _action(pid, name)
	_ensure_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.device = -1
	InputMap.action_add_event(action, ev)

func _add_mouse_btn(pid: int, name: String, btn: MouseButton) -> void:
	var action := _action(pid, name)
	_ensure_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	ev.device = -1
	InputMap.action_add_event(action, ev)

func _add_joy_btn(pid: int, name: String, device: int, btn: JoyButton) -> void:
	var action := _action(pid, name)
	_ensure_action(action)
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = btn
	InputMap.action_add_event(action, ev)

func _add_joy_axis(pid: int, name: String, device: int, axis: JoyAxis, positive: bool) -> void:
	var action := _action(pid, name)
	_ensure_action(action)
	var ev := InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = axis
	ev.axis_value = 1.0 if positive else -1.0
	InputMap.action_add_event(action, ev)
