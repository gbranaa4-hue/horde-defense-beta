# ============================================================
# HordeManager.gd — AUTOLOAD as "HordeManager"
# ============================================================
# Central brain for all minions.
# Handles: targeting, LOD, separation, flow field queries.
# Minions NEVER search the scene tree — manager feeds everything.
# ============================================================
extends Node

# ── Registries (never call get_nodes_in_group in battle) ─────
var _team1   : Array = []
var _team2   : Array = []
var _all     : Array = []

# Structures indexed by team
var _structures : Dictionary = { 1: [], 2: [] }  # bases, turrets

# ── Config ────────────────────────────────────────────────────
const LOD0_DIST : float = 18.0
const LOD1_DIST : float = 45.0
const LOD2_DIST : float = 100.0
const SEP_RADIUS : float = 1.5
const SEP_FORCE  : float = 10.0
const TARGET_INTERVAL : float = 0.25
const SEP_INTERVAL    : float = 0.1

# ── Internal ──────────────────────────────────────────────────
var _target_timer : float = 0.0
var _sep_timer    : float = 0.0
var _player_positions : Array[Vector3] = []


# ============================================================
func _ready() -> void:
	add_to_group("horde_manager")
	add_to_group("zombie_horde_manager")
	set_process(true)
	# Scan for bases after scene is ready
	get_tree().process_frame.connect(_register_bases, CONNECT_ONE_SHOT)

func _register_bases() -> void:
	for b in get_tree().get_nodes_in_group("bases"):
		if not is_instance_valid(b) or not ("team_id" in b): continue
		var tid : int = int(b.get("team_id"))
		if tid in _structures and not _structures[tid].has(b):
			_structures[tid].append(b)
			print("[HordeManager] registered base: %s team=%d" % [b.name, tid])
	# Also register turrets
	for t in get_tree().get_nodes_in_group("towers"):
		if not is_instance_valid(t) or not ("team_id" in t): continue
		var tid : int = int(t.get("team_id"))
		if tid in _structures and not _structures[tid].has(t):
			_structures[tid].append(t)


func _process(delta: float) -> void:
	_clean_dead()
	_update_player_positions()

	_target_timer -= delta
	if _target_timer <= 0.0:
		_target_timer = TARGET_INTERVAL
		_assign_targets()
		_update_lod()
		_push_flow_fields()

	_sep_timer -= delta
	if _sep_timer <= 0.0:
		_sep_timer = SEP_INTERVAL
		_compute_separation()


# ============================================================
# REGISTRATION
# ============================================================
func register(m: Node) -> void:
	if not is_instance_valid(m): return
	_all.append(m)
	if m.team_id == 1: _team1.append(m)
	else:              _team2.append(m)
	# Register structures referenced by this minion
	_register_structure(m.enemy_base)
	_register_structure(m.friendly_base)

func unregister(m: Node) -> void:
	_all.erase(m); _team1.erase(m); _team2.erase(m)

func register_structure(node: Node3D, team: int) -> void:
	if not is_instance_valid(node): return
	if not _structures[team].has(node):
		_structures[team].append(node)

func _register_structure(node: Node3D) -> void:
	if not is_instance_valid(node) or not ("team_id" in node): return
	var tid : int = int(node.get("team_id"))
	if tid in _structures and not _structures[tid].has(node):
		_structures[tid].append(node)


# ============================================================
# TARGETING — runs every 0.25s, O(n) not O(n²)
# ============================================================
func _assign_targets() -> void:
	# Team 1 minions target team 2 units/structures
	_assign_for_team(_team1, _team2, _structures[2])
	# Team 2 minions target team 1 units/structures
	_assign_for_team(_team2, _team1, _structures[1])


func _assign_for_team(
		attackers : Array,
		enemies   : Array,
		structs   : Array) -> void:

	# All players — filtered per-attacker below
	var all_players : Array = []
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and "team_id" in p: all_players.append(p)

	for attacker in attackers:
		if not is_instance_valid(attacker) or not attacker.has_method("is_dead") or attacker.is_dead(): continue
		if attacker.lod >= 3: continue

		# Skip if player-commanded or already has valid close target
		if attacker.has_method("is_commanded") and attacker.is_commanded(): continue
		if is_instance_valid(attacker.target) \
				and _node_alive(attacker.target) \
				and attacker.global_position.distance_to(attacker.target.global_position) \
					< attacker.attack_range * 3.0:
			continue

		var best      : Node3D = null
		var best_dist : float  = attacker.attack_range * 2.5

		# Priority 1: enemy players (different team from attacker)
		for p in all_players:
			if not is_instance_valid(p): continue
			if int(p.get("team_id")) == attacker.team_id: continue  # must be enemy team
			if p.has_method("is_dead") and p.is_dead(): continue
			if "is_dead" in p and p.get("is_dead") == true: continue
			var d : float = attacker.global_position.distance_to((p as Node3D).global_position)
			if d < best_dist: best_dist = d; best = p as Node3D

		# Priority 2: enemy minions
		for enemy in enemies:
			if not is_instance_valid(enemy) or enemy.is_dead(): continue
			var d : float = attacker.global_position.distance_to(enemy.global_position)
			if d < best_dist: best_dist = d; best = enemy

		# Priority 3: structures (base etc) — always consider if nothing closer
		if not is_instance_valid(best):
			best_dist = 999.0
			for s in structs:
				if not is_instance_valid(s): continue
				if "health" in s and float(s.get("health")) <= 0.0: continue
				var d : float = attacker.global_position.distance_to((s as Node3D).global_position)
				if d < best_dist: best_dist = d; best = s as Node3D

		attacker.assign_target(best)


# ============================================================
# LOD — distance from nearest player
# ============================================================
func _update_player_positions() -> void:
	_player_positions.clear()
	for p in get_tree().get_nodes_in_group("player"):
		if p is Node3D: _player_positions.append((p as Node3D).global_position)

func _update_lod() -> void:
	for m in _all:
		if not is_instance_valid(m): continue
		var dist : float = _nearest_player_dist(m.global_position)
		var new_lod : int
		if   dist < LOD0_DIST:  new_lod = 0
		elif dist < LOD1_DIST:  new_lod = 1
		elif dist < LOD2_DIST:  new_lod = 2
		else:                   new_lod = 3
		if m.lod != new_lod:
			m.lod = new_lod
			m.set_physics_process(new_lod < 3)

func _nearest_player_dist(pos: Vector3) -> float:
	var best : float = 9999.0
	for pp in _player_positions:
		var d : float = pos.distance_to(pp)
		if d < best: best = d
	return best


# ============================================================
# FLOW FIELD — push direction toward enemy base per lane
# ============================================================
func _push_flow_fields() -> void:
	var lf := get_tree().get_first_node_in_group("lane_flow_field")
	for m in _all:
		if not is_instance_valid(m) or m.is_dead(): continue
		if m.state != 1: continue
		if m.has_method("is_commanded") and m.is_commanded(): continue  # keep command dir
		var dir : Vector3
		if is_instance_valid(lf) and lf.has_method("get_flow"):
			dir = lf.get_flow(m.team_id, m.lane_id, m.global_position)
		elif is_instance_valid(m.enemy_base):
			dir = (m.enemy_base.global_position - m.global_position)
			dir.y = 0.0
			if dir.length_squared() > 0.01: dir = dir.normalized()
		m.set_flow_direction(dir)


# ============================================================
# SEPARATION — keeps minions from stacking
# ============================================================
func _compute_separation() -> void:
	# O(n) spatial bucket approach — group by approximate grid cell
	var buckets : Dictionary = {}
	for m in _all:
		if not is_instance_valid(m) or m.is_dead(): continue
		var key : Vector3i = Vector3i(
			int(m.global_position.x / (SEP_RADIUS * 2.0)),
			0,
			int(m.global_position.z / (SEP_RADIUS * 2.0)))
		if not buckets.has(key): buckets[key] = []
		buckets[key].append(m)

	# Only check neighbors in same + adjacent cells
	var offsets : Array = [
		Vector3i(0,0,0), Vector3i(1,0,0), Vector3i(-1,0,0),
		Vector3i(0,0,1), Vector3i(0,0,-1),
		Vector3i(1,0,1), Vector3i(1,0,-1), Vector3i(-1,0,1), Vector3i(-1,0,-1)]

	for key in buckets:
		var cell_units : Array = buckets[key]
		var neighbors  : Array = []
		for off in offsets:
			var nkey : Vector3i = key + off
			if buckets.has(nkey): neighbors.append_array(buckets[nkey])

		for m in cell_units:
			if not is_instance_valid(m): continue
			var force := Vector3.ZERO
			for n in neighbors:
				if not is_instance_valid(n) or n == m: continue
				var diff : Vector3 = m.global_position - (n as Node3D).global_position
				diff.y = 0.0
				var dist : float = diff.length()
				if dist < 0.01:
					diff = Vector3(randf_range(-1,1), 0, randf_range(-1,1))
					dist = diff.length()
				if dist < SEP_RADIUS:
					force += diff.normalized() * (1.0 - dist / SEP_RADIUS) * SEP_FORCE
			if force.length() > 8.0: force = force.normalized() * 8.0
			m.set_separation_force(force)


# ============================================================
# HELPERS
# ============================================================
func _node_alive(node: Node) -> bool:
	if not is_instance_valid(node): return false
	if node.has_method("is_dead") and node.is_dead(): return false
	if "health" in node and float(node.get("health")) <= 0.0: return false
	return true


# ============================================================
# CLEANUP
# ============================================================
func _clean_dead() -> void:
	_all    = _all.filter(func(m: Node): return is_instance_valid(m) and not m.is_dead())
	_team1  = _team1.filter(func(m: Node): return is_instance_valid(m) and not m.is_dead())
	_team2  = _team2.filter(func(m: Node): return is_instance_valid(m) and not m.is_dead())

func get_team_count(team: int) -> int:
	return _team1.size() if team == 1 else _team2.size()


# ============================================================
# SQUAD COMMAND API — used by SquadCommandPanel
# ============================================================
var _selected : Array = []

signal selection_changed(selected: Array)

func get_selected() -> Array:
	return _selected

func deselect_all() -> void:
	_selected.clear()
	selection_changed.emit(_selected)

func select_all_team(team: int) -> void:
	_selected.clear()
	var src : Array = _team1 if team == 1 else _team2
	for m in src:
		if is_instance_valid(m) and not m.is_dead(): _selected.append(m)
	selection_changed.emit(_selected)

func select_owned_by(owner_iid: int) -> void:
	_selected.clear()
	for m in _all:
		if not is_instance_valid(m) or m.is_dead(): continue
		if "owner_player" in m and is_instance_valid(m.owner_player) 				and m.owner_player.get_instance_id() == owner_iid:
			_selected.append(m)
	selection_changed.emit(_selected)

func select_in_radius(pos: Vector3, radius: float, team: int) -> void:
	_selected.clear()
	var src : Array = _team1 if team == 1 else _team2
	for m in src:
		if not is_instance_valid(m) or m.is_dead(): continue
		if m.global_position.distance_to(pos) <= radius: _selected.append(m)
	selection_changed.emit(_selected)

func select_box(cam: Camera3D, ndc_min: Vector2, ndc_max: Vector2, team: int) -> void:
	_selected.clear()
	var src : Array = _team1 if team == 1 else _team2
	for m in src:
		if not is_instance_valid(m) or m.is_dead(): continue
		var sp : Vector2 = cam.unproject_position(m.global_position)
		var vp : Vector2 = cam.get_viewport().get_visible_rect().size
		var uv : Vector2 = sp / vp
		if uv.x >= ndc_min.x and uv.x <= ndc_max.x 				and uv.y >= ndc_min.y and uv.y <= ndc_max.y:
			_selected.append(m)
	selection_changed.emit(_selected)

func command_attack(world_pos: Vector3) -> void:
	for m in _selected:
		if not is_instance_valid(m) or m.is_dead(): continue
		var enemies : Array = _team1 if m.team_id == 2 else _team2
		var best : Node3D = null; var best_d : float = 999.0
		for e in enemies:
			if not is_instance_valid(e) or e.is_dead(): continue
			var d : float = world_pos.distance_to(e.global_position)
			if d < best_d: best_d = d; best = e
		var m3d_a := m as Node3D
		var flow : Vector3 = world_pos - m3d_a.global_position; flow.y = 0.0
		if flow.length_squared() > 0.01: flow = flow.normalized()
		m.command(flow, best, 10.0)

func command_defend(base_pos: Vector3) -> void:
	for m in _selected:
		if not is_instance_valid(m) or m.is_dead(): continue
		var m3d_b := m as Node3D
		var flow : Vector3 = base_pos - m3d_b.global_position; flow.y = 0.0
		if flow.length_squared() > 0.01: flow = flow.normalized()
		m.command(flow, null, 12.0)

func command_patrol(waypoints: Array) -> void:
	# Simple: loop through waypoints by pushing toward each in sequence
	for m in _selected:
		if not is_instance_valid(m) or m.is_dead(): continue
		if waypoints.is_empty(): continue
		# Use first waypoint as immediate push direction
		var wp0 : Vector3 = waypoints[0] as Vector3
		var m3d_c := m as Node3D
		var dir : Vector3 = (wp0 - m3d_c.global_position).normalized()
		dir.y = 0.0
		m.set_flow_direction(dir)
		m.state = 1

func command_stay() -> void:
	for m in _selected:
		if not is_instance_valid(m) or m.is_dead(): continue
		m.velocity = Vector3.ZERO
		m.command(Vector3.ZERO, null, 15.0)
		m.set_separation_force(Vector3.ZERO)

func command_follow(target: Node3D) -> void:
	for m in _selected:
		if not is_instance_valid(m) or m.is_dead(): continue
		var flow := Vector3.ZERO
		if is_instance_valid(target):
			flow = (target.global_position - m.global_position)
			flow.y = 0.0
			if flow.length_squared() > 0.01: flow = flow.normalized()
		m.command(flow, null, 999.0)  # follow indefinitely until next command
		# Update flow toward player each frame via HordeManager
		m.set_meta("follow_target", target)

func command_follow_interrupt(target: Node3D) -> void:
	command_follow(target)

func get_all_minions() -> Array:
	return _all#
