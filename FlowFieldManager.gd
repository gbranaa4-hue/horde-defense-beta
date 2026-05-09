# ============================================================
# LaneFlowField.gd — AUTOLOAD as "LaneFlowField"
# ============================================================
# Pre-computes flow directions for each lane.
# Minions call get_flow(team, lane, position) to get
# a normalized Vector3 pointing toward enemy base.
# Zero overhead per minion — one lookup per update batch.
# ============================================================
extends Node

# _flows[team_id][lane_id] = Array of {origin, direction} segments
var _flows : Dictionary = {}
var _ready_flag : bool = false


func _ready() -> void:
	add_to_group("lane_flow_field")
	# Wait for LaneSpawner to compute paths
	get_tree().create_timer(0.5).timeout.connect(_build_from_lane_spawner)


func _build_from_lane_spawner() -> void:
	var ls := get_tree().get_first_node_in_group("lane_spawner")
	if not is_instance_valid(ls):
		# Retry
		get_tree().create_timer(0.5).timeout.connect(_build_from_lane_spawner)
		return

	_flows.clear()
	for team in [1, 2]:
		_flows[team] = {}
		for lane in 3:
			var wps : Array = ls.get_lane_waypoints(team, lane)
			if wps.is_empty(): continue
			var segments : Array = []
			for i in range(wps.size() - 1):
				var a : Vector3 = wps[i]
				var b : Vector3 = wps[i + 1]
				var dir : Vector3 = (b - a); dir.y = 0.0
				if dir.length_squared() > 0.01: dir = dir.normalized()
				segments.append({ "origin": a, "dir": dir, "end": b })
			_flows[team][lane] = segments

	_ready_flag = true
	print("[LaneFlowField] Built | teams=%d" % _flows.size())


# ── Get flow direction for a minion at a given position ──────
func get_flow(team: int, lane: int, pos: Vector3) -> Vector3:
	if not _ready_flag: return Vector3.ZERO
	if not _flows.has(team): return Vector3.ZERO
	if not _flows[team].has(lane): return Vector3.ZERO

	var segments : Array = _flows[team][lane]
	if segments.is_empty(): return Vector3.ZERO

	# Find nearest segment and return its direction
	var best_dir  : Vector3 = segments[0]["dir"]
	var best_dist : float   = 9999.0

	for seg in segments:
		var mid : Vector3 = (seg["origin"] as Vector3).lerp(seg["end"], 0.5)
		var d   : float   = pos.distance_to(mid)
		if d < best_dist:
			best_dist = d
			best_dir  = seg["dir"]

	return best_dir


func is_ready() -> bool:
	return _ready_flag
