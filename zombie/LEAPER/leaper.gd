# ============================================================
# leaper_creep.gd
# 🕷️ LEAPER — Crawling zombie that scales walls and vaults at
#             distant targets, applying a movement slow on hit.
# ============================================================
extends BaseCreep

# ===============================
# EXPORTS
# ===============================
@export var leap_range       : float = 9.0
@export var leap_min_range   : float = 2.5
@export var leap_cooldown    : float = 7.0
@export var leap_speed       : float = 18.0
@export var leap_arc_height  : float = 6.0
@export var slow_factor      : float = 0.45
@export var slow_duration    : float = 2.5

# ===============================
# STATE
# ===============================
var _leap_timer   : float   = 0.0
var _is_leaping   : bool    = false
var _leap_airtime : float   = 0.0
var _leap_target  : Node3D  = null
var _is_climbing  : bool    = false

const LEAP_MIN_AIRTIME := 0.3

# ===============================
# READY
# ===============================
func _ready() -> void:
	max_health      = 120.0
	move_speed      = 3.2
	damage          = 14.0
	attack_range    = 1.4
	attack_cooldown = 1.1
	gold_reward     = 25
	super._ready()
	_leap_timer = leap_cooldown * randf_range(0.2, 0.6)

	var climb_area := get_node_or_null("ClimbArea3D") as Area3D
	if climb_area:
		climb_area.body_entered.connect(_on_wall_entered)
		climb_area.body_exited.connect(_on_wall_exited)

	print("[Leaper] spawned | owner_id=%d | team_id=%d" % [owner_id, team_id])

# ===============================
# PHYSICS PROCESS
# ===============================
func _physics_process(delta: float) -> void:
	if _is_leaping:
		_leap_airtime += delta
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		move_and_slide()
		if _leap_airtime >= LEAP_MIN_AIRTIME and is_on_floor():
			_on_leap_land()
		return

	if _is_climbing:
		velocity.y = clampf(velocity.y, -1.0, 1.0)

	super._physics_process(delta)

	if _is_dead:
		return

	_leap_timer -= delta
	if _leap_timer <= 0.0:
		_try_leap()

# ===============================
# ATTACK
# ===============================
func _try_attack(t: Node3D) -> void:
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_cooldown
	if _anim_tree:
		_anim_tree.set(
			"parameters/attack_shot/request",
			AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if t.has_method("take_damage"):
		t.take_damage(damage, self)

# ===============================
# TAKE DAMAGE
# ===============================
func take_damage(amount: float, instigator: Node = null) -> void:
	if _is_dead:
		return
	health -= amount
	if instigator != null and instigator is Node3D and is_instance_valid(instigator):
		_commit_target(instigator as Node3D)
	if health <= 0.0:
		_start_death()

# ===============================
# DEATH
# ===============================
func _start_death() -> void:
	if _is_dead:
		return
	_is_dead    = true
	_is_leaping = false
	velocity    = Vector3.ZERO
	set_physics_process(false)
	if _anim_tree:
		_anim_tree.set(
			"parameters/death_shot/request",
			AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	print("[Leaper] died | awarding %d gold" % gold_reward)
	var ap  := get_node_or_null("AnimationPlayer2") as AnimationPlayer
	var dur := 1.5
	if ap and ap.has_animation("die"):
		dur = ap.get_animation("die").length
	await get_tree().create_timer(dur).timeout
	_award_gold()
	queue_free()

# ===============================
# LEAP
# ===============================
func _try_leap() -> void:
	print("[Leaper] _try_leap called | target=%s | is_leaping=%s" % [target, _is_leaping])

	var t : Node3D = target
	if not is_instance_valid(t):
		print("[Leaper] BAIL: no valid target")
		_leap_timer = 1.0   # retry soon
		return

	var dist := global_position.distance_to(t.global_position)
	print("[Leaper] dist=%.1f | leap_range=%.1f | leap_min_range=%.1f" % [dist, leap_range, leap_min_range])

	if dist > leap_range:
		print("[Leaper] BAIL: target too far")
		_leap_timer = 1.0
		return
	if dist < leap_min_range:
		print("[Leaper] BAIL: target too close (will melee)")
		_leap_timer = leap_cooldown
		return

	_is_leaping   = true
	_leap_airtime = 0.0
	_leap_target  = t
	_leap_timer   = leap_cooldown

	var flat_dir := Vector3(
		t.global_position.x - global_position.x,
		0.0,
		t.global_position.z - global_position.z
	).normalized()

	velocity = flat_dir * leap_speed + Vector3.UP * leap_arc_height
	print("[Leaper] LEAPING | vel=%s" % velocity)

	if _anim_tree:
		_anim_tree.set(
			"parameters/leap_shot/request",
			AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

	_play_leap_vfx()

func _on_leap_land() -> void:
	_is_leaping = false
	print("[Leaper] landed")
	if is_instance_valid(_leap_target):
		if _leap_target.has_method("take_damage"):
			_leap_target.take_damage(damage, self)
		if _leap_target.has_method("apply_slow"):
			_leap_target.apply_slow(slow_factor, slow_duration)
			print("[Leaper] applied %.0f%% slow for %.1fs" % [(1.0 - slow_factor) * 100, slow_duration])
	_leap_target = null

# ===============================
# WALL CLIMB
# ===============================
func _on_wall_entered(_body: Node) -> void:
	_is_climbing = true

func _on_wall_exited(_body: Node) -> void:
	_is_climbing = false

# ===============================
# VFX
# ===============================
func _play_leap_vfx() -> void:
	var vfx := get_node_or_null("LeapVFX")
	if is_instance_valid(vfx) and vfx.has_method("restart"):
		vfx.restart()
