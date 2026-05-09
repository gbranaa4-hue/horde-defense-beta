# ============================================================
# TrinketSpawner.gd
# ============================================================
# Spawns trinkets with proper ability_data that matches the
# ability pools so TalentTree.on_trinket_collected() saves
# the pickup permanently.
#
# Drop rates:
#   • 3 base trinkets spawn near each base at game start
#   • Enemy zombies drop on death: 8% chance, 20s cooldown
#   • Tier 2 drops: after 3 min    Tier 3: after 7 min
#   • Higher tiers weighted rarer (8:4:2:1)
#   • Max 15 trinkets on ground at once
# ============================================================
extends Node

@export var trinket_scene       : PackedScene
@export var spawn_radius        : float = 8.0
@export var drop_chance         : float = 0.08
@export var max_trinkets_alive  : int   = 15
@export var drop_cooldown       : float = 20.0

const TRINKET_SCENE_PATH := "res://scenes/TrinketPickup.tscn"

# Playtime (seconds) before each tier can drop
const TIER_UNLOCK_TIME : Array[float] = [0.0, 0.0, 180.0, 420.0]

# ── Ability pools — MUST match TalentTree / shop pools exactly ──
const ATTACK_POOL : Array = [
	{"id":"rapid_fire",   "name":"⚡ Rapid Fire",       "slot":0,"tier":0,"cooldown":120.0,"duration":8.0,  "desc":"Fire rate x2.5 for 8s."},
	{"id":"frenzy",       "name":"⚡ Frenzy",           "slot":0,"tier":0,"cooldown":100.0,"duration":6.0,  "desc":"Rapid fire burst for 6s."},
	{"id":"double_damage","name":"💀 Death Mark",       "slot":0,"tier":1,"cooldown":150.0,"duration":10.0, "desc":"Deal 2x damage for 10s."},
	{"id":"berserker",    "name":"🔥 Berserker",        "slot":0,"tier":1,"cooldown":130.0,"duration":8.0,  "desc":"Fire x1.8 move x1.6 for 8s."},
	{"id":"fire_weapon",  "name":"🔥 Fire Weapon",      "slot":0,"tier":2,"cooldown":125.0,"duration":9.0,  "desc":"Burning shots for 9s."},
	{"id":"explosive",    "name":"💥 Explosive Rounds", "slot":0,"tier":2,"cooldown":145.0,"duration":7.0,  "desc":"Bullets explode on hit."},
	{"id":"vampiric",     "name":"🩸 Vampiric Strike",  "slot":0,"tier":3,"cooldown":135.0,"duration":8.0,  "desc":"Heal 30pct damage dealt for 8s."},
	{"id":"execute",      "name":"☠ Execute",           "slot":0,"tier":3,"cooldown":160.0,"duration":5.0,  "desc":"Instantly kill enemies below 25pct HP."},
]
const DEFENSE_POOL : Array = [
	{"id":"void_shield",  "name":"🔵 Void Shield",      "slot":1,"tier":0,"cooldown":90.0, "duration":6.0,  "desc":"Full damage immunity 6s."},
	{"id":"blood_rite",   "name":"💚 Blood Rite",        "slot":1,"tier":0,"cooldown":80.0, "amount":60.0,   "desc":"Restore 60 HP instantly."},
	{"id":"iron_skin",    "name":"🪨 Iron Skin",         "slot":1,"tier":1,"cooldown":110.0,"duration":12.0, "desc":"Take 60pct less damage for 12s."},
	{"id":"energy_shield","name":"🔵 Energy Shield",     "slot":1,"tier":1,"cooldown":105.0,"amount":75.0,   "desc":"Gain 75 temporary HP."},
	{"id":"reflect",      "name":"🔄 Mirror Guard",      "slot":1,"tier":2,"cooldown":120.0,"duration":7.0,  "desc":"Reflect 100pct damage for 7s."},
	{"id":"frost_armor",  "name":"❄ Frost Armor",        "slot":1,"tier":2,"cooldown":115.0,"duration":10.0, "desc":"Attackers slowed 60pct."},
	{"id":"second_wind",  "name":"💨 Second Wind",       "slot":1,"tier":3,"cooldown":180.0,"duration":0.0,  "desc":"Auto-revive once at 30pct HP."},
	{"id":"camouflage",   "name":"🌿 Camouflage",        "slot":1,"tier":3,"cooldown":90.0, "duration":12.0, "desc":"Hard to see for 12s."},
]
const MOTION_POOL : Array = [
	{"id":"void_dash",   "name":"💨 Void Dash",   "slot":2,"tier":0,"cooldown":60.0, "distance":8.0,  "desc":"Dash forward 8m."},
	{"id":"phase_shift", "name":"👻 Phase Shift", "slot":2,"tier":0,"cooldown":75.0, "duration":5.0,  "desc":"Semi-transparent 5s."},
	{"id":"overclock",   "name":"🌀 Overclock",   "slot":2,"tier":1,"cooldown":90.0, "duration":6.0,  "desc":"Speed x1.3 for 6s."},
	{"id":"blink",       "name":"✨ Blink",        "slot":2,"tier":1,"cooldown":70.0, "distance":12.0, "desc":"Teleport 12m forward."},
	{"id":"sprint",      "name":"🏃 Sprint",       "slot":2,"tier":2,"cooldown":80.0, "duration":5.0,  "desc":"Speed x1.6 for 5s."},
	{"id":"haste",       "name":"⚡ Haste",        "slot":2,"tier":2,"cooldown":110.0,"duration":4.0,  "desc":"Speed x1.8 + fire x1.5 for 4s."},
	{"id":"evasion",     "name":"🎭 Evasion",      "slot":2,"tier":3,"cooldown":85.0, "duration":6.0,  "desc":"50pct dodge for 6s."},
	{"id":"double_jump", "name":"🦘 Double Jump",  "slot":2,"tier":3,"cooldown":40.0, "duration":20.0, "desc":"Double jump for 20s."},
]

var _spawned_count  : int   = 0
var _match_time     : float = 0.0
var _last_drop_time : float = -999.0
var _did_base_spawn : bool  = false


func _ready() -> void:
	add_to_group("trinket_spawner")
	if not trinket_scene:
		var s := load(TRINKET_SCENE_PATH)
		if s: trinket_scene = s
	await get_tree().process_frame
	await get_tree().process_frame
	_base_spawn()


func _process(delta: float) -> void:
	_match_time += delta


# ── 3 tier-0 trinkets per team at game start ─────────────────
func _base_spawn() -> void:
	if _did_base_spawn: return
	_did_base_spawn = true
	var pools : Array = [ATTACK_POOL, DEFENSE_POOL, MOTION_POOL]
	for b in get_tree().get_nodes_in_group("bases"):
		if not is_instance_valid(b): continue
		var origin : Vector3 = (b as Node3D).global_position
		var tid    : int     = int(b.get("team_id") if "team_id" in b else 1)
		for slot_idx in 3:
			var tier0 : Array = pools[slot_idx].filter(func(a): return a.get("tier",0) == 0)
			if tier0.is_empty(): continue
			var data : Dictionary = tier0[randi() % tier0.size()].duplicate()
			var angle : float = float(slot_idx) / 3.0 * TAU
			var pos   : Vector3 = origin + Vector3(cos(angle)*spawn_radius, 0.4, sin(angle)*spawn_radius)
			_spawn_trinket(data, tid, pos)


# ── Called by BaseZombie._award_gold() on death ───────────────
func on_zombie_died(zombie: Node, killing_team: int) -> void:
	if _spawned_count >= max_trinkets_alive: return
	if _match_time - _last_drop_time < drop_cooldown: return
	if randf() > drop_chance: return
	if not is_instance_valid(zombie): return
	var pos : Vector3 = (zombie as Node3D).global_position if zombie is Node3D else Vector3.ZERO
	if pos == Vector3.ZERO: return

	# Tier gating by match time
	var max_tier : int = 0
	for t in range(TIER_UNLOCK_TIME.size() - 1, -1, -1):
		if _match_time >= TIER_UNLOCK_TIME[t]: max_tier = t; break

	# Random slot, weighted tier
	var pools   : Array = [ATTACK_POOL, DEFENSE_POOL, MOTION_POOL]
	var slot    : int   = randi() % 3
	var options : Array = pools[slot].filter(func(a): return int(a.get("tier",0)) <= max_tier)
	if options.is_empty(): return

	# Weight lower tiers more heavily
	var weighted : Array = []
	for a in options:
		var w : int = [8, 4, 2, 1][clampi(int(a.get("tier",0)), 0, 3)]
		for _i in w: weighted.append(a)

	var data : Dictionary = weighted[randi() % weighted.size()].duplicate()
	var offset := Vector3(randf_range(-0.8,0.8), 0.4, randf_range(-0.8,0.8))
	_spawn_trinket(data, killing_team, pos + offset)
	_last_drop_time = _match_time


# ── Core spawn ────────────────────────────────────────────────
func _spawn_trinket(data: Dictionary, tid: int, pos: Vector3) -> void:
	if not is_instance_valid(trinket_scene): return
	var node : Node3D = trinket_scene.instantiate() as Node3D
	if not is_instance_valid(node): return

	# TrinketPickup expects ability_data and team_id
	if node.has_method("setup"):
		node.setup(data, tid)
	else:
		if "ability_data" in node: node.ability_data = data
		if "team_id"      in node: node.team_id      = tid

	node.global_position = pos
	get_tree().current_scene.add_child(node)
	_spawned_count += 1
	node.tree_exiting.connect(func(): _spawned_count = maxi(0, _spawned_count - 1))
