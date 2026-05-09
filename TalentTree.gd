# ============================================================
# TalentTree.gd — AUTOLOAD
# ADD TO: Project > Autoloads, name = "TalentTree"
# ============================================================
# TIER COSTS (pickups per slot):
#   Tier 1:  0  — always unlocked
#   Tier 2:  3
#   Tier 3:  8
#   Tier 4: 16
#   Tier 5: 28  — full mastery
# ============================================================
extends Node

signal tree_updated(player_id: int)
signal hero_class_changed(player_id: int, class_name_: String)

const TIER_THRESHOLDS : Array[int] = [0, 3, 8, 16, 28]

const HERO_CLASSES : Array = [
	{
		"id": "berserker", "name": "⚔ Berserker", "color": Color(1.0, 0.25, 0.05),
		"desc": "Raw aggression — maximum fire rate and relentless pursuit.",
		"combo": "Berserker + Void Dash + Blood Rite",
		"slots": { 0: "berserker", 1: "blood_rite", 2: "void_dash" },
	},
	{
		"id": "ghost", "name": "👻 Ghost", "color": Color(0.4, 0.8, 1.0),
		"desc": "Stealth and speed. Disappear, reposition, and eliminate.",
		"combo": "Camouflage + Blink + Execute",
		"slots": { 0: "execute", 1: "camouflage", 2: "blink" },
	},
	{
		"id": "tank", "name": "🛡 Tank", "color": Color(0.2, 0.55, 1.0),
		"desc": "Absorbs punishment and reflects it back. Wins by outlasting.",
		"combo": "Iron Skin + Mirror Guard + Overclock",
		"slots": { 0: "double_damage", 1: "reflect", 2: "overclock" },
	},
	{
		"id": "hunter", "name": "🔥 Hunter", "color": Color(1.0, 0.6, 0.0),
		"desc": "Sustained area damage. Great for horde clearing.",
		"combo": "Fire Weapon + Vampiric Strike + Sprint",
		"slots": { 0: "vampiric", 1: "frost_armor", 2: "sprint" },
	},
	{
		"id": "commander", "name": "🧟 Commander", "color": Color(0.15, 0.9, 0.45),
		"desc": "Buff your zombie horde. Auras extend to nearby undead.",
		"combo": "Rapid Fire + Second Wind + Haste",
		"slots": { 0: "rapid_fire", 1: "second_wind", 2: "haste" },
	},
]

# pid → {slot: count}   — NEVER resets on death, permanent
var _collected            : Dictionary = {}
var _equipped             : Dictionary = {}
var _queued               : Dictionary = {}
var _active_class         : Dictionary = {}
var _collected_abilities  : Dictionary = {}  # pid → {slot: Array[Dictionary]}


func _ready() -> void:
	add_to_group("talent_tree")


# ── Called by TrinketPickup BEFORE equip_ability ─────────────
# Order matters — unlock tier first so HUD refresh is correct
func on_trinket_collected(player: Node, data: Dictionary) -> void:
	var pid  : int = int(player.get("player_id") if "player_id" in player else 0)
	var slot : int = int(data.get("slot", 0))

	if not _collected.has(pid):
		_collected[pid] = {0: 0, 1: 0, 2: 0}
		_equipped[pid]  = {0: null, 1: null, 2: null}

	if not _collected_abilities.has(pid):
		_collected_abilities[pid] = {0: [], 1: [], 2: []}

	_collected[pid][slot] += 1

	# Store the ability data so the UI can list what was collected
	# Only add if not already in list (avoid duplicates on respawn etc.)
	var ability_id : String = str(data.get("id", ""))
	var already_have := false
	for existing in _collected_abilities[pid][slot]:
		if existing.get("id", "") == ability_id:
			already_have = true; break
	if not already_have and ability_id != "":
		_collected_abilities[pid][slot].append(data.duplicate())

	var total : int = _collected[pid][slot]
	var tier  : int = tier_unlocked(pid, slot)
	print("[TalentTree] P%d slot%d: pickup #%d → tier %d — collected '%s'" % [pid, slot, total, tier + 1, ability_id])
	tree_updated.emit(pid)


# ── Getters ───────────────────────────────────────────────────
func collected_count(player_id: int, slot: int) -> int:
	if not _collected.has(player_id): return 0
	return int(_collected[player_id].get(slot, 0))


func tier_unlocked(player_id: int, slot: int) -> int:
	var count : int = collected_count(player_id, slot)
	for t in range(TIER_THRESHOLDS.size() - 1, -1, -1):
		if count >= TIER_THRESHOLDS[t]: return t
	return 0


func pickups_to_next_tier(player_id: int, slot: int) -> int:
	var count    : int = collected_count(player_id, slot)
	var cur_tier : int = tier_unlocked(player_id, slot)
	if cur_tier >= TIER_THRESHOLDS.size() - 1: return 0
	return TIER_THRESHOLDS[cur_tier + 1] - count


# ── Equipped tracking ─────────────────────────────────────────
func set_equipped(player_id: int, slot: int, data: Dictionary) -> void:
	if not _equipped.has(player_id):
		_equipped[player_id] = {0: null, 1: null, 2: null}
	_equipped[player_id][slot] = data if not data.is_empty() else null


# Returns Array[Dictionary] of all abilities collected for this slot
func get_collected_abilities(player_id: int, slot: int) -> Array:
	if not _collected_abilities.has(player_id): return []
	return _collected_abilities[player_id].get(slot, [])


func get_equipped(player_id: int, slot: int) -> Dictionary:
	if not _equipped.has(player_id): return {}
	var eq = _equipped[player_id].get(slot, null)
	return eq if eq != null else {}


# ── Queue ability for next matching pickup ────────────────────
func queue_ability(player_id: int, data: Dictionary) -> void:
	_queued[player_id] = data
	print("[TalentTree] P%d queued '%s'" % [player_id, data.get("name","?")])


func get_queued(player_id: int) -> Dictionary:
	return _queued.get(player_id, {})


func clear_queued(player_id: int) -> void:
	_queued.erase(player_id)


# ── Progress strings ──────────────────────────────────────────
func progress_text(player_id: int, slot: int) -> String:
	var count    : int = collected_count(player_id, slot)
	var cur_tier : int = tier_unlocked(player_id, slot)
	if cur_tier >= TIER_THRESHOLDS.size() - 1:
		return "MASTERY (%d)" % count
	return "T%d  %d/%d → T%d" % [
		cur_tier + 1, count, TIER_THRESHOLDS[cur_tier + 1], cur_tier + 2]


func tier_label(tier: int) -> String:
	match tier:
		0: return "Tier I — Starter"
		1: return "Tier II — %d trinkets" % TIER_THRESHOLDS[1]
		2: return "Tier III — %d trinkets" % TIER_THRESHOLDS[2]
		3: return "Tier IV — %d trinkets" % TIER_THRESHOLDS[3]
		4: return "Tier V — MASTERY (%d trinkets)" % TIER_THRESHOLDS[4]
	return "Tier %d" % (tier + 1)


# ── Hero classes ──────────────────────────────────────────────
func get_hero_classes() -> Array:
	return HERO_CLASSES.duplicate(true)


func get_active_class(player_id: int) -> String:
	return _active_class.get(player_id, "")


func select_hero_class(player: Node, class_id: String) -> bool:
	var pid : int = int(player.get("player_id") if "player_id" in player else 0)
	var cls : Dictionary = {}
	for c in HERO_CLASSES:
		if c["id"] == class_id: cls = c; break
	if cls.is_empty(): return false

	_active_class[pid] = class_id
	var slots : Dictionary = cls.get("slots", {})
	for slot_key in slots:
		var slot     : int    = int(slot_key)
		var abil_id  : String = str(slots[slot_key])
		var abil_data : Dictionary = _find_ability_by_id(abil_id, slot)
		if not abil_data.is_empty():
			var unlocked : int = tier_unlocked(pid, slot)
			var tier     : int = int(abil_data.get("tier", 0))
			if tier <= unlocked and player.has_method("equip_ability"):
				player.equip_ability(slot, abil_data)
			else:
				_queued[pid] = abil_data

	hero_class_changed.emit(pid, class_id)
	tree_updated.emit(pid)
	return true


func clear_hero_class(player_id: int) -> void:
	_active_class.erase(player_id)
	_queued.erase(player_id)
	hero_class_changed.emit(player_id, "")


func get_class_info(class_id: String) -> Dictionary:
	for c in HERO_CLASSES:
		if c["id"] == class_id: return c.duplicate(true)
	return {}


func _find_ability_by_id(abil_id: String, slot: int) -> Dictionary:
	const POOLS : Array = [
		[
			{"id":"rapid_fire",   "name":"⚡ Rapid Fire",       "slot":0,"tier":0,"cooldown":120.0,"duration":8.0,  "desc":"Fire rate x2.5 for 8s."},
			{"id":"frenzy",       "name":"⚡ Frenzy",           "slot":0,"tier":0,"cooldown":100.0,"duration":6.0,  "desc":"Rapid fire burst."},
			{"id":"double_damage","name":"💀 Death Mark",       "slot":0,"tier":1,"cooldown":150.0,"duration":10.0, "desc":"2x damage 10s."},
			{"id":"berserker",    "name":"🔥 Berserker",        "slot":0,"tier":1,"cooldown":130.0,"duration":8.0,  "desc":"Fire x1.8 move x1.6."},
			{"id":"fire_weapon",  "name":"🔥 Fire Weapon",      "slot":0,"tier":2,"cooldown":125.0,"duration":9.0,  "desc":"Burning shots."},
			{"id":"explosive",    "name":"💥 Explosive Rounds", "slot":0,"tier":2,"cooldown":145.0,"duration":7.0,  "desc":"Bullets explode."},
			{"id":"vampiric",     "name":"🩸 Vampiric Strike",  "slot":0,"tier":3,"cooldown":135.0,"duration":8.0,  "desc":"Heal 30pct dealt."},
			{"id":"execute",      "name":"☠ Execute",           "slot":0,"tier":3,"cooldown":160.0,"duration":5.0,  "desc":"Instant kill <25pct HP."},
		],
		[
			{"id":"void_shield",  "name":"🔵 Void Shield",      "slot":1,"tier":0,"cooldown":90.0, "duration":6.0,  "desc":"Full immunity 6s."},
			{"id":"blood_rite",   "name":"💚 Blood Rite",        "slot":1,"tier":0,"cooldown":80.0, "amount":60.0,   "desc":"Restore 60 HP."},
			{"id":"iron_skin",    "name":"🪨 Iron Skin",         "slot":1,"tier":1,"cooldown":110.0,"duration":12.0, "desc":"60pct reduction 12s."},
			{"id":"energy_shield","name":"🔵 Energy Shield",     "slot":1,"tier":1,"cooldown":105.0,"amount":75.0,   "desc":"75 temp HP."},
			{"id":"reflect",      "name":"🔄 Mirror Guard",      "slot":1,"tier":2,"cooldown":120.0,"duration":7.0,  "desc":"Reflect 100pct dmg."},
			{"id":"frost_armor",  "name":"❄ Frost Armor",        "slot":1,"tier":2,"cooldown":115.0,"duration":10.0, "desc":"Attackers slowed 60pct."},
			{"id":"second_wind",  "name":"💨 Second Wind",       "slot":1,"tier":3,"cooldown":180.0,"duration":0.0,  "desc":"Auto-revive once."},
			{"id":"camouflage",   "name":"🌿 Camouflage",        "slot":1,"tier":3,"cooldown":90.0, "duration":12.0, "desc":"Hard to see 12s."},
		],
		[
			{"id":"void_dash",   "name":"💨 Void Dash",   "slot":2,"tier":0,"cooldown":60.0, "distance":8.0,  "desc":"Dash 8m."},
			{"id":"phase_shift", "name":"👻 Phase Shift", "slot":2,"tier":0,"cooldown":75.0, "duration":5.0,  "desc":"Semi-transparent 5s."},
			{"id":"overclock",   "name":"🌀 Overclock",   "slot":2,"tier":1,"cooldown":90.0, "duration":6.0,  "desc":"Speed x1.3 for 6s."},
			{"id":"blink",       "name":"✨ Blink",        "slot":2,"tier":1,"cooldown":70.0, "distance":12.0, "desc":"Teleport 12m."},
			{"id":"sprint",      "name":"🏃 Sprint",       "slot":2,"tier":2,"cooldown":80.0, "duration":5.0,  "desc":"Speed x1.6 for 5s."},
			{"id":"haste",       "name":"⚡ Haste",        "slot":2,"tier":2,"cooldown":110.0,"duration":4.0,  "desc":"Speed x1.8 fire x1.5."},
			{"id":"evasion",     "name":"🎭 Evasion",      "slot":2,"tier":3,"cooldown":85.0, "duration":6.0,  "desc":"50pct dodge 6s."},
			{"id":"double_jump", "name":"🦘 Double Jump",  "slot":2,"tier":3,"cooldown":40.0, "duration":20.0, "desc":"Double jump 20s."},
		],
	]
	if slot < 0 or slot >= POOLS.size(): return {}
	for abil in POOLS[slot]:
		if abil.get("id","") == abil_id: return abil.duplicate()
	return {}
