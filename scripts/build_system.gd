extends Control

var selected_turret: Node3D = null
var gm: Node = null
var can_use_hotkeys: bool = false


# UI nodes
@onready var level_label: Label = $LevelLabel
@onready var damage_label: Label = $DamageLabel
@onready var fire_rate_label: Label = $FireRateLabel
@onready var cost_label: Label = $CostLabel
@onready var hint_label: Label = $HintLabel

@onready var upgrade_button: Button = $UpgradeButton
@onready var close_button: Button = $CloseButton


func _ready() -> void:
	
	add_to_group("ui")
	visible = false

	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	add_to_group("ui")
	visible = false

	gm = get_node_or_null("/root/GameManager")
	if gm == null:
		push_error("GameManager not found!")

	if upgrade_button:
		upgrade_button.pressed.connect(_on_upgrade)
	else:
		push_error("UpgradeButton not found!")

	if close_button:
		close_button.pressed.connect(_on_close)
	else:
		push_error("CloseButton not found!")


# Open UI for a turret
func open(turret: Node3D) -> void:
	if turret == null:
		return

	selected_turret = turret
	visible = true
	can_use_hotkeys = true

	if hint_label:
		hint_label.text = "Press F to upgrade"

	_update_ui()


# Update UI values
func _update_ui() -> void:
	if selected_turret == null:
		_close_internal()
		return

	level_label.text = "Level: %d" % selected_turret.level
	damage_label.text = "Damage: %d" % selected_turret.damage
	fire_rate_label.text = "Fire Rate: %.2f" % selected_turret.fire_rate
	cost_label.text = "Upgrade Cost: %d" % selected_turret.upgrade_cost

	if gm:
		upgrade_button.disabled = not gm.can_afford(selected_turret.upgrade_cost)


# Upgrade logic (safe)
func _on_upgrade() -> void:
	if selected_turret == null or gm == null:
		return

	var cost: int = selected_turret.upgrade_cost

	if gm.can_afford(cost):
		if gm.spend_money(cost):
			selected_turret.upgrade()
			_update_ui()
		else:
			print("Upgrade failed: spend_money() returned false")
	else:
		print("Not enough money!")


# Close button
func _on_close() -> void:
	_close_internal()


func _close_internal() -> void:
	selected_turret = null
	visible = false
	can_use_hotkeys = false

	if hint_label:
		hint_label.text = ""


# Hotkey input (ONLY when UI is open)
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		print("KEY:", event.keycode)

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			_on_upgrade()
		elif event.keycode == KEY_ESCAPE:
			_close_internal()
