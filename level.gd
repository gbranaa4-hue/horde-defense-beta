extends Node3D

# ===========================
# CONFIG
# ===========================
@export var default_attack_creep: PackedScene   # Your Zombie scene here

const SPAWNER_GROUP := "creep_spawner"

# ===========================
# READY
# ===========================
func _ready() -> void:
	print("=== Level loaded ===")
	_assign_to_spawners()

	# Debug: total spawners found
	var total_spawners = get_tree().get_nodes_in_group(SPAWNER_GROUP).size()
	print("Total spawners found: ", total_spawners)

# ===========================
# ASSIGN SPAWNERS
# ===========================
func _assign_to_spawners() -> void:
	var spawners = get_tree().get_nodes_in_group(SPAWNER_GROUP)
	if spawners.is_empty():
		push_warning("No spawners found in group '%s'" % SPAWNER_GROUP)
		return

	for spawner in spawners:
		_assign_spawner(spawner)

# ===========================
# SAFE ASSIGNMENT TO SPAWNER
# ===========================
func _assign_spawner(spawner: Node) -> void:
	if not is_instance_valid(spawner):
		push_warning("Invalid spawner node")
		return

	# Verify it has a script
	var script = spawner.get_script()
	if not script:
		push_warning("Spawner '%s' has no script attached" % spawner.name)
		return

	# Assign team ID if exported
	if "team_id" in spawner:
		print("Assigning team_id to spawner: ", spawner.name, " -> ", spawner.team_id)

	# Assign enemy base if exported
	if "enemy_base" in spawner:
		var enemy_base = _get_enemy_base_for_team(spawner.team_id)
		spawner.enemy_base = enemy_base
		print("Assigned enemy base: %s -> %s" % [spawner.name, enemy_base.name])

	# Assign default creep scene
	if default_attack_creep and spawner.has_method("set_default_attack_creep"):
		spawner.set_default_attack_creep(default_attack_creep)
		print("✅ Assigned default creep to spawner: %s (Team %d)" % [spawner.name, spawner.team_id])
	else:
		push_warning("Could not assign default creep scene to '%s'" % spawner.name)

	print("✅ Spawner configured: %s → Team %d" % [spawner.name, spawner.team_id])

# ===========================
# HELPER
# ===========================
func _get_enemy_base_for_team(team_id: int) -> Node3D:
	# Example: you should have nodes named "BaseTeam1" and "BaseTeam2"
	for base in get_tree().get_nodes_in_group("bases"):
		if "team_id" in base and base.team_id != team_id:
			return base
	push_warning("No enemy base found for team %d" % team_id)
	return null
