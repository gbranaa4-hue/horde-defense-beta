# ============================================================
# AbilityComponent.gd
# Owns ability slots, cooldowns, effects
# ============================================================
extends ActorComponent
class_name AbilityComponent

var ability_slots     : Array        = [null, null, null]
var ability_cooldowns : Array[float] = [0.0, 0.0, 0.0]

# Active effect timers
var _rapid_fire_timer    : float = 0.0
var _double_damage_timer : float = 0.0
var _shield_timer        : float = 0.0
var _ghost_timer         : float = 0.0
var _sprint_boost_timer  : float = 0.0
var _berserk_timer       : float = 0.0

signal abilities_changed

func _ready() -> void:
	initialize(get_parent() as CharacterBody3D)


func tick(delta: float) -> void:
	_tick_cooldowns(delta)
	_tick_effects(delta)

func _tick_cooldowns(delta: float) -> void:
	for i in 3:
		if ability_cooldowns[i] > 0.0:
			ability_cooldowns[i] = maxf(0.0, ability_cooldowns[i] - delta)
			if ability_cooldowns[i] == 0.0: abilities_changed.emit()

func _tick_effects(delta: float) -> void:
	_rapid_fire_timer    = maxf(0.0, _rapid_fire_timer    - delta)
	_double_damage_timer = maxf(0.0, _double_damage_timer - delta)
	_shield_timer        = maxf(0.0, _shield_timer        - delta)
	_berserk_timer       = maxf(0.0, _berserk_timer       - delta)
	_sprint_boost_timer  = maxf(0.0, _sprint_boost_timer  - delta)
	_ghost_timer         = maxf(0.0, _ghost_timer         - delta)


func equip_ability(slot: int, data: Dictionary) -> void:
	if slot < 0 or slot >= 3: return
	ability_slots[slot] = data if not data.is_empty() else null
	ability_cooldowns[slot] = 0.0
	abilities_changed.emit()

func activate_ability(slot: int) -> void:
	if slot < 0 or slot >= 3: return
	var data = ability_slots[slot]
	if data == null or ability_cooldowns[slot] > 0.0: return
	ability_cooldowns[slot] = float(data.get("cooldown", 10.0))
	_trigger(data)
	abilities_changed.emit()

func _trigger(data: Dictionary) -> void:
	var id  : String = str(data.get("id", ""))
	var dur : float  = data.get("duration", 0.0)
	var amt : float  = data.get("amount",   0.0)
	var dist: float  = data.get("distance", 8.0)
	match id:
		"rapid_fire","frenzy","fire_weapon","frost_weapon","shock_weapon":
			_rapid_fire_timer = dur
		"double_damage","death_mark","crit_strike","execute":
			_double_damage_timer = dur
		"berserker":
			_berserk_timer = dur
		"void_shield","iron_skin","stone_skin","reflect","frost_armor","evasion","second_wind","cleanse":
			_shield_timer = dur
		"camouflage","phase_shift":
			_ghost_timer = dur
		"regen_aura","overclock","sprint","wind_walk","haste":
			_sprint_boost_timer = dur
			if id == "haste": _rapid_fire_timer = dur
		"blood_rite","soul_drain","energy_shield":
			# Forward to health component
			var hc := actor.get_node_or_null("HealthComponent") as HealthComponent
			if is_instance_valid(hc): hc.heal(amt)
		"void_dash","shadow_step","blink":
			var d := Vector3(actor.velocity.x, 0, actor.velocity.z).normalized()
			if d.length_squared() < 0.1: d = -actor.global_transform.basis.z
			actor.global_position += d * dist
	abilities_changed.emit()


# ── State queries ─────────────────────────────────────────────
func is_rapid_fire()    -> bool: return _rapid_fire_timer    > 0.0
func is_double_damage() -> bool: return _double_damage_timer > 0.0 or _berserk_timer > 0.0
func is_shielded()      -> bool: return _shield_timer        > 0.0
func get_damage_multiplier()    -> float: return 2.0 if is_double_damage() else 1.0
func get_fire_rate_multiplier() -> float:
	var m := 1.0
	if is_rapid_fire():        m *= 2.5
	if _berserk_timer > 0.0:   m *= 1.8
	return m
func get_speed_multiplier() -> float:
	var m := 1.0
	if _sprint_boost_timer > 0.0: m *= 1.4
	if _berserk_timer      > 0.0: m *= 1.6
	return m
