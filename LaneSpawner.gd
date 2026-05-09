# ============================================================
# LaneSpawner.gd — AUTOLOAD
# ============================================================
extends Node

signal wave_spawned(team_id: int, lane: int, count: int)

@export var creep_scene_team1 : PackedScene = null
@export var creep_scene_team2 : PackedScene = null
@export var wave_size         : int   = 5
@export var wave_interval     : float = 30.0
@export var spawn_stagger     : float = 0.3
@export var lane_width_offset : float = 0.35

const LANE_COUNT   := 3
const SCENE_PATH_1 := "res://zombie/zombie.tscn"
const SCENE_PATH_2 := "res://zombie/zombie.tscn"

var _base1  : Node3D = null
var _base2  : Node3D = null
var _ready_to_spawn : bool = false
var _wave_timer     : float = 0.0
var _wave_number    : int   = 0
var _lane_paths : Array = [[], [], []]


func _ready() -> void:
	# Singleton guard — only one LaneSpawner should run
	var existing := get_tree().get_nodes_in_group("lane_spawner")
	if existing.size() > 0 and existing[0] != self:
		push_warning("[LaneSpawner] Duplicate detected (%s). Removing." % name)
		queue_free(); return
	add_to_group("lane_spawner")
	set_process(false)
	# Wait for bases to be added to scene — retry up to 5 seconds
	_find_bases_retry()

func _find_bases_retry() -> void:
	for _attempt in range(50):   # 50 x 0.1s = 5 seconds max
		await get_tree().create_timer(0.1).timeout
		var found1 := false; var found2 := false
		for b in get_tree().get_nodes_in_group("bases"):
			if not is_instance_valid(b) or not ("team_id" in b): continue
			if int(b.get("team_id")) == 1: found1 = true
			if int(b.get("team_id")) == 2: found2 = true
		if found1 and found2:
			_find_bases()
			return
	push_error("[LaneSpawner] Could not find both bases after 5s!")


func _find_bases() -> void:
	for b in get_tree().get_nodes_in_group("bases"):
		if not is_instance_valid(b) or not ("team_id" in b): continue
		if int(b.get("team_id")) == 1: _base1 = b as Node3D
		else:                           _base2 = b as Node3D

	if not is_instance_valid(_base1) or not is_instance_valid(_base2):
		push_error("[LaneSpawner] bases still missing after retry — check 'bases' group and team_id.")
		return
	print("[LaneSpawner] _find_bases OK | base1=%s pos=%s | base2=%s pos=%s" % [
		_base1.name, str(_base1.global_position.snapped(Vector3.ONE)),
		_base2.name, str(_base2.global_position.snapped(Vector3.ONE))])

	_compute_lane_paths()
	# Don't override process state if start() already called
	if not _ready_to_spawn:
		set_process(false)

	if not is_instance_valid(creep_scene_team1):
		push_error("[LaneSpawner] creep_scene_team1 is NULL — assign in Inspector!")
	if not is_instance_valid(creep_scene_team2):
		push_error("[LaneSpawner] creep_scene_team2 is NULL — assign in Inspector!")

	print("[LaneSpawner] Ready. Base1=%s(team%s) Base2=%s(team%s)" % [
		_base1.name, str(_base1.get("team_id") if "team_id" in _base1 else "?"),
		_base2.name, str(_base2.get("team_id") if "team_id" in _base2 else "?")])


func _compute_lane_paths() -> void:
	# Team 1 base (spawns here, marches toward team 2 base)
	var t1_start : Vector3 = _base1.global_position
	# Team 2 base (spawns here, marches toward team 1 base)
	var t2_start : Vector3 = _base2.global_position

	var axis    := (t2_start - t1_start); axis.y = 0.0
	var length  := axis.length()
	var forward := axis.normalized()
	var perp    := Vector3(-forward.z, 0.0, forward.x).normalized()
	var offsets : Array = [-1.0, 0.0, 1.0]

	# team_idx=0: team1 spawns at t1_start, marches to t2_start
	# team_idx=1: team2 spawns at t2_start, marches to t1_start
	var starts : Array = [t1_start, t2_start]
	var ends   : Array = [t2_start, t1_start]

	for team_idx in 2:
		_lane_paths[team_idx] = []
		var s : Vector3 = starts[team_idx]
		var e : Vector3 = ends[team_idx]
		for lane in LANE_COUNT:
			var off_amount : float = offsets[lane] * length * lane_width_offset
			var bulge_mid  : Vector3 = s.lerp(e, 0.5) + perp * off_amount
			var pts : Array = []
			for i in range(7):
				var t : float = float(i) / 6.0
				var p0 := s.lerp(bulge_mid, t)
				var p1 := bulge_mid.lerp(e, t)
				var wp : Vector3 = p0.lerp(p1, t)
				wp.y = 0.5   # normalize Y — zombie handles exact ground height
				pts.append(wp)
			# Pin first/last to exact base XZ
			pts[0]             = Vector3(s.x, 0.5, s.z)
			pts[pts.size() - 1] = Vector3(e.x, 0.5, e.z)
			_lane_paths[team_idx].append(pts)

	print("[LaneSpawner] Lane paths computed. Offset scale=%.1f" % (length * lane_width_offset))


func _process(delta: float) -> void:
	if not _ready_to_spawn: return
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		_wave_timer = wave_interval
		_wave_number += 1
		_spawn_all_lanes()


func _spawn_all_lanes() -> void:
	for lane in LANE_COUNT:
		_spawn_lane_wave(1, lane)
		_spawn_lane_wave(2, lane)


func _spawn_lane_wave(team: int, lane: int) -> void:
	var scene : PackedScene = _get_scene(team)
	if not is_instance_valid(scene):
		push_error("[LaneSpawner] MISSING SCENE for team %d — assign creep_scene_team%d in Inspector!" % [team, team])
		return

	var team_idx : int = 0 if team == 1 else 1
	var paths    : Array = _lane_paths[team_idx]
	if paths.is_empty():
		push_error("[LaneSpawner] T%d lane paths EMPTY — _compute_lane_paths failed" % team); return
	if lane >= paths.size(): return
	var waypoints : Array = paths[lane]
	if waypoints.is_empty(): return

	# ── FIX: spawn at waypoint[1], not waypoint[0] ──────────────
	# waypoint[0] = base position — spawning there causes instant base attack
	# waypoint[1] = first march point away from base
	var spawn_pos : Vector3 = waypoints[1] if waypoints.size() > 1 else waypoints[0]
	var march_wps : Array   = waypoints.slice(1) if waypoints.size() > 1 else waypoints

	var enemy_base : Node3D = _base2 if team == 1 else _base1
	var friendly   : Node3D = _base1 if team == 1 else _base2

	var spawned := 0
	for i in range(wave_size):
		var creep := _spawn_creep(scene, team, spawn_pos, march_wps, enemy_base, friendly, i, lane)
		if is_instance_valid(creep): spawned += 1
		if i < wave_size - 1:
			await get_tree().create_timer(spawn_stagger).timeout

	if spawned > 0:
		wave_spawned.emit(team, lane, spawned)
		print("[LaneSpawner] ✓ T%d Lane%d Wave#%d — %d creeps | spawn=%s → enemy=%s" % [
			team, lane, _wave_number, spawned,
			str(spawn_pos.snapped(Vector3.ONE)),
			enemy_base.name if is_instance_valid(enemy_base) else "NULL"])


func _spawn_creep(
		scene     : PackedScene,
		team      : int,
		pos       : Vector3,
		waypoints : Array,
		enemy_base: Node3D,
		friendly  : Node3D,
		slot      : int,
		lane      : int = 0
) -> Node3D:
	if not is_instance_valid(scene): return null
	var creep := scene.instantiate()
	if not is_instance_valid(creep): return null

	# Set identity BEFORE add_child so _ready() sees correct values
	if "team_id"       in creep: creep.set("team_id",       team)
	if "enemy_base"    in creep: creep.set("enemy_base",    enemy_base)
	if "friendly_base" in creep: creep.set("friendly_base", friendly)
	if "lane_id"       in creep: creep.set("lane_id",       lane)
	if "owner_id"      in creep: creep.set("owner_id",      -1)

	get_tree().current_scene.add_child(creep)

	# RE-APPLY after _ready() — guards against _find_bases() overwriting
	if "team_id"       in creep: creep.set("team_id",       team)
	if "enemy_base"    in creep: creep.set("enemy_base",    enemy_base)
	if "friendly_base" in creep: creep.set("friendly_base", friendly)
	if "lane_id"       in creep: creep.set("lane_id",       lane)

	# Position with stagger — raycast to find actual ground Y
	var angle  : float   = float(slot) / float(wave_size) * TAU
	var offset : Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * 0.9
	var spawn  : Vector3 = pos + offset
	var space  := get_tree().root.get_world_3d().direct_space_state if is_inside_tree() else null
	if is_instance_valid(space):
		var ray := PhysicsRayQueryParameters3D.create(
			spawn + Vector3(0, 5, 0), spawn + Vector3(0, -10, 0))
		ray.collision_mask = 1  # terrain/static layer only
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			spawn.y = hit.position.y + 0.1
		else:
			spawn.y = maxf(spawn.y, 0.5)
	else:
		spawn.y = maxf(spawn.y, 0.5)
	creep.global_position = spawn

	creep.add_to_group("units")
	creep.add_to_group("minions")

	# Fade minion in through fog patch
	var fse := get_tree().get_first_node_in_group("fog_spawn_effect")
	if is_instance_valid(fse) and fse.has_method("fade_in_minion"):
		fse.fade_in_minion(creep as Node3D)

	# Legacy waypoint support (old zombie.gd)
	if creep.has_method("set_lane"):
		var march_wps := waypoints.slice(1) if waypoints.size() > 1 else waypoints
		creep.call("set_lane", march_wps, lane)

	# Register with HordeManager (new system)
	var hm := get_tree().get_first_node_in_group("horde_manager")
	if is_instance_valid(hm) and hm.has_method("register"):
		hm.call("register", creep)

	# Legacy ZombieHordeManager support
	var zhm := get_tree().get_first_node_in_group("zombie_horde_manager")
	if is_instance_valid(zhm) and zhm.has_method("register_zombie"):
		zhm.register_zombie(creep, team)

	return creep as Node3D


func _get_scene(team: int) -> PackedScene:
	if team == 1:
		if is_instance_valid(creep_scene_team1): return creep_scene_team1
		if ResourceLoader.exists(SCENE_PATH_1): return load(SCENE_PATH_1)
	else:
		if is_instance_valid(creep_scene_team2): return creep_scene_team2
		if ResourceLoader.exists(SCENE_PATH_2): return load(SCENE_PATH_2)
	return null


func start() -> void:
	if _ready_to_spawn: return  # already started — ignore duplicate call
	_ready_to_spawn = true
	_wave_timer = 8.0
	set_process(true)
	print("[LaneSpawner] Match started — first wave in 8s")

func stop() -> void:
	set_process(false)

func set_wave_interval(t: float) -> void:
	wave_interval = t

func get_lane_waypoints(team: int, lane: int) -> Array:
	var idx : int = 0 if team == 1 else 1
	if idx < _lane_paths.size() and lane < _lane_paths[idx].size():
		return _lane_paths[idx][lane]
	return []
