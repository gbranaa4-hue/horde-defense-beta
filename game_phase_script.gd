extends Node

# ===============================
# CONFIG
# ===============================
@export var starting_money              : int   = 1000
@export var prep_time                   : float = 180.0
@export var atmosphere_transition_time  : float = 4.0

@export var fog_density                 : float = 0.008
@export var fog_color                   : Color = Color(0.6, 0.65, 0.75, 1.0)

@export var scary_sound_volume_db       : float = -6.0   # adjust in inspector
@export var scary_sound                 : AudioStreamPlayer = null
@export var night_ambience              : AudioStreamPlayer = null

# ===============================
# NODE REFS
# ===============================
@onready var world_env : WorldEnvironment  = $WorldEnvironment
@onready var sun       : DirectionalLight3D = $DirectionalLight3D

# ===============================
# STATE
# ===============================
var team_money   : Dictionary = {1: 0, 2: 0}
var team_ready   : Dictionary = {1: false, 2: false}
var prep_timer   : float = 0.0
var match_started: bool  = false
var creep_upgrades: Dictionary = {1: [], 2: []}

var _day_fog_density : float
var _atmo_tween      : Tween = null

# ===============================
# SIGNALS
# ===============================
signal money_changed(team: int, amount: int)
signal ready_updated(team: int, ready: bool)
signal prep_time_updated(time_left: float)
signal match_started_signal()
signal show_phase_label(text: String, fade_out: bool)

# ===============================
# READY
# ===============================
func _ready() -> void:
	add_to_group("game_manager")
	set_process(true)
	_init_money()
	_cache_day_environment()
	show_phase_label.emit("DAY", false)
	print("🟢 GameManager ready — PREP PHASE")

# ===============================
# CACHE DAY ENVIRONMENT
# ===============================
func _cache_day_environment() -> void:
	if not is_instance_valid(world_env):
		push_warning("GameManager: WorldEnvironment missing.")
		return
	_day_fog_density = world_env.environment.fog_density

# ===============================
# PROCESS
# ===============================
func _process(delta: float) -> void:
	if match_started:
		return
	prep_timer += delta
	var time_left : float = maxf(prep_time - prep_timer, 0.0)
	prep_time_updated.emit(time_left)
	if time_left == 0.0:
		_start_match()

# ===============================
# INPUT — Space/Enter also readies
# ===============================
func _input(event: InputEvent) -> void:
	if match_started:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			if not team_ready.get(1, false):
				set_team_ready(1, true)

# ===============================
# READY SYSTEM
# ===============================
func set_team_ready(team_id: int, ready: bool = true) -> void:
	if match_started:
		return
	if not team_ready.has(team_id):
		return
	team_ready[team_id] = ready
	ready_updated.emit(team_id, ready)
	# Start immediately when player hits ready — don't wait for timer
	_start_match()

# ===============================
# MATCH START
# ===============================
func _start_match() -> void:
	if match_started:
		return
	match_started = true
	set_process(false)
	print("🔥 MATCH STARTED")
	# Emit -1 so HUD hides the timer entirely
	prep_time_updated.emit(-1.0)
	match_started_signal.emit()
	show_phase_label.emit("NIGHT", true)
	_trigger_fog()
	_play_sounds()
	_activate_spawners()

# ===============================
# FOG
# ===============================
func _trigger_fog() -> void:
	if not is_instance_valid(world_env):
		push_warning("GameManager: WorldEnvironment missing.")
		return

	var env : Environment = world_env.environment
	var t   : float       = atmosphere_transition_time

	if _atmo_tween and _atmo_tween.is_valid():
		_atmo_tween.kill()

	_atmo_tween = create_tween()
	_atmo_tween.set_parallel(true)
	_atmo_tween.set_ease(Tween.EASE_IN_OUT)
	_atmo_tween.set_trans(Tween.TRANS_SINE)

	env.fog_enabled = true
	env.fog_density = 0.0
	_atmo_tween.tween_property(env, "fog_density",     fog_density, t)
	_atmo_tween.tween_property(env, "fog_light_color", fog_color,   t)

# ===============================
# SOUNDS
# ===============================
func _play_sounds() -> void:
	if is_instance_valid(scary_sound):
		scary_sound.volume_db = scary_sound_volume_db
		scary_sound.play()
	else:
		push_warning("GameManager: No scary_sound assigned.")

	if is_instance_valid(night_ambience):
		night_ambience.play()
	else:
		push_warning("GameManager: No night_ambience assigned.")

# ===============================
# SPAWNERS
# ===============================
func _activate_spawners() -> void:
	for s in get_tree().get_nodes_in_group("creep_spawner"):
		if not is_instance_valid(s):
			continue
		if "active" in s:
			s.active = true
		if s.has_method("start_spawning"):
			s.start_spawning()

# ===============================
# MONEY
# ===============================
func _init_money() -> void:
	team_money[1] = starting_money
	team_money[2] = starting_money
	money_changed.emit(1, team_money[1])
	money_changed.emit(2, team_money[2])

func spend_gold(team_id: int, amount: int) -> bool:
	if not team_money.has(team_id):
		return false
	if team_money[team_id] < amount:
		return false
	team_money[team_id] -= amount
	money_changed.emit(team_id, team_money[team_id])
	return true

func award_gold(team_id: int, amount: int) -> void:
	if not team_money.has(team_id):
		return
	team_money[team_id] += amount
	money_changed.emit(team_id, team_money[team_id])

func get_gold(team_id: int) -> int:
	return team_money.get(team_id, 0)

# ===============================
# ADD GOLD (alias used by BaseCreep)
# ===============================
func add_gold(team_id: int, amount: int) -> void:
	award_gold(team_id, amount)

# ===============================
# CREEP UPGRADES
# ===============================
func add_creep_upgrade(team_id: int, upgrade: Dictionary) -> void:
	if not creep_upgrades.has(team_id):
		return
	creep_upgrades[team_id].append(upgrade)
	for unit in get_tree().get_nodes_in_group("units"):
		if "team_id" in unit and unit.team_id == team_id:
			if unit.has_method("apply_upgrade"):
				unit.apply_upgrade(upgrade["stat"], upgrade["amount"])
	print("[GameManager] Creep upgrade T%d: %s" % [team_id, upgrade["label"]])

func get_creep_upgrades(team_id: int) -> Array:
	return creep_upgrades.get(team_id, [])
