# ============================================================
# tank_creep.gd
# 🪨 TANK — High HP, periodically taunts nearby enemy creeps.
# ============================================================
extends BaseCreep

# ===============================
# EXPORTS
# ===============================
@export var taunt_radius   : float = 6.0
@export var taunt_cooldown : float = 8.0
@export var taunt_duration : float = 3.0

# ===============================
# STATE
# ===============================
var _taunt_timer : float = 0.0

# ===============================
# READY
# ===============================
func _ready() -> void:
	max_health      = 300.0
	move_speed      = 1.8
	damage          = 8.0
	attack_range    = 2.2
	attack_cooldown = 1.5
	gold_reward     = 40
	super._ready()
	_taunt_timer = taunt_cooldown * randf_range(0.3, 0.7)
	print("[Tank] spawned | owner_id=%d | team_id=%d" % [owner_id, team_id])

# ===============================
# PHYSICS PROCESS
# ===============================
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _is_dead:
		return
	_taunt_timer -= delta
	if _taunt_timer <= 0.0:
		_do_taunt()
		_taunt_timer = taunt_cooldown

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
	print("[Tank] died | awarding %d gold" % gold_reward)
	var ap  := get_node_or_null("AnimationPlayer2") as AnimationPlayer
	var dur := 1.5
	if ap and ap.has_animation("die"):
		dur = ap.get_animation("die").length
	await get_tree().create_timer(dur).timeout
	_award_gold()
	queue_free()

# ===============================
# TAUNT
# ===============================
func _do_taunt() -> void:
	var taunted := 0
	for u in get_tree().get_nodes_in_group("creeps"):
		if not is_instance_valid(u): continue
		if u == self: continue
		if not (u is Node3D): continue
		if _is_friendly(u): continue
		if not u.has_method("set_forced_target"): continue
		var dist := global_position.distance_to((u as Node3D).global_position)
		if dist <= taunt_radius:
			u.set_forced_target(self, taunt_duration)
			taunted += 1
	print("[Tank] taunt fired | taunted %d enemy creep(s)" % taunted)
	_play_taunt_vfx()

func _play_taunt_vfx() -> void:
	var vfx := get_node_or_null("TauntVFX")
	if is_instance_valid(vfx) and vfx.has_method("restart"):
		vfx.restart()
