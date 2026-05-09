# ============================================================
# AIPlayer.gd — Compatible with BaseZombie / ZombieHordeManager
# ============================================================
extends Node

@export var spawn_point : Node3D = null
@export var base_node   : Node3D = null

# ─────────────────────────────────────────────────────────────
# INSPECTOR OVERRIDES
# ─────────────────────────────────────────────────────────────
@export_group("Difficulty")
@export_enum("EASY:1","MEDIUM:2","HARD:3","NIGHTMARE:4") var difficulty_preset : int = 2

@export_group("AI Timing Overrides  (0 = use preset)")
@export var override_decision_interval : float = 0.0
@export var override_wave_interval     : float = 0.0
@export var override_wave_size         : int   = 0
@export var override_gold_reserve      : int   = 0

@export_group("AI Economy Overrides  (0 = use preset)")
@export var override_starting_gold      : int   = 0
@export_range(0.0, 1.0, 0.01) var override_optimality : float = 0.0
@export var override_max_upgrade_stacks : int   = 0
@export var override_max_turrets        : int   = 0

@export_group("Zombie Stat Overrides  (0 = use scene defaults)")
@export var override_zombie_health    : float = 0.0
@export var override_zombie_damage    : float = 0.0
@export var override_zombie_speed     : float = 0.0
@export var override_zombie_attack_cd : float = 0.0

@export_group("Wave Scaling")
@export var health_per_wave : float = 0.0
@export var damage_per_wave : float = 0.0

# ─────────────────────────────────────────────────────────────
# AI MODE CONSTANTS — mirrors BaseZombie enum, no class ref needed
# ─────────────────────────────────────────────────────────────
# Must match BaseZombie enum order:
# enum AIMode { FOLLOW_OWNER, ATTACK, DEFEND, PATROL, STAY, LANE_PUSH }
const AI_FOLLOW      := 0
const AI_ATTACK      := 1
const AI_DEFEND      := 2
const AI_PATROL      := 3
const AI_STAY        := 4
const AI_LANE_PUSH   := 5

# ─────────────────────────────────────────────────────────────
# DIFFICULTY TABLES
# ─────────────────────────────────────────────────────────────
const DECISION_INTERVALS : Array = [0.0, 7.0,  4.5,  2.5,  1.0 ]
const OPTIMALITY         : Array = [0.0, 0.40, 0.65, 0.82, 0.98]
const GOLD_RESERVE       : Array = [0,   400,  250,  120,  50  ]
const STARTING_GOLD      : Array = [0,  1500, 2500, 4000, 6000 ]
const LOOKAHEAD          : Array = [0,   1,    2,    3,    5   ]
const WAVE_INTERVALS     : Array = [0.0, 35.0, 22.0, 12.0, 6.0 ]
const WAVE_SIZES         : Array = [0,   2,    3,    5,    8   ]
const NM_ESCALATION_TIME     : float = 240.0
const NM_ESCALATION_INTERVAL : float = 3.5

const DPS_BALANCE_TOLERANCE : float = 0.15
const EHP_BALANCE_TOLERANCE : float = 0.20
const IDEAL_ATK_DEF_RATIO   : float = 2.0
const BASE_DANGER_THRESHOLD : float = 0.55
const TURRET_COVERAGE_RATIO : float = 2.0
const MAX_UPGRADE_STACKS    : Array = [0, 2, 4, 7, 12]
const MAX_TURRETS           : int   = 8
const TURRET_UPGRADE_EVERY  : Array = [0, 10, 6, 3, 1]
const TURRET_INNER_RADIUS   : float = 8.0
const TURRET_OUTER_RADIUS   : float = 18.0
const WAVE_DEFEND_RATIO     : Array = [0.0, 0.10, 0.20, 0.30, 0.40]

const CREEP_UPGRADES : Array = [
	{ "label": "Zombie Health +50",       "stat": "max_health",      "amount": 50,    "cost": 150, "ehp_value": 50.0, "dps_value": 0.0  },
	{ "label": "Zombie Attack Speed +5%", "stat": "attack_cooldown", "amount": -0.05, "cost": 200, "ehp_value": 0.0,  "dps_value": 0.05 },
	{ "label": "Zombie Damage +10",       "stat": "damage",          "amount": 10,    "cost": 250, "ehp_value": 0.0,  "dps_value": 10.0 },
]
const BASE_UPGRADES : Array = [
	{ "label": "Base Health +100", "amount": 100, "cost": 200 },
	{ "label": "Base Health +250", "amount": 250, "cost": 400 },
	{ "label": "Base Health +500", "amount": 500, "cost": 700 },
]

# ─────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────
var team_id    : int = 2
var difficulty : int = 2
var _wave_number : int = 0

var game_manager           : Node  = null
var _shop                  : Node  = null   # ShopUI — untyped to avoid class_name dep
var _horde_manager                 = null
var _match_started         : bool  = false
var _decision_timer        : float = 0.0
var _wave_timer            : float = 0.0
var _upgrade_counts        : Dictionary = {}
var _turrets_placed        : int   = 0
var _turrets_upgraded      : int   = 0
var _purchase_count        : int   = 0
var _phase                 : int   = 0
var _estimated_spent       : int   = 0
var _match_time            : float = 0.0
var _my_turrets            : Array = []
var _state                 : Dictionary = {}
var _hp_stacks_needed      : int   = 0
var _starting_gold_granted : bool  = false
var _my_zombies            : Array = []


# ============================================================
# SHOP ACCESS — untyped, no ShopUI class_name needed
# ============================================================
func _get_shop() -> Node:
	if is_instance_valid(_shop): return _shop
	for s in get_tree().get_nodes_in_group("shop"):
		if is_instance_valid(s): _shop = s; break
	return _shop

func _attack_scenes() -> Array:
	var s := _get_shop()
	if is_instance_valid(s) and "attack_creep_scenes" in s and not s.attack_creep_scenes.is_empty():
		return s.attack_creep_scenes
	var fallback : PackedScene = load("res://zombie/zombie.tscn")
	if is_instance_valid(fallback): return [fallback]
	return []
func _attack_costs() -> Array:
	var s := _get_shop()
	return s.attack_creep_costs  if is_instance_valid(s) and "attack_creep_costs"  in s else []
func _defend_scenes() -> Array:
	var s := _get_shop()
	if is_instance_valid(s) and "defend_creep_scenes" in s and not s.defend_creep_scenes.is_empty():
		return s.defend_creep_scenes
	# Fallback: use attack scenes if defend scenes not assigned
	if is_instance_valid(s) and "attack_creep_scenes" in s:
		return s.attack_creep_scenes
	# Last resort: use zombie.tscn directly
	var fallback : PackedScene = load("res://zombie/zombie.tscn")
	if is_instance_valid(fallback): return [fallback]
	return []
func _defend_costs() -> Array:
	var s := _get_shop()
	return s.defend_creep_costs  if is_instance_valid(s) and "defend_creep_costs"  in s else []
func _turret_scenes() -> Array:
	var s := _get_shop()
	return s.turret_scenes       if is_instance_valid(s) and "turret_scenes"       in s else []
func _turret_costs() -> Array:
	var s := _get_shop()
	return s.turret_costs        if is_instance_valid(s) and "turret_costs"        in s else []


# ============================================================
# OVERRIDE HELPERS
# ============================================================
func _decision_interval() -> float:
	var d := clampi(difficulty, 1, 4)
	return override_decision_interval if override_decision_interval > 0.0 else DECISION_INTERVALS[d]
func _wave_interval() -> float:
	var d := clampi(difficulty, 1, 4)
	return override_wave_interval if override_wave_interval > 0.0 else WAVE_INTERVALS[d]
func _wave_size() -> int:
	var d := clampi(difficulty, 1, 4)
	return override_wave_size if override_wave_size > 0 else WAVE_SIZES[d]
func _gold_reserve() -> int:
	var d := clampi(difficulty, 1, 4)
	return override_gold_reserve if override_gold_reserve > 0 else GOLD_RESERVE[d]
func _starting_gold() -> int:
	var d := clampi(difficulty, 1, 4)
	return override_starting_gold if override_starting_gold > 0 else STARTING_GOLD[d]
func _optimality() -> float:
	var d := clampi(difficulty, 1, 4)
	return override_optimality if override_optimality > 0.0 else OPTIMALITY[d]
func _max_stacks() -> int:
	var d := clampi(difficulty, 1, 4)
	return override_max_upgrade_stacks if override_max_upgrade_stacks > 0 else MAX_UPGRADE_STACKS[d]
func _max_turrets_val() -> int:
	return override_max_turrets if override_max_turrets > 0 else MAX_TURRETS


# ============================================================
# READY
# ============================================================
func _ready() -> void:
	add_to_group("ai_player")
	difficulty = difficulty_preset

	var gs := get_node_or_null("/root/GameSettings")
	if is_instance_valid(gs):
		team_id          = clampi(gs.ai_team_id, 1, 2)
		gs.ai_difficulty = difficulty
		if not gs.ai_active(): set_process(false); return
	else:
		push_warning("[AIPlayer] GameSettings not found — using defaults.")

	await get_tree().process_frame
	await get_tree().process_frame

	game_manager = get_tree().get_first_node_in_group("game_manager")
	if not is_instance_valid(game_manager):
		push_warning("[AIPlayer] No game_manager."); set_process(false); return

	if Engine.has_singleton("ZombieHordeManager"):
		_horde_manager = Engine.get_singleton("ZombieHordeManager")

	if game_manager.has_signal("match_started_signal"):
		game_manager.match_started_signal.connect(_on_match_started)

	_wave_timer = _wave_interval() * 0.5
	print("[AIPlayer] T=%d | diff=%d | horde_mgr=%s | spawn_point=%s | base_node=%s" % [
		team_id, difficulty, str(is_instance_valid(_horde_manager)),
		spawn_point.name if is_instance_valid(spawn_point) else "NONE",
		base_node.name if is_instance_valid(base_node) else "NONE"])

	await get_tree().create_timer(0.5).timeout
	_grant_starting_gold()
	await get_tree().create_timer(1.5).timeout
	_prep_phase_build()


# ============================================================
# STARTING GOLD
# ============================================================
func _grant_starting_gold() -> void:
	if _starting_gold_granted: return
	_starting_gold_granted = true
	if not is_instance_valid(game_manager): return
	var target  : int = _starting_gold()
	var current : int = game_manager.get_gold(team_id) if game_manager.has_method("get_gold") else 0
	if game_manager.has_method("set_gold"):
		game_manager.set_gold(team_id, maxi(current, target))
	else:
		var deficit : int = target - current
		if deficit > 0:
			if   game_manager.has_method("add_gold"):  game_manager.add_gold(team_id, deficit)
			elif game_manager.has_method("give_gold"): game_manager.give_gold(team_id, deficit)
	print("[AIPlayer] T%d gold → %d" % [team_id, _starting_gold()])


# ============================================================
# PROCESS
# ============================================================
func _process(delta: float) -> void:
	if not _match_started: return
	_match_time     += delta
	_decision_timer -= delta
	_wave_timer     -= delta

	if _wave_timer <= 0.0:
		var interval : float = _wave_interval()
		if difficulty == 4 and _match_time > NM_ESCALATION_TIME:
			interval = NM_ESCALATION_INTERVAL
		_wave_timer = interval
		_force_horde_wave()

	if difficulty == 4 and _match_time > 420.0:
		_decision_timer = min(_decision_timer, 0.7)

	if _decision_timer <= 0.0:
		_decision_timer = _decision_interval()
		_update_state()
		_think()

	_my_turrets = _my_turrets.filter(func(t): return is_instance_valid(t))
	_my_zombies = _my_zombies.filter(func(z): return is_instance_valid(z))


# ============================================================
# FORCED HORDE WAVE
# ============================================================
func _force_horde_wave() -> void:
	var wave_count : int   = _wave_size()
	var unit_gap   : int   = _state.get("en_unit_count", 0) - _state.get("my_unit_count", 0)
	if unit_gap > 3: wave_count = int(float(wave_count) * 1.5)

	var gold : int = game_manager.get_gold(team_id) if is_instance_valid(game_manager) else 0
	if gold < _gold_reserve(): return

	var atk_scores := _score_creep_catalogue(_attack_scenes(), _attack_costs(), "attack")
	var def_scores := _score_creep_catalogue(_defend_scenes(), _defend_costs(), "defend")
	var def_ratio  : float = WAVE_DEFEND_RATIO[clampi(difficulty, 1, 4)]
	var def_slots  : int   = int(round(float(wave_count) * def_ratio))
	var atk_slots  : int   = wave_count - def_slots

	var wave_order : Array = []
	for _a in atk_slots: wave_order.append("attack")
	for _d in def_slots: wave_order.append("defend")
	wave_order.shuffle()

	var bought_atk : int = 0
	var bought_def : int = 0
	for slot in wave_order:
		await get_tree().create_timer(randf_range(0.08, 0.35)).timeout
		if slot == "attack":
			if _buy_best_value_creep(atk_scores, "attack"): bought_atk += 1
		else:
			if _buy_best_value_creep(def_scores, "defend"): bought_def += 1

	if bought_atk + bought_def > 0:
		_wave_number += 1
		print("[AIPlayer] T%d WAVE #%d — %datk %ddef" % [team_id, _wave_number, bought_atk, bought_def])


# ============================================================
# STATE SNAPSHOT
# ============================================================
func _update_state() -> void:
	var enemy_team : int = 1 if team_id == 2 else 2
	var my_units := _get_team_units(team_id)
	var my_atk   := my_units.filter(func(u): return not u.is_in_group("towers") and not u.is_in_group("bases"))
	var my_def   := my_units.filter(func(u): return u.is_in_group("towers"))
	var en_units := _get_team_units(enemy_team)
	var en_atk   := en_units.filter(func(u): return not u.is_in_group("towers") and not u.is_in_group("bases"))

	var my_dps : float = _calc_team_dps(my_atk)
	var en_dps : float = _calc_team_dps(en_atk)
	var my_ehp : float = _calc_team_ehp(my_atk)
	var en_ehp : float = _calc_team_ehp(en_atk)

	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p) or not ("team_id" in p): continue
		if int(p.get("team_id")) != enemy_team: continue
		var php  : float = float(p.get("health")     if "health"     in p else 100.0)
		var parm : float = float(p.get("armor")       if "armor"      in p else 0.0)
		en_ehp += php * (1.0 + parm / 100.0)
		var wm = p.get("weapon_manager") if "weapon_manager" in p else null
		if is_instance_valid(wm):
			var wdmg  : float = float(wm.get("current_damage") if "current_damage" in wm else wm.get("damage") if "damage" in wm else 20.0)
			var wrate : float = float(wm.get("fire_rate")       if "fire_rate"       in wm else 0.2)
			en_dps += wdmg * (1.0 / maxf(wrate, 0.01))

	var my_ttk : float = en_ehp / maxf(my_dps, 0.01)
	var en_ttk : float = my_ehp / maxf(en_dps, 0.01)

	var en_max_single_dmg : float = 0.0
	for u in get_tree().get_nodes_in_group("units"):
		if not is_instance_valid(u) or not ("team_id" in u): continue
		if int(u.get("team_id")) != enemy_team: continue
		en_max_single_dmg = maxf(en_max_single_dmg, float(u.get("damage") if "damage" in u else 0.0))
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p) or not ("team_id" in p): continue
		if int(p.get("team_id")) != enemy_team: continue
		var wm = p.get("weapon_manager") if "weapon_manager" in p else null
		if is_instance_valid(wm):
			en_max_single_dmg = maxf(en_max_single_dmg,
				float(wm.get("current_damage") if "current_damage" in wm else wm.get("damage") if "damage" in wm else 0.0))

	var current_hp    : float = 100.0 + float(_upgrade_counts.get("max_health", 0)) * 50.0
	_hp_stacks_needed = 0
	if en_max_single_dmg > 0.0:
		var hp_needed : float = en_max_single_dmg * 1.15
		_hp_stacks_needed = maxi(0, int(ceil((hp_needed - current_hp) / 50.0)))

	var gold : int = game_manager.get_gold(team_id) if is_instance_valid(game_manager) else 0

	_state = {
		"gold":              gold,
		"my_dps":            my_dps,
		"en_dps":            en_dps,
		"my_ehp":            my_ehp,
		"en_ehp":            en_ehp,
		"my_ttk":            my_ttk,
		"en_ttk":            en_ttk,
		"my_unit_count":     my_atk.size(),
		"en_unit_count":     en_atk.size(),
		"my_def_count":      my_def.size(),
		"atk_def_ratio":     float(my_atk.size()) / maxf(float(my_def.size()), 1.0),
		"my_base_ratio":     _get_base_ratio(team_id),
		"covered_enemies":   _count_covered_enemies(),
		"dps_deficit":       en_dps - my_dps,
		"ehp_deficit":       en_ehp - my_ehp,
		"ttk_advantage":     en_ttk - my_ttk,
		"en_max_single_dmg": en_max_single_dmg,
		"hp_stacks_needed":  _hp_stacks_needed,
		"phase":             _phase,
		"match_time":        _match_time,
	}


func _get_team_units(tid: int) -> Array:
	var out : Array = []
	for u in get_tree().get_nodes_in_group("units"):
		if is_instance_valid(u) and "team_id" in u and int(u.get("team_id")) == tid:
			out.append(u)
	return out

func _calc_team_dps(units: Array) -> float:
	var total : float = 0.0
	for u in units:
		if not is_instance_valid(u): continue
		var dmg : float = float(u.get("damage")          if "damage"          in u else 0.0)
		var cd  : float = float(u.get("attack_cooldown") if "attack_cooldown" in u else 1.0)
		if cd > 0.0: total += dmg / cd
	return total

func _calc_team_ehp(units: Array) -> float:
	var total : float = 0.0
	for u in units:
		if not is_instance_valid(u): continue
		var hp  : float = float(u.get("health")     if "health"     in u else u.get("max_health") if "max_health" in u else 0.0)
		var arm : float = float(u.get("armor")      if "armor"      in u else 0.0)
		total += hp * (1.0 + arm / 100.0)
	return total

func _get_base_ratio(tid: int) -> float:
	for b in get_tree().get_nodes_in_group("bases"):
		if not ("team_id" in b) or int(b.get("team_id")) != tid: continue
		var hp    : float = float(b.get("health_value") if "health_value" in b else b.get("health") if "health" in b else b.get("current_health") if "current_health" in b else 0.0)
		var maxhp : float = float(b.get("max_health") if "max_health" in b else 1.0)
		return hp / maxhp if maxhp > 0.0 else 1.0
	return 1.0

func _count_covered_enemies() -> int:
	var count : int = 0
	for t in _my_turrets:
		if not is_instance_valid(t) or not ("target" in t): continue
		if is_instance_valid(t.target): count += 1
	return count

func _update_phase(gold: int) -> void:
	var total : int = gold + _estimated_spent
	if   total >= 5000: _phase = 3
	elif total >= 2000: _phase = 2
	elif total >= 600:  _phase = 1
	else:               _phase = 0


# ============================================================
# PREP PHASE
# ============================================================
func _prep_phase_build() -> void:
	# Wait until bases are in the scene before buying — avoids enemy=NULL on minions
	var waited := 0
	while (not is_instance_valid(_find_my_base_node()) \
			or not is_instance_valid(_find_enemy_base_node())) \
			and waited < 50:
		await get_tree().create_timer(0.1).timeout
		waited += 1

	var atk_scores := _score_creep_catalogue(_attack_scenes(), _attack_costs(), "attack")
	var def_scores := _score_creep_catalogue(_defend_scenes(), _defend_costs(), "defend")
	var start_units : int = [0, 2, 3, 5, 7][clampi(difficulty, 1, 4)]
	var start_defs  : int = [0, 1, 1, 2, 3][clampi(difficulty, 1, 4)]
	for _i in start_units:
		await get_tree().create_timer(randf_range(0.3, 0.9)).timeout
		_buy_best_value_creep(atk_scores, "attack")
	for _i in start_defs:
		await get_tree().create_timer(randf_range(0.4, 1.0)).timeout
		_buy_best_value_creep(def_scores, "defend")
	if difficulty >= 2: await get_tree().create_timer(1.5).timeout; _try_place_turret()
	if difficulty >= 3:
		await get_tree().create_timer(2.0).timeout; _try_place_turret()
		await get_tree().create_timer(1.0).timeout; _try_creep_upgrade_smart()
	if difficulty == 4:
		await get_tree().create_timer(1.5).timeout; _try_place_turret()
		await get_tree().create_timer(0.8).timeout; _try_place_turret()
		await get_tree().create_timer(0.8).timeout; _try_creep_upgrade_smart()
		await get_tree().create_timer(0.8).timeout; _try_creep_upgrade_smart()


# ============================================================
# CATALOGUE SCORING
# ============================================================
func _score_creep_catalogue(scenes: Array, costs: Array, kind: String) -> Array:
	var scores : Array = []
	for i in scenes.size():
		var scene : PackedScene = scenes[i]
		if not is_instance_valid(scene): continue
		var cost : int  = costs[i] if i < costs.size() else 1
		var inst : Node = scene.instantiate()
		var hp   : float = float(inst.get("max_health")      if "max_health"      in inst else 100.0)
		var dmg  : float = float(inst.get("damage")          if "damage"          in inst else 10.0)
		var cd   : float = float(inst.get("attack_cooldown") if "attack_cooldown" in inst else 1.2)
		var arm  : float = float(inst.get("armor")           if "armor"           in inst else 0.0)
		var spd  : float = float(inst.get("move_speed")      if "move_speed"      in inst else 4.0)
		inst.queue_free()
		var dps   : float = dmg / maxf(cd, 0.01)
		var ehp   : float = hp * (1.0 + arm / 100.0)
		var value : float = (dps * 2.0 + ehp * 0.05 + spd * 0.5) / maxf(float(cost), 1.0)
		scores.append({"index": i, "scene": scene, "cost": cost, "kind": kind,
			"dps": dps, "ehp": ehp, "value": value, "hp": hp, "dmg": dmg, "cd": cd})
	scores.sort_custom(func(a, b): return a["value"] > b["value"])
	return scores


func _buy_best_value_creep(scores: Array, kind: String) -> bool:
	if scores.is_empty(): return false
	var gold       : int   = game_manager.get_gold(team_id) if is_instance_valid(game_manager) else 0
	var affordable : Array = scores.filter(func(s): return gold >= s["cost"])
	if affordable.is_empty(): return false
	var chosen : Dictionary = affordable[0] if randf() < _optimality() else affordable[randi() % affordable.size()]
	return _buy_creep(chosen["scene"], chosen["cost"], kind)


# ============================================================
# THINK
# ============================================================
func _think() -> void:
	if not is_instance_valid(game_manager): return
	var gold : int = _state.get("gold", 0)
	_update_phase(gold)
	if gold < _gold_reserve(): return
	var need    := _evaluate_needs()
	var executed := false
	for action in need:
		match action:
			"base_upgrade":       executed = _try_base_upgrade()
			"turret_upgrade":     executed = _try_upgrade_existing_turret()
			"turret_place":       executed = _try_place_turret()
			"creep_upgrade_ehp":  executed = _try_creep_upgrade_stat("max_health")
			"creep_upgrade_dps":  executed = _try_creep_upgrade_stat("damage")
			"creep_upgrade_aspd": executed = _try_creep_upgrade_stat("attack_cooldown")
			"buy_attack":         executed = _buy_attack_smart()
			"buy_defend":         executed = _buy_defend_smart()
		if executed: break
	var lookahead : int = LOOKAHEAD[clampi(difficulty, 1, 4)]
	for _i in lookahead:
		if not executed: break
		gold = game_manager.get_gold(team_id)
		if gold < _gold_reserve(): break
		var needs2 := _evaluate_needs()
		if needs2.is_empty(): break
		for action in needs2:
			match action:
				"buy_attack": executed = _buy_attack_smart()
				"buy_defend": executed = _buy_defend_smart()
				_: executed = false
			if executed: break


# ============================================================
# EVALUATE NEEDS
# ============================================================
func _evaluate_needs() -> Array:
	var actions  : Array = []
	var gold     : int   = _state.get("gold",            0)
	var my_base  : float = _state.get("my_base_ratio",   1.0)
	var dps_def  : float = _state.get("dps_deficit",     0.0)
	var ehp_def  : float = _state.get("ehp_deficit",     0.0)
	var my_dps   : float = _state.get("my_dps",          1.0)
	var my_ehp   : float = _state.get("my_ehp",          1.0)
	var my_count : int   = _state.get("my_unit_count",   0)
	var en_count : int   = _state.get("en_unit_count",   0)
	var atk_def  : float = _state.get("atk_def_ratio",   2.0)
	var covered  : int   = _state.get("covered_enemies", 0)
	var hp_stks  : int   = _state.get("hp_stacks_needed",0)
	var cur_hp_stacks : int = _upgrade_counts.get("max_health", 0)
	var max_stacks    : int = _max_stacks()

	if hp_stks > 0 and cur_hp_stacks < mini(hp_stks, max_stacks):
		if gold >= 150: actions.append("creep_upgrade_ehp")
	if my_base < BASE_DANGER_THRESHOLD: actions.append("base_upgrade")
	if not _my_turrets.is_empty() and covered > 0 and _should_upgrade_turret():
		actions.append("turret_upgrade")
	if dps_def > my_dps * DPS_BALANCE_TOLERANCE * 2.0:
		if gold >= 250: actions.append("creep_upgrade_dps")
		for _b in mini(3, LOOKAHEAD[clampi(difficulty,1,4)] + 1): actions.append("buy_attack")
	if ehp_def > my_ehp * EHP_BALANCE_TOLERANCE * 2.0:
		if gold >= 150: actions.append("creep_upgrade_ehp")
		actions.append("buy_defend")
	var unit_gap : int = en_count - my_count
	if unit_gap > 0:
		for _u in mini(unit_gap, LOOKAHEAD[clampi(difficulty,1,4)] + 1): actions.append("buy_attack")
	if atk_def > IDEAL_ATK_DEF_RATIO * 1.5:   actions.append("buy_defend")
	elif atk_def < IDEAL_ATK_DEF_RATIO * 0.5: actions.append("buy_attack")
	if _turrets_placed < _max_turrets_val():
		var want : int = maxi(1, int(float(en_count) / TURRET_COVERAGE_RATIO))
		if _turrets_placed < want: actions.append("turret_place")
	if dps_def > 0.0 and gold >= 200: actions.append("creep_upgrade_aspd")
	if actions.is_empty() or my_count == 0:
		actions.append("buy_attack"); actions.append("buy_defend")
		if _turrets_placed < _max_turrets_val(): actions.append("turret_place")
	if randf() > _optimality(): actions.shuffle()
	return actions


# ============================================================
# SMART BUY
# ============================================================
func _buy_attack_smart() -> bool:
	return _buy_best_value_creep(_score_creep_catalogue(_attack_scenes(), _attack_costs(), "attack"), "attack")
func _buy_defend_smart() -> bool:
	return _buy_best_value_creep(_score_creep_catalogue(_defend_scenes(), _defend_costs(), "defend"), "defend")


# ============================================================
# SPAWN CREEP
# ============================================================
func _buy_creep(scene: PackedScene, cost: int, kind: String) -> bool:
	print("[AIPlayer] _buy_creep T%d | kind=%s | cost=%d" % [team_id, kind, cost])
	if not is_instance_valid(scene):
		push_warning("[AIPlayer] scene is NULL for kind=%s — assign scenes in Shop Inspector" % kind)
		return false
	if not is_instance_valid(scene) or not is_instance_valid(game_manager): return false
	if not game_manager.spend_gold(team_id, cost): return false
	_estimated_spent += cost; _purchase_count += 1

	# Try spawner first
	for s in get_tree().get_nodes_in_group("creep_spawner"):
		if not is_instance_valid(s) or not ("team_id" in s): continue
		if int(s.get("team_id")) != team_id: continue
		if not s.has_method("spawn_purchased_creep"): continue
		var creep = s.call("spawn_purchased_creep", scene, null)
		if not is_instance_valid(creep): continue
		_apply_stat_overrides(creep)
		_apply_upgrades_to_creep(creep)
		_configure_creep_for_moba(creep, kind, s)
		_my_zombies.append(creep)
		return true

	# ── FALLBACK: direct instantiate at correct spawn location ──
	var spawn_pos : Vector3 = Vector3.ZERO
	var spawn_rot : Basis   = Basis.IDENTITY

	# Priority 1: assigned spawn_point export
	if is_instance_valid(spawn_point):
		spawn_pos = spawn_point.global_position
		spawn_rot = spawn_point.global_transform.basis

	# Priority 2: creep_spawner matching OUR team_id
	if spawn_pos == Vector3.ZERO:
		for s in get_tree().get_nodes_in_group("creep_spawner"):
			if not is_instance_valid(s) or not ("team_id" in s): continue
			if int(s.get("team_id")) != team_id: continue
			if s is Node3D:
				spawn_pos = (s as Node3D).global_position
				spawn_rot = (s as Node3D).global_transform.basis
				break

	# Priority 3: our base node
	if spawn_pos == Vector3.ZERO and is_instance_valid(base_node):
		spawn_pos = base_node.global_position
		spawn_rot = base_node.global_transform.basis

	# Priority 4: scan bases group by team_id
	if spawn_pos == Vector3.ZERO:
		for b in get_tree().get_nodes_in_group("bases"):
			if not is_instance_valid(b) or not ("team_id" in b): continue
			if int(b.get("team_id")) != team_id: continue
			spawn_pos = (b as Node3D).global_position
			break

	# Formation randomness
	spawn_pos += Vector3(randf_range(-3.0, 3.0), 0.5, randf_range(-3.0, 3.0))

	var creep : Node = scene.instantiate()
	if "team_id"  in creep: creep.set("team_id",  team_id)
	if "owner_id" in creep: creep.set("owner_id", get_instance_id())
	get_tree().current_scene.add_child(creep)
	if creep is Node3D:
		(creep as Node3D).global_position = spawn_pos
	_apply_stat_overrides(creep)
	_apply_upgrades_to_creep(creep)
	_configure_creep_for_moba(creep, kind, null)
	_my_zombies.append(creep)
	print("[AIPlayer] fallback spawn T%d at %s" % [team_id, str(spawn_pos)])
	return true


# ============================================================
# MOBA LANE CONFIG — uses plain int AI mode constants
# ============================================================
func _configure_creep_for_moba(creep: Node, kind: String, spawner: Node = null) -> void:
	if not is_instance_valid(creep): return

	var my_base      : Node3D = _find_my_base_node()
	var enemy_base_n : Node3D = _find_enemy_base_node()

	if "team_id" in creep: creep.set("team_id", team_id)

	if is_instance_valid(my_base) and is_instance_valid(enemy_base_n):
		if "friendly_base" in creep: creep.set("friendly_base", my_base)
		if "enemy_base"    in creep: creep.set("enemy_base",    enemy_base_n)
	else:
		# Bases not ready — retry until found (poll every 0.2s, max 10 attempts)
		_retry_set_bases(creep, 0)

	if kind == "attack":
		var lane_id   : int   = randi_range(0, 2)
		var waypoints : Array = _get_real_lane_waypoints(lane_id)
		if not waypoints.is_empty() and creep.has_method("set_lane"):
			var march_wps : Array = waypoints.slice(1) if waypoints.size() > 1 else waypoints
			creep.set_lane(march_wps, lane_id)
		elif creep.has_method("set_ai_mode"):
			creep.set_ai_mode(AI_LANE_PUSH)
		if "owner_player" in creep: creep.set("owner_player", null)
	else:
		if creep.has_method("set_ai_mode"): creep.set_ai_mode(AI_DEFEND)
		if "owner_player" in creep: creep.set("owner_player", null)
		if is_instance_valid(my_base) and creep.has_method("set_move_target"):
			creep.set_move_target(my_base.global_position)

func _retry_set_bases(creep: Node, attempt: int) -> void:
	if not is_instance_valid(creep): return
	var mb : Node3D = _find_my_base_node()
	var eb : Node3D = _find_enemy_base_node()
	if is_instance_valid(mb) and is_instance_valid(eb):
		if "team_id"       in creep: creep.set("team_id",       team_id)
		if "friendly_base" in creep: creep.set("friendly_base", mb)
		if "enemy_base"    in creep: creep.set("enemy_base",    eb)
	elif attempt < 10:
		get_tree().create_timer(0.2).timeout.connect(
			func(): _retry_set_bases(creep, attempt + 1), CONNECT_ONE_SHOT)


func _find_my_base_node() -> Node3D:
	if is_instance_valid(base_node): return base_node as Node3D
	for b in get_tree().get_nodes_in_group("bases"):
		if is_instance_valid(b) and "team_id" in b and int(b.get("team_id")) == team_id:
			return b as Node3D
	return null


func _get_lane_for_position(pos: Vector3) -> int:
	if pos.x < -15 and pos.z < -10: return 1
	if pos.x < -15 and pos.z > 10:  return 3
	return 2


func _get_lane_waypoints(lane_id: int) -> Array:
	return _get_real_lane_waypoints(lane_id)

func _get_real_lane_waypoints(lane_id: int) -> Array:
	# Pull from LaneSpawner which computed paths from real base positions
	var ls := get_tree().get_first_node_in_group("lane_spawner")
	if is_instance_valid(ls) and ls.has_method("get_lane_waypoints"):
		var wps : Array = ls.get_lane_waypoints(team_id, lane_id)
		if not wps.is_empty(): return wps
	# LaneSpawner not ready yet — build path from actual base positions directly
	var my_b : Node3D = _find_my_base_node()
	var en_b : Node3D = _find_enemy_base_node()
	if is_instance_valid(my_b) and is_instance_valid(en_b):
		var start : Vector3 = my_b.global_position
		var goal  : Vector3 = en_b.global_position
		var axis  : Vector3 = (goal - start); axis.y = 0.0
		var perp  : Vector3 = Vector3(-axis.normalized().z, 0.0, axis.normalized().x)
		var offset: float   = randf_range(-8.0, 8.0)
		var mid   : Vector3 = start.lerp(goal, 0.5) + perp * offset
		# 7-point path matching LaneSpawner format
		var pts : Array = []
		for i in range(7):
			var t : float = float(i) / 6.0
			var p0 := start.lerp(mid, t)
			var p1 := mid.lerp(goal, t)
			pts.append(p0.lerp(p1, t))
		return pts
	return []


func _find_enemy_base_node() -> Node3D:
	var enemy_team : int = 1 if team_id == 2 else 2
	for b in get_tree().get_nodes_in_group("bases"):
		if is_instance_valid(b) and "team_id" in b and int(b.get("team_id")) == enemy_team:
			return b as Node3D
	return null


# ============================================================
# CREEP UPGRADES
# ============================================================
func _try_creep_upgrade_smart() -> bool:
	var dps_def : float = _state.get("dps_deficit",      0.0)
	var ehp_def : float = _state.get("ehp_deficit",      0.0)
	var hp_stks : int   = _state.get("hp_stacks_needed", 0)
	if hp_stks > 0 and _upgrade_counts.get("max_health", 0) < hp_stks:
		if _try_creep_upgrade_stat("max_health"): return true
	if dps_def > ehp_def:
		if _try_creep_upgrade_stat("damage"):          return true
		if _try_creep_upgrade_stat("attack_cooldown"): return true
		return _try_creep_upgrade_stat("max_health")
	else:
		if _try_creep_upgrade_stat("max_health"): return true
		return _try_creep_upgrade_stat("damage")


func _try_creep_upgrade_stat(stat: String) -> bool:
	if _upgrade_counts.get(stat, 0) >= _max_stacks(): return false
	for upg in CREEP_UPGRADES:
		if upg["stat"] != stat: continue
		if not is_instance_valid(game_manager): return false
		if game_manager.get_gold(team_id) < upg["cost"]: return false
		if not game_manager.spend_gold(team_id, upg["cost"]): return false
		_estimated_spent += upg["cost"]
		_upgrade_counts[stat] = _upgrade_counts.get(stat, 0) + 1
		var upg_data : Dictionary = upg.duplicate()
		upg_data["team_id"] = team_id
		if game_manager.has_method("add_creep_upgrade"):
			game_manager.add_creep_upgrade(team_id, upg_data)
		_apply_upgrade_to_all_live(stat, upg["amount"])
		print("[AIPlayer] T%d upgrade: %s (stack %d)" % [team_id, upg["label"], _upgrade_counts[stat]])
		return true
	return false


func _apply_upgrades_to_creep(creep: Node) -> void:
	for stat in _upgrade_counts:
		for upg in CREEP_UPGRADES:
			if upg["stat"] == stat:
				for _i in _upgrade_counts[stat]: _apply_one_upgrade(creep, stat, upg["amount"])
				break


func _apply_upgrade_to_all_live(stat: String, amount: float) -> void:
	for z in _my_zombies:
		if is_instance_valid(z): _apply_one_upgrade(z, stat, amount)


func _apply_one_upgrade(creep: Node, stat: String, amount: float) -> void:
	if creep.has_method("apply_upgrade"): creep.apply_upgrade(stat, amount); return
	match stat:
		"max_health":
			if "max_health" in creep: creep.set("max_health", float(creep.get("max_health")) + amount)
			if "health"     in creep: creep.set("health", minf(float(creep.get("health")) + amount, float(creep.get("max_health"))))
		"damage":
			if "damage" in creep: creep.set("damage", float(creep.get("damage")) + amount)
		"attack_cooldown":
			if "attack_cooldown" in creep: creep.set("attack_cooldown", maxf(0.3, float(creep.get("attack_cooldown")) + amount))


func _apply_stat_overrides(creep: Node) -> void:
	if override_zombie_health > 0.0:
		if "max_health" in creep: creep.set("max_health", override_zombie_health)
		if "health"     in creep: creep.set("health",     override_zombie_health)
	if override_zombie_damage > 0.0:
		if "damage"     in creep: creep.set("damage",     override_zombie_damage)
	if override_zombie_speed > 0.0:
		if "move_speed" in creep: creep.set("move_speed", override_zombie_speed)
	if override_zombie_attack_cd > 0.0:
		if "attack_cooldown" in creep: creep.set("attack_cooldown", override_zombie_attack_cd)
	if _wave_number > 0:
		if health_per_wave > 0.0:
			var bonus : float = health_per_wave * _wave_number
			if "max_health" in creep: creep.set("max_health", float(creep.get("max_health")) + bonus)
			if "health"     in creep: creep.set("health", minf(float(creep.get("health")) + bonus, float(creep.get("max_health"))))
		if damage_per_wave > 0.0:
			if "damage" in creep: creep.set("damage", float(creep.get("damage")) + damage_per_wave * _wave_number)


# ============================================================
# BASE UPGRADES
# ============================================================
func _try_base_upgrade() -> bool:
	for upg in BASE_UPGRADES:
		if not game_manager.spend_gold(team_id, upg["cost"]): continue
		_estimated_spent += upg["cost"]
		if is_instance_valid(base_node):
			if   base_node.has_method("add_health"): base_node.add_health(upg["amount"])
			elif "max_health" in base_node:           base_node.set("max_health", float(base_node.get("max_health")) + upg["amount"])
		return true
	return false


# ============================================================
# TURRET PLACEMENT
# ============================================================
func _try_place_turret() -> bool:
	var scenes := _turret_scenes(); var costs := _turret_costs()
	if scenes.is_empty() or not is_instance_valid(base_node): return false
	var gold : int = game_manager.get_gold(team_id)
	var affordable : Array = []
	for i in scenes.size():
		var c : int = costs[i] if i < costs.size() else 500
		if gold >= c: affordable.append(i)
	if affordable.is_empty(): return false

	var best_idx : int = -1; var best_val : float = -1.0
	if randf() < _optimality():
		for i in affordable:
			var inst : Node = scenes[i].instantiate()
			var dmg  : float = float(inst.get("base_damage") if "base_damage" in inst else inst.get("damage") if "damage" in inst else 10.0)
			var rate : float = float(inst.get("fire_rate")   if "fire_rate"   in inst else 1.0)
			var rng  : float = float(inst.get("range")       if "range"       in inst else 10.0)
			var c    : int   = costs[i] if i < costs.size() else 500
			var val  : float = (dmg / maxf(rate,0.01) * rng) / maxf(float(c),1.0)
			inst.queue_free()
			if val > best_val: best_val = val; best_idx = i
	else:
		best_idx = affordable[randi() % affordable.size()]

	if best_idx < 0: return false
	var best_cost : int = costs[best_idx] if best_idx < costs.size() else 500
	if not game_manager.spend_gold(team_id, best_cost): return false
	_estimated_spent += best_cost

	var inst := scenes[best_idx].instantiate() as Node3D
	if not inst: return false
	get_tree().current_scene.add_child(inst)

	var base_pos    : Vector3 = base_node.global_position
	var forward_dir : Vector3 = Vector3.FORWARD
	var enemy_team  : int     = 1 if team_id == 2 else 2
	for b in get_tree().get_nodes_in_group("bases"):
		if not ("team_id" in b) or int(b.get("team_id")) != enemy_team: continue
		if b is Node3D:
			var dv : Vector3 = (b as Node3D).global_position - base_pos
			if dv.length() > 0.1: forward_dir = dv.normalized()
		break

	var is_inner : bool  = _turrets_placed < (MAX_TURRETS / 2)
	var radius   : float = (TURRET_INNER_RADIUS if is_inner else TURRET_OUTER_RADIUS) + randf_range(-1.5, 1.5)
	var slot     : int   = _turrets_placed % (MAX_TURRETS / 2)
	var t_val    : float = float(slot) / maxf(float(MAX_TURRETS / 2 - 1), 1.0)
	var angle    : float = lerp(-deg_to_rad(100.0), deg_to_rad(100.0), t_val) + randf_range(-0.15, 0.15)
	inst.global_position = base_pos + (Basis(Vector3.UP, angle) * forward_dir) * radius
	if "team_id"  in inst: inst.set("team_id",  team_id)
	if "owner_id" in inst: inst.set("owner_id", get_instance_id())

	_my_turrets.append(inst); _turrets_placed += 1; _purchase_count += 1
	return true


func _should_upgrade_turret() -> bool:
	var every : int = TURRET_UPGRADE_EVERY[clampi(difficulty, 1, 4)]
	return every > 0 and _purchase_count > 0 and _purchase_count % every == 0

func _try_upgrade_existing_turret() -> bool:
	for t in _my_turrets:
		if not is_instance_valid(t): continue
		if not t.has_method("upgrade") or not t.has_method("get_upgrade_cost"): continue
		var cost : int = t.get_upgrade_cost()
		if game_manager.get_gold(team_id) >= cost and game_manager.spend_gold(team_id, cost):
			_estimated_spent += cost; t.upgrade(); _turrets_upgraded += 1; return true
	return false


# ============================================================
# MATCH EVENTS
# ============================================================
func _on_match_started() -> void:
	if _match_started: return
	_match_started  = true
	_match_time     = 0.0
	_decision_timer = _decision_interval()
	_wave_timer     = _wave_interval() * 0.5
	_grant_starting_gold()
	_update_state()
	print("[AIPlayer] T%d match started | diff=%d" % [team_id, difficulty])


func set_difficulty(d: int) -> void:
	difficulty = clampi(d, 1, 4)
	var gs := get_node_or_null("/root/GameSettings")
	if is_instance_valid(gs): gs.ai_difficulty = difficulty

func scale_to_score_gap(human_gold: int, ai_gold: int) -> void:
	var gap : int = human_gold - ai_gold
	if gap > 1000 and difficulty < 4:    set_difficulty(difficulty + 1)
	elif gap < -600 and difficulty > 1: set_difficulty(difficulty - 1)
