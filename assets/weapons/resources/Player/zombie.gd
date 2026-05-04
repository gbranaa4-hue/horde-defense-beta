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
var team_id       : int    = 1
var owner_id      : int    = -1
var owner_player  : Node3D = null
var enemy_base    : Node3D = null
var friendly_base : Node3D = null

# ===============================
# STATS
# ===============================
@export var max_health      : float = 100.0
@export var move_speed      : float = 4.0
@export var attack_range    : float = 2.0
@export var damage          : float = 15.0
@export var attack_cooldown : float = 1.2
@export var detection_range : float = 14.0
@export var aggro_range     : float = 8.0
@export var gold_reward     : int   = 25

# ===============================
# AI STATE
# ===============================
var health      : float
var ai_mode     : AIMode  = AIMode.ATTACK
var target      : Node3D  = null
var target_lock : float   = 0.0

const TARGET_LOCK_TIME := 2.5

var move_target     : Vector3 = Vector3.ZERO
var has_move_target : bool    = false

# Patrol
var patrol_points     : Array[Vector3] = []
var _patrol_index     : int            = 0
var _patrol_direction : int            = 1

# ===============================
# INTERNAL
# ===============================
var _attack_timer : float = 0.0
var _is_dead      : bool  = false
var _anim_tree    : AnimationTree = null

# Tracks whether we INTEND to be moving this frame.
# Set true by _move_toward(), false by any idle branch.
# Used by _update_move_blend() so we never rely on post-slide velocity.
var _intends_to_move : bool = false

# ===============================
# READY
# ===============================
func _ready() -> void:
	health = max_health
	add_to_group("units")
	add_to_group("creeps")

	# Try common locations for AnimationTree
	_anim_tree = get_node_or_null("AnimationTree") as AnimationTree
	if _anim_tree == null:
		_anim_tree = get_node_or_null("AnimationPlayer2/AnimationTree") as AnimationTree
	if _anim_tree == null:
		# Search all children recursively
		for child in get_children():
			if child is AnimationTree:
				_anim_tree = child as AnimationTree
				break
			for grandchild in child.get_children():
				if grandchild is AnimationTree:
					_anim_tree = grandchild as AnimationTree
					break

	if _anim_tree == null:
		push_warning("[BaseCreep] %s — AnimationTree not found anywhere in children." % name)
	else:
		# Make sure it is pointing at a valid AnimationPlayer
		if _anim_tree.anim_player == NodePath(""):
			var ap := get_node_or_null("AnimationPlayer2") as AnimationPlayer
			if ap:
				_anim_tree.anim_player = _anim_tree.get_path_to(ap)
		_anim_tree.active = true
		print("[BaseCreep] %s AnimationTree found at: %s" % [name, _anim_tree.get_path()])

	await get_tree().process_frame
	_find_bases()

	print("[BaseCreep] %s ready | team=%d | owner=%d | mode=%s" \
		% [name, team_id, owner_id, AIMode.keys()[ai_mode]])

# ===============================
# BASE DISCOVERY
# ===============================
func _find_bases() -> void:
	for b in get_tree().get_nodes_in_group("bases"):
		if not ("team_id" in b): continue
		if b.team_id == team_id:
			friendly_base = b as Node3D
		else:
			enemy_base = b as Node3D

# ===============================
# PHYSICS PROCESS
# ===============================
func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	_intends_to_move = false   # reset each frame; _move_toward() sets it true

	_attack_timer = max(0.0, _attack_timer - delta)
	target_lock   = max(0.0, target_lock - delta)

	if target_lock <= 0.0:
		target = null

	if target != null and is_instance_valid(target):
		_process_target()
		_update_move_blend()
		move_and_slide()
		return

	if has_move_target:
		var dist_to_dest := global_position.distance_to(move_target)
		var nearby := _get_target_near(move_target, detection_range)
		if nearby:
			has_move_target = false
			_commit_target(nearby)
			_process_target()
		elif dist_to_dest > 1.5:
			_move_toward(move_target)
		else:
			has_move_target = false
			var t := _get_target()
			if t: _commit_target(t)
		_update_move_blend()
		move_and_slide()
		return

	match ai_mode:
		AIMode.ATTACK:       _tick_attack()
		AIMode.FOLLOW_OWNER: _tick_follow()
		AIMode.DEFEND:       _tick_follow()
		AIMode.PATROL:       _tick_patrol()
		AIMode.STAY:         _tick_stay()

	_update_move_blend()
	move_and_slide()

# ===============================
# ANIMATION BLEND
# ===============================
func _update_move_blend() -> void:
	if not _anim_tree:
		return
	# Use the intent flag — not post-slide velocity — to decide blend value.
	# This means "did the AI actually ask to move this frame?"
	var blend : float = 0.0
	if _intends_to_move:
		# Use horizontal velocity magnitude relative to move_speed for smooth blend
		var flat_speed : float = Vector2(velocity.x, velocity.z).length()
		blend = clampf(flat_speed / maxf(move_speed, 0.01), 0.0, 1.0)
		# Clamp tiny values to zero to avoid near-idle blend bleed
		if blend < 0.1:
			blend = 0.0
	_anim_tree.set("parameters/move_blend/blend_position", blend)

# ===============================
# TARGETING
# ===============================
func _get_target() -> Node3D:
	return _get_target_near(global_position, detection_range)

func _get_target_near(origin: Vector3, radius: float) -> Node3D:
	var best      : Node3D = null
	var best_dist : float  = radius

	for unit in get_tree().get_nodes_in_group("units"):
		if unit == self or not is_instance_valid(unit): continue
		if not ("team_id" in unit): continue
		if int(unit.team_id) == team_id: continue
		var u := unit as Node3D
		if u == null: continue
		var d := origin.distance_to(u.global_position)
		if d < best_dist:
			best      = u
			best_dist = d

	return best

func _commit_target(t: Node3D) -> void:
	if not is_instance_valid(t): return
	target      = t
	target_lock = TARGET_LOCK_TIME

func _process_target() -> void:
	if not is_instance_valid(target):
		target = null
		return
	if _in_attack_range(target):
		velocity = Vector3.ZERO
		# _intends_to_move stays false — we are standing still to attack
		_try_attack(target)
	else:
		_move_toward(target.global_position)

# ===============================
# AI TICKS
# ===============================
func _tick_attack() -> void:
	var t := _get_target()
	if t:
		_commit_target(t)
		_process_target()
		return
	if is_instance_valid(enemy_base):
		_move_toward(enemy_base.global_position)
	else:
		velocity = Vector3.ZERO

func _tick_follow() -> void:
	var t := _get_target()
	if t and global_position.distance_to(t.global_position) < aggro_range:
		_commit_target(t)
		_process_target()
		return
	if not is_instance_valid(owner_player):
		velocity = Vector3.ZERO
		return
	var dist := global_position.distance_to(owner_player.global_position)
	if dist > 2.5:
		_move_toward(owner_player.global_position)
	else:
		velocity = Vector3.ZERO

func _tick_patrol() -> void:
	if patrol_points.is_empty():
		velocity = Vector3.ZERO
		return

	var t := _get_target()
	if t and global_position.distance_to(t.global_position) < aggro_range:
		_commit_target(t)
		_process_target()
		return

	var dest := patrol_points[_patrol_index]
	var dist := global_position.distance_to(dest)

	if dist < 1.2:
		_patrol_index += _patrol_direction
		if _patrol_index >= patrol_points.size():
			_patrol_index     = patrol_points.size() - 2
			_patrol_direction = -1
		elif _patrol_index < 0:
			_patrol_index     = 1
			_patrol_direction = 1
		_patrol_index = clamp(_patrol_index, 0, patrol_points.size() - 1)
	else:
		_move_toward(dest)

func _tick_stay() -> void:
	velocity = Vector3.ZERO

func set_patrol_points(points: Array) -> void:
	patrol_points.clear()
	for p in points:
		patrol_points.append(p as Vector3)
	_patrol_index     = 0
	_patrol_direction = 1

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
	if instigator != null and instigator is Node3D and is_instance_valid(instigator):
		_commit_target(instigator as Node3D)
	if health <= 0.0:
		_start_death()

# ===============================
# MOVEMENT
# ===============================
func _move_toward(dest: Vector3) -> void:
	var dir := dest - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		velocity = Vector3.ZERO
		return
	dir              = dir.normalized()
	velocity         = dir * move_speed
	_intends_to_move = true   # signal to blend that we are actually moving
	rotation.y       = lerp_angle(rotation.y, atan2(dir.x, dir.z), 0.15)

func _in_attack_range(t: Node3D) -> bool:
	return is_instance_valid(t) and \
		global_position.distance_to(t.global_position) <= attack_range

# ===============================
# FRIENDLY CHECK
# ===============================
func _is_friendly(node: Node) -> bool:
	if not ("team_id" in node): return false
	return int(node.get("team_id")) == team_id

# ===============================
# AI MODE SETTER
# ===============================
func set_ai_mode(mode: AIMode) -> void:
	print("[BaseCreep] %s mode: %s → %s" \
		% [name, AIMode.keys()[ai_mode], AIMode.keys()[mode]])
	ai_mode         = mode
	target          = null
	target_lock     = 0.0
	has_move_target = false

# ===============================
# FORCED TARGET (tank taunt)
# ===============================
func set_forced_target(new_target: Node3D, duration: float) -> void:
	print("[BaseCreep] %s forced → %s for %.1fs" % [name, new_target.name, duration])
	target      = new_target
	target_lock = duration

# ===============================
# DEATH + GOLD
# ===============================
func _start_death() -> void:
	if _is_dead: return
	_is_dead = true
	velocity = Vector3.ZERO
	set_physics_process(false)

	print("[BaseCreep] %s died | awarding %d gold to team %d" \
		% [name, gold_reward, 2 if team_id == 1 else 1])

	if _anim_tree:
		_anim_tree.set("parameters/death_shot/request",
				AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

	var ap  := get_node_or_null("AnimationPlayer2") as AnimationPlayer
	var dur := 1.5
	if ap and ap.has_animation("die"):
		dur = ap.get_animation("die").length

	await get_tree().create_timer(dur).timeout
	_award_gold()
	queue_free()

func _award_gold() -> void:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if not is_instance_valid(gm):
		push_warning("[BaseCreep] _award_gold: game_manager not found!")
		return
	var receiving_team : int = 2 if team_id == 1 else 1
	print("[BaseCreep] %s | my team_id=%d | awarding %d gold to team %d" \
		% [name, team_id, gold_reward, receiving_team])
	gm.award_gold(receiving_team, gold_reward)
