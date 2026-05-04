## ═══════════════════════════════════════════════════════════
##  CREEP TYPES — Special abilities for the Horde
##  All extend DefenseCreep (which extends Zombie)
##  Each has a unique passive + active/triggered ability
## ═══════════════════════════════════════════════════════════

# ---------------------------------------------------------------
# 🪨 TANK CREEP — High HP, taunts nearby enemies onto itself
#    Ability: TAUNT — forces all enemies in radius to target Tank
# ---------------------------------------------------------------
extends DefenseCreep
class_name TankCreep

@export var taunt_radius: float     = 6.0
@export var taunt_cooldown: float   = 8.0
@export var taunt_duration: float   = 3.0

var _taunt_timer: float = 0.0

func _ready() -> void:
	max_health    = 300.0
	move_speed    = 1.8
	damage        = 8.0
	attack_range  = 2.2
	gold_reward   = 40
	separation_distance = 1.6
	super._ready()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_taunt_timer -= delta
	if _taunt_timer <= 0.0 and state != State.DEAD:
		_do_taunt()
		_taunt_timer = taunt_cooldown

func _do_taunt() -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if not (u is Node3D) or _is_friendly(u):
			continue
		if not u.has_method("set_forced_target"):
			continue
		var dist: float = global_position.distance_to((u as Node3D).global_position)
		if dist <= taunt_radius:
			u.set_forced_target(self, taunt_duration)
	# Visual cue — override in scene with particle/shader
	_play_taunt_vfx()

func set_forced_target(new_target: Node3D, duration: float) -> void:
	target = new_target
	target_lock_timer = duration
	state = State.CHASE

func _play_taunt_vfx() -> void:
	# Hook: emit a signal or trigger a GPUParticles3D child named "TauntVFX"
	var vfx := get_node_or_null("TauntVFX")
	if vfx and vfx.has_method("restart"):
		vfx.restart()


# ---------------------------------------------------------------
# 🔥 BERSERKER CREEP — Gets faster and stronger as HP drops
#    Ability: BLOODRAGE — below 40% HP, double attack speed + damage
# ---------------------------------------------------------------
#extends DefenseCreep
#class_name BerserkerCreep

# Uncomment and use as separate file. Shown inline for reference:
#
# @export var rage_threshold: float = 0.4
# var _raging: bool = false
# func _ready() -> void:
# 	max_health = 120.0; damage = 18.0; move_speed = 3.2; gold_reward = 35
# 	super._ready()
# func take_damage(amount: float, instigator: Node = null) -> void:
# 	super.take_damage(amount, instigator)
# 	var hp_pct: float = health / max_health
# 	if hp_pct < rage_threshold and not _raging:
# 		_raging = true
# 		attack_cooldown *= 0.5
# 		damage *= 2.0
# 		move_speed *= 1.4
# 		_play_rage_vfx()
# func _play_rage_vfx() -> void:
# 	var vfx := get_node_or_null("RageVFX")
# 	if vfx: vfx.set("emitting", true)
