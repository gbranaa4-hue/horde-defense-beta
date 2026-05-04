extends Node3D

# ===============================
# CONFIG
# ===============================
enum Lane { TOP, MID, BOT }

@export var lane_id: Lane = Lane.MID
@export var team_id: int = 2
@export var enemy_base: Node3D
@export var friendly_base: Node3D
@export var active: bool = false
@export var creep_scene: PackedScene
@export var wave_size: int = 6
@export var wave_interval: float = 30.0
@export var spawn_delay: float = 0.25
@export var wave_spread: float = 1.0
@export var wave_scaling: bool = true
@export var scaling_interval: int = 5

# ===============================
# STATE
# ===============================
var wave_number: int = 0
var timer: float = 0.0
var spawning: bool = false

# ===============================
# READY
# ===============================
func _ready() -> void:
	add_to_group("creep_spawner")
	add_to_group("lane_" + Lane.keys()[lane_id].to_lower())
	timer = wave_interval
	_debug_self()

# ===============================
# PROCESS
# ===============================
func _process(delta: float) -> void:
	if not active:
		return
	if spawning or creep_scene == null:
		return
	if not is_instance_valid(enemy_base):
		push_warning("[Spawner:%s] enemy_base is invalid! Cannot spawn." % name)
		return
	timer -= delta
	if timer <= 0.0:
		timer = wave_interval
		spawn_wave()

# ===============================
# WAVE
# ===============================
func spawn_wave() -> void:
	wave_number += 1
	spawning = true
	print("[Spawner:%s] Wave %d | team:%d" % [name, wave_number, team_id])
	await _spawn_all()
	spawning = false

func _spawn_all() -> void:
	var count: int = wave_size
	if wave_scaling:
		count += wave_number / scaling_interval
	print("[Spawner:%s] Spawning %d creeps" % [name, count])
	for i in range(count):
		var pos := global_position + _line_offset(i, count)
		_spawn_single(pos, i, null)  # wave creeps have no owner (AI-controlled only)
		if i < count - 1:
			await get_tree().create_timer(spawn_delay).timeout

# ===============================
# SPAWN SINGLE (internal)
# ===============================
# owner_player: the player node who purchased this creep, or null for wave creeps
func _spawn_single(pos: Vector3, index: int, owner_player: Node) -> Node:
	if creep_scene == null:
		push_error("[Spawner:%s] creep_scene is null!" % name)
		return null

	var creep = creep_scene.instantiate()
	if creep == null:
		push_error("[Spawner:%s] Failed to instantiate creep!" % name)
		return null

	get_tree().current_scene.add_child(creep)
	creep.global_position = pos

	# --- Core identity ---
	if "team_id" in creep:
		creep.team_id = team_id
	else:
		push_error("[Spawner:%s] Creep missing team_id!" % name)

	if "enemy_base" in creep:
		creep.enemy_base = enemy_base
	else:
		push_error("[Spawner:%s] Creep missing enemy_base!" % name)

	if "friendly_base" in creep:
		creep.friendly_base = friendly_base
	else:
		push_warning("[Spawner:%s] Creep missing friendly_base." % name)

	# --- Player ownership (player-purchased creeps only) ---
	if owner_player != null:
		if "owner_player" in creep:
			creep.owner_player = owner_player
		if "owner_id" in creep:
			creep.owner_id = owner_player.get_instance_id()

	creep.add_to_group("units")
	creep.add_to_group("lane_" + Lane.keys()[lane_id].to_lower())

	_debug_creep(creep, index)
	return creep

# ===============================
# CALLED BY SHOP — spawn a purchased creep
# owner_player: the player node who bought it (used for command locking)
# ===============================
func spawn_purchased_creep(scene: PackedScene, owner_player: Node) -> Node:
	if scene == null:
		push_error("[Spawner:%s] spawn_purchased_creep: scene is null!" % name)
		return null
	if not is_instance_valid(enemy_base):
		push_warning("[Spawner:%s] spawn_purchased_creep: enemy_base invalid!" % name)
		return null

	var creep = scene.instantiate()
	if creep == null:
		push_error("[Spawner:%s] Failed to instantiate purchased creep!" % name)
		return null

	# MUST be before add_child — _ready() fires the instant the node
	# enters the tree, so identity must exist beforehand.
	if "team_id"       in creep: creep.team_id       = team_id
	if "enemy_base"    in creep: creep.enemy_base     = enemy_base
	if "friendly_base" in creep: creep.friendly_base  = friendly_base
	if owner_player != null:
		if "owner_player" in creep: creep.owner_player = owner_player
		if "owner_id"     in creep: creep.owner_id     = owner_player.get_instance_id()

	get_tree().current_scene.add_child(creep)          # _ready() fires here
	creep.global_position = global_position + _line_offset(0, 1)
	creep.add_to_group("units")
	creep.add_to_group("lane_" + Lane.keys()[lane_id].to_lower())

	print("[Spawner:%s] Purchased creep spawned | scene:%s | owner:%s | team:%d" % [
		name,
		scene.resource_path.get_file(),
		owner_player.name if owner_player != null else "NONE",
		team_id
	])
	return creep
# ===============================
# DEBUG
# ===============================
func _debug_self() -> void:
	print("========================================")
	print("[Spawner:%s] INIT" % name)
	print("  team_id      : %d" % team_id)
	print("  lane_id      : %s" % Lane.keys()[lane_id])
	print("  enemy_base   : %s" % _node_name(enemy_base))
	print("  friendly_base: %s" % _node_name(friendly_base))
	print("  wave_size    : %d" % wave_size)
	print("  wave_interval: %.1f" % wave_interval)
	print("  creep_scene  : %s" % ("SET" if creep_scene else "NULL ⚠️"))
	print("========================================")

func _debug_creep(creep: Node, index: int) -> void:
	var eb_name: String = _node_name(creep.enemy_base if "enemy_base" in creep else null)
	var fb_name: String = _node_name(creep.friendly_base if "friendly_base" in creep else null)
	var cteam: int      = creep.team_id if "team_id" in creep else -1
	var owner_name: String = creep.owner_player.name if ("owner_player" in creep and creep.owner_player != null) else "WAVE"
	print("[Spawner:%s] Creep[%d] team:%d | owner:%s | enemy_base:%s | friendly_base:%s" % [
		name, index, cteam, owner_name, eb_name, fb_name
	])
	if is_instance_valid(enemy_base) and "team_id" in enemy_base:
		if enemy_base.team_id == cteam:
			push_warning("[Spawner:%s] ⚠️ Creep team_id matches enemy_base team_id — spawner misconfigured!" % name)

func _node_name(node) -> String:
	if node == null:         return "NULL"
	if not is_instance_valid(node): return "INVALID"
	return str(node.name)

# ===============================
# UTIL
# ===============================
func _line_offset(i: int, count: int) -> Vector3:
	var right := -global_transform.basis.x
	var half := (count - 1) * wave_spread * 0.5
	return right * (i * wave_spread - half)

# ===============================
# CALLED BY GAME MANAGER
# ===============================
func start_spawning() -> void:
	active = true
	timer = 3.0
	print("[Spawner:%s] start_spawning() — first wave in 3s" % name)
