# ============================================================
# BaseTurret.gd
# ============================================================
# All three turrets extend this.
# Handles health, damage scaling, death, team assignment,
# and independent per-turret audio controls.
# ============================================================
extends Node3D
class_name BaseTurret

# ── HEALTH ───────────────────────────────────────────────────
@export_group("Health")
@export var max_health : float = 200.0
@export var armor      : float = 0.0    # flat damage reduction per hit

var health   : float = 0.0
var _is_dead : bool  = false

signal health_changed(current: float, maximum: float)
signal turret_died(turret: Node)

# ── SHARED IDENTITY ──────────────────────────────────────────
var team_id   : int = 1
var level     : int = 1
var max_level : int = 5

signal turret_selected(turret)
signal turret_upgraded(turret)

# ── AUDIO ────────────────────────────────────────────────────
# Each sound slot gets its own AudioStreamPlayer3D child added at runtime.
# Expose everything you'd ever want to tweak in the Inspector.

@export_group("Audio")

@export_subgroup("Fire Sound")
@export var sfx_fire          : AudioStream
@export_range(-80.0, 24.0, 0.5, "suffix:dB")
var sfx_fire_volume_db    : float = 0.0
@export_range(0.1, 4.0, 0.01)
var sfx_fire_pitch        : float = 1.0
@export var sfx_fire_bus      : StringName = &"SFX"
@export var sfx_fire_max_dist : float = 30.0

@export_subgroup("Hit / Impact Sound")
@export var sfx_hit           : AudioStream
@export_range(-80.0, 24.0, 0.5, "suffix:dB")
var sfx_hit_volume_db     : float = 0.0
@export_range(0.1, 4.0, 0.01)
var sfx_hit_pitch         : float = 1.0
@export var sfx_hit_bus       : StringName = &"SFX"
@export var sfx_hit_max_dist  : float = 20.0

@export_subgroup("Death Sound")
@export var sfx_death         : AudioStream
@export_range(-80.0, 24.0, 0.5, "suffix:dB")
var sfx_death_volume_db   : float = 0.0
@export_range(0.1, 4.0, 0.01)
var sfx_death_pitch       : float = 1.0
@export var sfx_death_bus     : StringName = &"SFX"
@export var sfx_death_max_dist: float = 40.0

@export_subgroup("Upgrade Sound")
@export var sfx_upgrade        : AudioStream
@export_range(-80.0, 24.0, 0.5, "suffix:dB")
var sfx_upgrade_volume_db  : float = 0.0
@export_range(0.1, 4.0, 0.01)
var sfx_upgrade_pitch      : float = 1.0
@export var sfx_upgrade_bus    : StringName = &"SFX"
@export var sfx_upgrade_max_dist: float = 20.0

# Internal players — one per slot so sounds never cancel each other out.
var _player_fire    : AudioStreamPlayer3D
var _player_hit     : AudioStreamPlayer3D
var _player_death   : AudioStreamPlayer3D
var _player_upgrade : AudioStreamPlayer3D

# ============================================================
func _base_ready() -> void:
	health = max_health
	add_to_group("turrets")
	add_to_group("towers")
	add_to_group("units")
	_setup_audio()

# ── Audio setup ──────────────────────────────────────────────
func _setup_audio() -> void:
	_player_fire    = _make_player(sfx_fire,    sfx_fire_volume_db,    sfx_fire_pitch,    sfx_fire_bus,    sfx_fire_max_dist)
	_player_hit     = _make_player(sfx_hit,     sfx_hit_volume_db,     sfx_hit_pitch,     sfx_hit_bus,     sfx_hit_max_dist)
	_player_death   = _make_player(sfx_death,   sfx_death_volume_db,   sfx_death_pitch,   sfx_death_bus,   sfx_death_max_dist)
	_player_upgrade = _make_player(sfx_upgrade, sfx_upgrade_volume_db, sfx_upgrade_pitch, sfx_upgrade_bus, sfx_upgrade_max_dist)

func _make_player(stream: AudioStream, vol_db: float, pitch: float,
		bus: StringName, max_dist: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream           = stream
	p.volume_db        = vol_db
	p.pitch_scale      = pitch
	p.bus              = bus
	p.max_distance     = max_dist
	p.autoplay         = false
	add_child(p)
	return p

# ── Public play helpers (call from subclasses) ───────────────

## Play the fire sound. Pass pitch_override to add per-shot variance.
func play_fire_sfx(pitch_override: float = sfx_fire_pitch) -> void:
	_play(_player_fire, pitch_override)

func play_hit_sfx(pitch_override: float = sfx_hit_pitch) -> void:
	_play(_player_hit, pitch_override)

func play_upgrade_sfx() -> void:
	_play(_player_upgrade, sfx_upgrade_pitch)

func _play(player: AudioStreamPlayer3D, pitch: float) -> void:
	if player == null or player.stream == null:
		return
	player.pitch_scale = pitch
	player.play()

# ── DAMAGE / DEATH ───────────────────────────────────────────
func take_damage(amount: float, _instigator: Node = null) -> void:
	if _is_dead: return
	var actual : float = maxf(amount - armor, 1.0)
	health = maxf(health - actual, 0.0)
	health_changed.emit(health, max_health)
	play_hit_sfx()
	if health <= 0.0:
		_die()

func _die() -> void:
	if _is_dead: return
	_is_dead = true
	turret_died.emit(self)
	# Play death sound before the node is freed.
	# Reparent the player to the scene root so it survives queue_free().
	if _player_death and _player_death.stream:
		var root := get_tree().current_scene
		_player_death.reparent(root)
		_player_death.play()
		# Clean up the orphaned player after it finishes.
		_player_death.finished.connect(_player_death.queue_free)
	await get_tree().create_timer(0.4).timeout
	queue_free()

# ── Per-level stat scaling helpers ───────────────────────────
func _dmg_scale() -> float:
	return pow(1.32, level - 1)   # L1=1.0  L5≈3.0

func _rate_scale() -> float:
	return pow(0.88, level - 1)   # faster each level

func _range_bonus() -> float:
	return (level - 1) * 1.8

func _health_scale() -> float:
	return pow(1.37, level - 1)   # L1=1.0  L5≈3.5
