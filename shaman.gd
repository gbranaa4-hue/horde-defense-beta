# ============================================================
# shaman_creep.gd
# 🩹 SHAMAN — Targeted heal every few seconds + passive aura regen.
# ============================================================
extends BaseCreep
class_name ShamanCreep

# ===============================
# EXPORTS
# ===============================
@export var heal_radius   : float = 7.0
@export var heal_amount   : float = 20.0
@export var heal_cooldown : float = 4.0
@export var aura_regen    : float = 2.0  # HP/sec to all nearby friendlies
@export var aura_radius   : float = 5.0

# ===============================
# STATE
# ===============================
var _heal_timer : float = 0.0

# ===============================
# READY
# ===============================
func _ready() -> void:
	max_health      = 80.0
	damage          = 6.0
	move_speed      = 2.0
	attack_cooldown = 1.8
	gold_reward     = 50
	aggro_range     = 5.0
	super._ready()
	_heal_timer = heal_cooldown * randf_range(0.3, 0.7)
	print("[Shaman] spawned | owner_id=%d | team_id=%d" % [owner_id, team_id])

# ===============================
# PHYSICS PROCESS
# ===============================
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _is_dead:
		return

	_heal_timer -= delta
	if _heal_timer <= 0.0:
		_do_targeted_heal()
		_heal_timer = heal_cooldown

	_apply_aura(delta)

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
	print("[Shaman] died | awarding %d gold" % gold_reward)
	var ap  := get_node_or_null("AnimationPlayer2") as AnimationPlayer
	var dur := 1.5
	if ap and ap.has_animation("die"):
		dur = ap.get_animation("die").length
	await get_tree().create_timer(dur).timeout
	_award_gold()
	queue_free()

# ===============================
# HEAL
# ===============================
func _do_targeted_heal() -> void:
	var best      : Node3D = null
	var lowest_hp : float  = INF

	for u in get_tree().get_nodes_in_group("units"):
		if not (u is Node3D) or not _is_friendly(u) or u == self:
			continue
		if not ("health" in u) or not ("max_health" in u):
			continue
		var unit3d := u as Node3D
		var dist   := global_position.distance_to(unit3d.global_position)
		if dist > heal_radius:
			continue
		var hp : float = u.get("health")
		if hp < lowest_hp and (u.get("max_health") - hp) > 0.0:
			lowest_hp = hp
			best      = unit3d

	if is_instance_valid(best):
		var cur_hp : float = best.get("health")
		var max_hp : float = best.get("max_health")
		best.set("health", min(cur_hp + heal_amount, max_hp))
		_play_heal_vfx(best.global_position)
		print("[Shaman] healed %s for %.1f HP" % [best.name, heal_amount])

func _apply_aura(delta: float) -> void:
	for u in get_tree().get_nodes_in_group("units"):
		if not (u is Node3D) or not _is_friendly(u) or u == self:
			continue
		if not ("health" in u) or not ("max_health" in u):
			continue
		var unit3d := u as Node3D
		var dist   := global_position.distance_to(unit3d.global_position)
		if dist <= aura_radius:
			var hp     : float = u.get("health")
			var max_hp : float = u.get("max_health")
			u.set("health", min(hp + aura_regen * delta, max_hp))

func _play_heal_vfx(world_pos: Vector3) -> void:
	var vfx := get_node_or_null("HealVFX")
	if is_instance_valid(vfx):
		vfx.global_position = world_pos
		if vfx.has_method("restart"):
			vfx.restart()
