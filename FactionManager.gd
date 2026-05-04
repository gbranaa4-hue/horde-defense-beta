extends Node

# ===============================
# FACTION RULES
# ===============================
const TEAM_PLAYER_A: int = 1
const TEAM_PLAYER_B: int = 2

# optional expansion later
var team_data := {
	1: { "name": "Team A", "enemy": 2 },
	2: { "name": "Team B", "enemy": 1 }
}


# ===============================
# CORE CHECKS
# ===============================
func is_enemy(a: Node, b: Node) -> bool:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return false

	return a.get("team_id") != b.get("team_id")


func is_ally(a: Node, b: Node) -> bool:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return false

	return a.get("team_id") == b.get("team_id")


func get_enemy_team(team_id: int) -> int:
	if team_data.has(team_id):
		return team_data[team_id]["enemy"]

	return -1


# ===============================
# TARGET FILTERING (VERY IMPORTANT)
# ===============================
func is_valid_target(me: Node, target: Node) -> bool:
	if not is_instance_valid(me) or not is_instance_valid(target):
		return false

	# cannot target same team
	if target.get("team_id") == me.get("team_id"):
		return false

	return true


# ===============================
# PRIORITY TARGET HELPERS
# ===============================
func get_closest_enemy(me: Node, group_name: String) -> Node:
	var closest: Node = null
	var best_dist: float = 999999.0

	for u in me.get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(u):
			continue

		if not is_valid_target(me, u):
			continue

		var d: float = me.global_position.distance_to(u.global_position)

		if d < best_dist:
			best_dist = d
			closest = u

	return closest
