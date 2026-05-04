# ============================================================
# berserker_creep.gd
# ⚔️ BERSERKER — Medium HP, enrages below 40% HP:
#               gains bonus speed + damage until death.
# ============================================================
extends BaseCreep

# ===============================
# EXPORTS
# ===============================
@export var enrage_threshold  : float = 0.4   # fraction of max_health
@export var enrage_speed_mult : float = 1.8
@export var enrage_dmg_mult   : float = 1.6

# ===============================
# STATE
# ===============================
var _enraged       : bool  = false
var _base_speed    : float = 0.0
var _base_damage   : float = 0.0

# ===============================
# READY
# ===============================
func _ready() -> void:
	max_health      = 180.0
	move_speed      = 2.8
	damage          = 18.0
	attack_range    = 1.6
	attack_cooldown = 0.9
	gold_reward     = 30
	super._ready()
	_base_speed  = move_speed
	_base_damage = damage
	print("[Berserker] spawned | owner_id=%d | team_id=%d" % [owner_id, team_id])

# ===============================
# PHYSICS PROCESS
# ===============================
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _is_dead:
		return
	_check_enrage()

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
	_is_dead = true
	velocity = Vector3.ZERO
	set_physics_process(false)
	if _anim_tree:
		_anim_tree.set(
			"parameters/death_shot/request",
			AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	print("[Berserker] died | awarding %d gold" % gold_reward)
	var ap  := get_node_or_null("AnimationPlayer2") as AnimationPlayer
	var dur := 1.5
	if ap and ap.has_animation("die"):
		dur = ap.get_animation("die").length
	await get_tree().create_timer(dur).timeout
	_award_gold()
	queue_free()

# ===============================
# ENRAGE
# ===============================
func _check_enrage() -> void:
	if _enraged:
		return
	if health / max_health <= enrage_threshold:
		_enraged   = true
		move_speed = _base_speed  * enrage_speed_mult
		damage     = _base_damage * enrage_dmg_mult
		print("[Berserker] ENRAGED | speed=%.1f | damage=%.1f" % [move_speed, damage])
		_play_enrage_vfx()

func _play_enrage_vfx() -> void:
	var vfx := get_node_or_null("EnrageVFX")
	if is_instance_valid(vfx) and vfx.has_method("restart"):
		vfx.restart()
