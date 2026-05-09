# ============================================================
# GameMenuHandler.gd
# ============================================================
# Add as a Node in your main game scene.
# Handles in-game pause menu for both KBM and gamepad players.
# Only the player who opened the menu can close it.
# ============================================================
extends Node

@export var menu_scene : PackedScene

const DEFAULT_MENU_PATH := "res://scenes/ui/GameMenu.tscn"

var _menu_instance : Control = null
var _menu_visible  : bool    = false
var _menu_device   : int     = -99   # -99 = nobody has it open


# ============================================================
# READY
# ============================================================
func _ready() -> void:
	set_process_unhandled_input(true)

	if not menu_scene and ResourceLoader.exists(DEFAULT_MENU_PATH):
		menu_scene = load(DEFAULT_MENU_PATH)
		print("[GameMenuHandler] Loaded default menu: %s" % DEFAULT_MENU_PATH)
	elif not menu_scene:
		push_warning("[GameMenuHandler] No menu_scene assigned and default not found at %s" % DEFAULT_MENU_PATH)


# ============================================================
# INPUT
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed(): return

	# KBM — ESC key
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		_toggle_menu(-1)
		get_viewport().set_input_as_handled()
		return

	# Gamepad — START button
	if event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START:
		_toggle_menu((event as InputEventJoypadButton).device)
		get_viewport().set_input_as_handled()
		return


# ============================================================
# TOGGLE
# ============================================================
func _toggle_menu(device: int) -> void:
	if _menu_visible:
		# Only the player who opened it can close it
		# KBM (device=-1) can always close
		if device != _menu_device and device != -1:
			return
		_hide_menu()
	else:
		_menu_device = device
		_show_menu()


# ============================================================
# SHOW
# ============================================================
func _show_menu() -> void:
	if not menu_scene:
		push_warning("[GameMenuHandler] No menu_scene — cannot open menu.")
		return

	# Instantiate once, reuse after
	if not is_instance_valid(_menu_instance):
		_menu_instance = menu_scene.instantiate() as Control
		if not _menu_instance:
			push_error("[GameMenuHandler] menu_scene did not instantiate as Control.")
			return
		_menu_instance.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().root.add_child(_menu_instance)

	if _menu_instance.has_method("show_in_game"):
		_menu_instance.show_in_game()
	else:
		_menu_instance.visible = true

	_menu_visible     = true
	get_tree().paused = true
	print("[GameMenuHandler] Menu opened by device=%d" % _menu_device)


# ============================================================
# HIDE
# ============================================================
func _hide_menu() -> void:
	if is_instance_valid(_menu_instance):
		if _menu_instance.has_method("hide_in_game"):
			_menu_instance.hide_in_game()
		else:
			_menu_instance.visible = false

	_menu_visible     = false
	_menu_device      = -99
	get_tree().paused = false
	print("[GameMenuHandler] Menu closed.")


# ============================================================
# PUBLIC — call from other scripts if needed
# ============================================================
func force_close() -> void:
	if _menu_visible: _hide_menu()

func is_menu_open() -> bool:
	return _menu_visible


# ============================================================
# CLEANUP
# ============================================================
func _exit_tree() -> void:
	if is_instance_valid(_menu_instance):
		_menu_instance.queue_free()
	_menu_instance = null
