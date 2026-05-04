extends Node
class_name HealthComponent

# ===============================
# SIGNALS
# ===============================
signal health_changed(current: float, maximum: float)
signal died

# ===============================
# STATS
# ===============================
@export var max_health: float = 100.0
var health: float = 0.0
var is_dead: bool = false

# ===============================
# READY
# ===============================
func _ready() -> void:
	reset_to_max()

# ===============================
# DAMAGE
# ===============================
func take_damage(amount: float) -> void:
	if amount <= 0:
		return

	# 🔥 Allow damage even if flagged dead but health > 0 (safety)
	if is_dead and health > 0:
		is_dead = false

	health -= amount
	health = clamp(health, 0.0, max_health)

	_emit_health()

	if health <= 0.0:
		_die()

# ===============================
# HEAL
# ===============================
func heal(amount: float) -> void:
	if amount <= 0 or is_dead:
		return

	health += amount
	health = clamp(health, 0.0, max_health)

	_emit_health()

# ===============================
# DEATH
# ===============================
func _die() -> void:
	if is_dead:
		return

	is_dead = true
	health = 0.0

	_emit_health()
	died.emit()

# ===============================
# RESET (CRITICAL FIX)
# ===============================
func reset_to_max() -> void:
	is_dead = false
	health = max_health

	_emit_health()

# ===============================
# INTERNAL
# ===============================
func _emit_health():
	health_changed.emit(health, max_health)

# ===============================
# UTIL
# ===============================
func is_alive() -> bool:
	return not is_dead
