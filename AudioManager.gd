# ============================================================
# AudioManager.gd — Godot 4 Audio System (Autoload as "AudioManager")
# Add this file as an Autoload in Project Settings:
#   Name: AudioManager   Path: res://AudioManager.gd
# ============================================================
extends Node

# ===============================
# VOLUME STATE
# ===============================
var master_volume : float = 1.0   # not yet wired to a bus; reserved for UI
var sfx_volume    : float = 0.7

var debug_mode : bool = false

# ===============================
# POOL CONFIG
# ===============================
const POOL_SIZE      : int   = 24     # raise if you have many simultaneous sounds
const MAX_DISTANCE   : float = 40.0
const REF_DISTANCE   : float = 1.0    # distance at which volume_db is exact

# ===============================
# INTERNALS
# ===============================
var _pool      : Array[AudioStreamPlayer3D] = []
var _pool_head : int = 0               # points to the oldest / most-likely-done slot

const SFX_BUS_NAME := "SFX"
var _sfx_bus_idx : int = 0

# ===============================
# READY
# ===============================
func _ready() -> void:
	_ensure_sfx_bus()
	_build_pool()
	print("[AudioManager] Ready | pool=%d | sfx_bus_idx=%d" % [POOL_SIZE, _sfx_bus_idx])

# ---------------------------------------------------------------
# Make sure an "SFX" bus exists and cache its index.
# AudioServer.bus_exists() does NOT exist in Godot 4 — we iterate
# manually instead.
# ---------------------------------------------------------------
func _ensure_sfx_bus() -> void:
	_sfx_bus_idx = -1
	for i in range(AudioServer.bus_count):
		if AudioServer.get_bus_name(i) == SFX_BUS_NAME:
			_sfx_bus_idx = i
			break

	if _sfx_bus_idx == -1:
		# Bus doesn't exist yet — create it and route to Master
		AudioServer.add_bus()
		_sfx_bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_sfx_bus_idx, SFX_BUS_NAME)
		AudioServer.set_bus_send(_sfx_bus_idx, "Master")
		print("[AudioManager] Created '%s' bus at index %d" % [SFX_BUS_NAME, _sfx_bus_idx])

	# Apply initial volume
	_apply_sfx_volume()

func _build_pool() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer3D.new()
		p.bus            = SFX_BUS_NAME
		p.max_distance   = MAX_DISTANCE
		p.unit_size      = REF_DISTANCE
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool.append(p)

# ===============================
# VOLUME HELPERS
# ===============================
func _linear_to_db(v: float) -> float:
	if v <= 0.0: return -80.0
	return 20.0 * log(v) / log(10.0)

func _db_to_linear(db: float) -> float:
	return pow(10.0, db / 20.0)

func _apply_sfx_volume() -> void:
	if _sfx_bus_idx >= 0:
		AudioServer.set_bus_volume_db(_sfx_bus_idx, _linear_to_db(sfx_volume))

# ===============================
# PUBLIC VOLUME API
# ===============================
func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_sfx_volume()

func get_sfx_volume() -> float:
	return sfx_volume

func set_debug(enabled: bool) -> void:
	debug_mode = enabled

# ===============================
# POOL SLOT SELECTION
# ===============================
# Prefer a slot that has finished playing; fall back to the oldest slot
# (round-robin head). This avoids cutting off sounds that are still audible.
func _acquire_slot() -> AudioStreamPlayer3D:
	# Fast path: scan forward from head for a free slot
	for i in range(POOL_SIZE):
		var idx := (_pool_head + i) % POOL_SIZE
		if not _pool[idx].playing:
			_pool_head = (idx + 1) % POOL_SIZE
			return _pool[idx]

	# All slots busy — evict the oldest (head) slot
	var p := _pool[_pool_head]
	_pool_head = (_pool_head + 1) % POOL_SIZE
	p.stop()
	return p

# ===============================
# PLAY 3D SOUND
# Called by BaseCreep (and anything else that needs spatialized audio).
# volume_offset_db is added on top of the bus volume already set, so
# pass 0.0 for a "normal" sound, positive to boost, negative to duck.
# ===============================
func play_3d_sound(
		sound          : AudioStream,
		world_position : Vector3,
		volume_offset_db : float = 0.0,
		pitch          : float   = 1.0
) -> void:
	if not is_instance_valid(sound):
		if debug_mode:
			push_warning("[AudioManager] play_3d_sound called with null stream")
		return

	var p := _acquire_slot()

	# The SFX bus already carries sfx_volume; volume_offset_db is a per-sound
	# trim so the designer can make a death scream louder than footsteps.
	p.stream          = sound
	p.global_position = world_position
	p.pitch_scale     = clampf(pitch, 0.1, 4.0)
	p.volume_db       = volume_offset_db   # offset relative to bus level
	p.play()

	if debug_mode:
		var sname := sound.resource_path.get_file() if sound.resource_path != "" else "(no path)"
		print("[AudioManager] 3D '%s' pos=%s vol_offset=%.1f dB pitch=%.2f" \
			% [sname, world_position, volume_offset_db, pitch])

# ===============================
# PLAY 2D (UI / MUSIC / NON-SPATIAL) SOUND
# Uses a temporary player that self-destructs when done.
# ===============================
func play_2d_sound(
		sound            : AudioStream,
		volume_offset_db : float = 0.0,
		pitch            : float = 1.0
) -> void:
	if not is_instance_valid(sound):
		return

	var p := AudioStreamPlayer.new()
	p.stream      = sound
	p.bus         = SFX_BUS_NAME
	p.volume_db   = volume_offset_db
	p.pitch_scale = clampf(pitch, 0.1, 4.0)
	add_child(p)
	p.play()
	# Use a lambda so we don't hold a dangling reference if the manager is freed
	p.finished.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
	)
	
