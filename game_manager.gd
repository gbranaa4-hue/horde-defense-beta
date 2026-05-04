extends Node


# ===============================
# CONFIG
# ===============================
@export var starting_money: int = 1000
@export var default_attack_creep: PackedScene
@export var prep_time: float = 180.0

## Passive income: gold given to each team every `income_interval` seconds
@export var income_amount: int   = 10
@export var income_interval: float = 5.0

# ===============================
# MONEY
# ===============================
var team_money := {
	1: 0,
	2: 0
}
var _income_timer: float = 0.0

# ===============================
# UPGRADES
# Per-team list of { "stat": String, "amount": float }
# Zombie._apply_existing_upgrades() reads this on spawn.
# ===============================
var _team_upgrades: Dictionary = {
	1: [],
	2: []
}

## Upgrade costs — add/edit freely
const UPGRADE_COSTS: Dictionary = {
	"health":       150,
	"damage":        120,
	"attack_speed":  200,
	"move_speed":    100,
}

# ===============================
# BASES
# ===============================
var team1_base: Node3D
var team2_base: Node3D

# ===============================
# STATE
# ===============================
var prep_timer: float   = 0.0
var match_started: bool = false
var team_ready := {
	1: false,
	2: false
}

# ===============================
# SIGNALS
# ===============================
signal money_changed(team: int, amount: int)
signal ready_updated(team: int, ready: bool)
signal prep_time_updated(time_left: float)
signal combat_started
signal upgrade_purchased(team: int, stat: String, amount: float)

# ===============================
# READY
# ===============================
func _ready() -> void:
	add_to_group("game_manager")
	set_process(true)
	_init_money()
	_find_bases()
	_assign_all_spawners()
	_disable_all_spawners()
	print("🟢 GameManager ready — PREP PHASE")

# ===============================
# PROCESS — prep timer + income
# ===============================
func _process(delta: float) -> void:
	# ── Prep countdown ──────────────────────────────────────────
	if not match_started:
		prep_timer += delta
		var time_left: float = max(prep_time - prep_timer, 0.0)
		prep_time_updated.emit(time_left)
		if time_left <= 0.0:
			start_match()
		return  # No income during prep

	# ── Passive income (combat only) ────────────────────────────
	_income_timer += delta
	if _income_timer >= income_interval:
		_income_timer -= income_interval
		_tick_income()

# ===============================
# MONEY
# ===============================
func _init_money() -> void:
	for t in team_money.keys():
		team_money[t] = starting_money
		money_changed.emit(t, team_money[t])

## Called by Zombie._grant_gold() when a unit dies
func award_gold(team_id: int, amount: int) -> void:
	if not team_money.has(team_id):
		return
	team_money[team_id] += amount
	money_changed.emit(team_id, team_money[team_id])
	print("[Gold] Team %d +%d (kill) → %d total" % [team_id, amount, team_money[team_id]])

## Called by CreepShop.purchase_creep() before spawning
func spend_gold(team_id: int, amount: int) -> bool:
	if not team_money.has(team_id):
		return false
	if team_money[team_id] < amount:
		return false
	team_money[team_id] -= amount
	money_changed.emit(team_id, team_money[team_id])
	return true

## Called by CreepShopUI to display current gold
func get_gold(team_id: int) -> int:
	return team_money.get(team_id, 0)

## Passive income tick — fires every `income_interval` seconds after match start
func _tick_income() -> void:
	for t in team_money.keys():
		award_gold(t, income_amount)

# ===============================
# UPGRADES
# ===============================
## Purchase an upgrade for a team. Returns false if insufficient gold.
## stat options: "health" | "damage" | "attack_speed" | "move_speed"
func purchase_upgrade(team_id: int, stat: String, amount: float = 1.0) -> bool:
	var cost: int = UPGRADE_COSTS.get(stat, 999999)
	if not spend_gold(team_id, cost):
		print("[Upgrade] Team %d cannot afford %s (%dg)" % [team_id, stat, cost])
		return false

	if not _team_upgrades.has(team_id):
		_team_upgrades[team_id] = []
	_team_upgrades[team_id].append({ "stat": stat, "amount": amount })

	# Apply to ALL living units on this team immediately
	_apply_upgrade_to_living(team_id, stat, amount)

	upgrade_purchased.emit(team_id, stat, amount)
	print("[Upgrade] Team %d → %s +%.2f" % [team_id, stat, amount])
	return true

## Called by Zombie._apply_existing_upgrades() on spawn — returns all upgrades for team
func get_creep_upgrades(team_id: int) -> Array:
	return _team_upgrades.get(team_id, [])

## Push a new upgrade to every currently-alive unit on this team
func _apply_upgrade_to_living(team_id: int, stat: String, amount: float) -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if not ("team_id" in u) or u.team_id != team_id:
			continue
		if u.has_method("apply_upgrade"):
			u.apply_upgrade(stat, amount)

# ===============================
# BASES
# ===============================
func _find_bases() -> void:
	for b in get_tree().get_nodes_in_group("bases"):
		if not ("team_id" in b):
			continue
		if b.team_id == 1:
			team1_base = b
		elif b.team_id == 2:
			team2_base = b
	print("Team1 base:", team1_base)
	print("Team2 base:", team2_base)

func get_base(team_id: int) -> Node3D:
	return team1_base if team_id == 1 else team2_base

func get_enemy_base(team_id: int) -> Node3D:
	return team2_base if team_id == 1 else team1_base

# ===============================
# SPAWNERS
# ===============================
func _assign_all_spawners() -> void:
	for s in get_tree().get_nodes_in_group("creep_spawner"):
		if not is_instance_valid(s) or not ("team_id" in s):
			continue
		s.set("enemy_base",    get_enemy_base(s.team_id))
		s.set("friendly_base", get_base(s.team_id))
		if default_attack_creep:
			s.set("creep_scene", default_attack_creep)

func _disable_all_spawners() -> void:
	for s in get_tree().get_nodes_in_group("creep_spawner"):
		if "active" in s:
			s.active = false

func _enable_all_spawners() -> void:
	for s in get_tree().get_nodes_in_group("creep_spawner"):
		if "active" in s:
			s.active = true

# ===============================
# READY SYSTEM
# ===============================
func set_team_ready(team_id: int, ready: bool = true) -> void:
	if not team_ready.has(team_id):
		return
	team_ready[team_id] = ready
	ready_updated.emit(team_id, ready)
	print("Team", team_id, "ready:", ready)
	_check_ready()

func _check_ready() -> void:
	if team_ready[1] and team_ready[2]:
		print("⚡ Both teams ready — starting early")
		start_match()

# ===============================
# MATCH START
# ===============================
func start_match() -> void:
	if match_started:
		return
	match_started = true
	_income_timer = 0.0
	print("🔥 MATCH STARTED")
	_enable_all_spawners()
	prep_time_updated.emit(0.0)
	combat_started.emit()
