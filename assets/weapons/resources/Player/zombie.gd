# ============================================================
# zombie.gd — BASE CREEP
# ============================================================
extends CharacterBody3D
class_name BaseCreep

# ===============================
# ENUMS
# ===============================
enum AIMode { FOLLOW_OWNER, ATTACK, DEFEND, PATROL, STAY }

# ===============================
# IDENTITY
# ===============================
var team_id      : int    = 1
var owner_id     : int    = -1
var owner_player : Node3D = null
var enemy_base   : Node3D = null
var friendly_base: Node3D = null

# ===============================
# STATS
# ===============================
@export var max_health      : float = 100.0
@export var move_speed      : float = 4.0
@export var attack_range    : float = 2.0
@export var damage          : float = 15.0
@export var attack_cooldown : float = 1.2
@export var detection_range : float = 10.0
@export var aggro_range     : float = 8.0
@export var gold_reward     : int   = 25

# ===============================
# STATE
# ===============================
var health      : float
var ai_mode     : AIMode = AIMode.ATTACK
var target      : Node3D = null
var target_lock : float  = 0.0

const TARGET_LOCK_TIME := 2.5

# ===============================
# INTERNAL
# ===============================
var _attack_timer : float = 0.0
var _is_dead      : bool  = false
var _anim_tree    : AnimationTree = null

# ===============================
# READY
# ===============================
func _ready() -> void:
	health = max_health
	add_to_group("units")
	add_to_group("creeps")

	if owner_player == null:
		ai_mode = AIMode.ATTACK

	_anim_tree = get_node_or_null("AnimationPlayer2/AnimationTree") as AnimationTree
	if _anim_tree == null:
		push_error("[BaseCreep] %s — AnimationTree not found at AnimationPlayer2/AnimationTree!" % name)
	else:
		_anim_tree.active = true

	print("[BaseCreep] %s ready | team_id=%d | owner_id=%d | ai_mode=%s" \
		% [name, team_id, owner_id, AIMode.keys()[ai_mode]])

# ===============================
# PROCESS
# ===============================
func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	_attack_timer = max(0.0, _attack_timer - delta)
	target_lock   = max(0.0, target_lock - delta)

	if target and is_instance_valid(target):
		if target_lock > 0.0:
			_process_target()
			_update_move_blend()
			move_and_slide()
			return
		else:
			target = null

	match ai_mode:
		AIMode.ATTACK:       _tick_attack()
		AIMode.FOLLOW_OWNER: _tick_follow()
		AIMode.DEFEND:       _tick_follow()
		_:
			velocity = Vector3.ZERO

	_update_move_blend()
	move_and_slide()

# ===============================
# ANIMATION
# ===============================
func _update_move_blend() -> void:
	if not _anim_tree:
		return
	var speed_ratio := velocity.length() / move_speed
	_anim_tree.set("parameters/BlendSpace1D/blend_position", speed_ratio)

# ===============================
# TARGETING
# ===============================
func _get_target() -> Node3D:
	var best      : Node3D = null
	var best_dist := detection_range

	for unit in get_tree().get_nodes_in_group("units"):
		if unit == self or not is_instance_valid(unit):
			continue
		if not ("team_id" in unit):
			continue
		if unit.team_id == team_id:
			continue

		var u := unit as Node3D
		if u == null:
			continue

		var d := global_position.distance_to(u.global_position)
		if d < best_dist:
			best      = u
			best_dist = d

	return best

func _commit_target(t: Node3D) -> void:
	if not is_instance_valid(t):
		return
	target      = t
	target_lock = TARGET_LOCK_TIME

func _process_target() -> void:
	if not is_instance_valid(target):
		target = null
		return
	_move_toward(target.global_position)
	if _in_attack_range(target):
		_try_attack(target)

# ===============================
# AI
# ===============================
func _tick_attack() -> void:
	var t := _get_target()
	if t:
		_commit_target(t)
		_process_target()
		return
	if enemy_base:
		_move_toward(enemy_base.global_position)

func _tick_follow() -> void:
	if owner_player == null:
		return
	var t := _get_target()
	if t and global_position.distance_to(t.global_position) < aggro_range:
		_commit_target(t)
		_process_target()
		return
	var dist := global_position.distance_to(owner_player.global_position)
	if dist > 2.0:
		_move_toward(owner_player.global_position)
	else:
		velocity = Vector3.ZERO

# ===============================
# COMBAT
# ===============================
func _try_attack(t: Node3D) -> void:
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_cooldown
	if _anim_tree:
		_anim_tree.set("parameters/attack_shot/request",
				AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if t.has_method("take_damage"):
		t.take_damage(damage, self)

func take_damage(amount: float, instigator: Node = null) -> void:
	if _is_dead:
		return
	health -= amount
	if instigator and instigator is Node3D:
		_commit_target(instigator)
	if health <= 0.0:
		_start_death()

# ===============================
# MOVEMENT
# ===============================
func _move_toward(dest: Vector3) -> void:
	var dir := dest - global_position
	dir.y = 0
	if dir.length() < 0.1:
		velocity = Vector3.ZERO
		return
	dir        = dir.normalized()
	velocity   = dir * move_speed
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 0.15)

func _in_attack_range(t: Node3D) -> bool:
	return is_instance_valid(t) and global_position.distance_to(t.global_position) <= attack_range

# ===============================
# FRIENDLY CHECK
# ===============================
func _is_friendly(node: Node) -> bool:
	if not ("team_id" in node):
		return false
	return node.get("team_id") == team_id

# ===============================
# AI MODE SETTER
# ===============================
func set_ai_mode(mode: AIMode) -> void:
	print("[BaseCreep] %s set_ai_mode: %s → %s" \
		% [name, AIMode.keys()[ai_mode], AIMode.keys()[mode]])
	ai_mode     = mode
	target      = null
	target_lock = 0.0

# ===============================
# FORCED TARGET (tank taunt)
# ===============================
func set_forced_target(new_target: Node3D, duration: float) -> void:
	print("[BaseCreep] %s forced target → %s for %.1fs" % [name, new_target.name, duration])
	target      = new_target
	target_lock = duration

# ===============================
# DEATH + GOLD
# ===============================
func _start_death() -> void:
	if _is_dead:
		return
	_is_dead = true
	velocity = Vector3.ZERO

	print("[BaseCreep] %s died | awarding %d gold to team %d" \
		% [name, gold_reward, 2 if team_id == 1 else 1])

	if _anim_tree:
		_anim_tree.set("parameters/death_shot/request",
				AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

	var ap := get_node_or_null("AnimationPlayer2") as AnimationPlayer
	var dur := 1.5
	if ap and ap.has_animation("die"):
		dur = ap.get_animation("die").length

	await get_tree().create_timer(dur).timeout
	_award_gold()
	queue_free()

func _award_gold() -> void:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm and gm.has_method("add_gold"):
		gm.add_gold(2 if team_id == 1 else 1, gold_reward)
