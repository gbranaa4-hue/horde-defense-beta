extends Node3D
class_name Base

# ===============================
# EXPORTS
# ===============================
@export var team_id      : int   = 1
@export var attack_radius: float = 3.0
@export var debug_damage : bool  = false

# ===============================
# COMPONENTS
# ===============================
@onready var health : Node = $HealthComponent

# ===============================
# SIGNALS
# ===============================
signal health_changed(current: float, max: float)
signal died

# ===============================
# READY
# ===============================
func _ready() -> void:
	add_to_group("bases")
	add_to_group("units")
	if not is_instance_valid(health):
		push_error("[Base:%s] Missing HealthComponent!" % name)
		return
	_connect_signals()
	_emit_health()

# ===============================
# SIGNAL CONNECTIONS
# ===============================
func _connect_signals() -> void:
	if health.has_signal("health_changed") and not health.health_changed.is_connected(_on_health_changed):
		health.health_changed.connect(_on_health_changed)
	if health.has_signal("died") and not health.died.is_connected(_on_died):
		health.died.connect(_on_died)

# ===============================
# HEALTH BRIDGE
# ===============================
func _on_health_changed(current: float, max_val: float) -> void:
	health_changed.emit(current, max_val)

func _emit_health() -> void:
	if is_instance_valid(health) and "health" in health and "max_health" in health:
		health_changed.emit(health.health, health.max_health)

# Expose health/max_health directly so HUD polling works
var health_value : float:
	get: return health.health if is_instance_valid(health) and "health" in health else 0.0

var max_health : float:
	get: return health.max_health if is_instance_valid(health) and "max_health" in health else 0.0

# ===============================
# DAMAGE
# ===============================
func take_damage(amount: float, attacker: Node = null, _knockback: Vector3 = Vector3.ZERO) -> void:
	if not is_instance_valid(health) or amount <= 0:
		return

	if attacker != null:
		var attacker_team := -999
		if "team_id" in attacker:
			attacker_team = attacker.team_id
		elif attacker.has_method("get_team_id"):
			attacker_team = attacker.get_team_id()

		if attacker_team == team_id:
			if debug_damage:
				print("[Base] Friendly fire blocked from: ", attacker.name)
			return

		if debug_damage:
			print("[Base] Damage: ", amount, " from: ", attacker.name)
	else:
		if debug_damage:
			print("[Base] Unknown damage source: ", amount)

	if health.has_method("take_damage"):
		health.take_damage(amount)

# ===============================
# DEATH
# ===============================
func _on_died() -> void:
	if debug_damage:
		print("[Base:%s] Destroyed (Team %d)" % [name, team_id])
	died.emit()
	get_tree().paused = true
	await get_tree().create_timer(1.0).timeout
	get_tree().paused = false
	get_tree().reload_current_scene()
