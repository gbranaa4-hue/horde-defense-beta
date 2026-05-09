extends Node3D
@export var base_a_path: NodePath
@export var base_b_path: NodePath
@export var color: Color = Color(1.0, 0.45, 0.0, 0.85)
@export var width: float = 0.4
@export var segments: int = 20
@export var arc_height: float = 30.0

# Particle trail settings
@export var particle_count: int = 12
@export var particle_speed: float = 0.4        # 0–1 per second along the arc
@export var particle_size_min: float = 0.3
@export var particle_size_max: float = 0.9
@export var particle_trail_length: float = 0.06 # how long each streak is (in t units)

var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _base_a: Node3D
var _base_b: Node3D

# Each particle: [t_position, t_offset, size_scale]
var _particles: Array = []
var _time: float = 0.0

func _ready() -> void:
	_base_a = get_node_or_null(base_a_path)
	_base_b = get_node_or_null(base_b_path)
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance  = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled           = true
	mat.emission                   = color
	mat.emission_energy_multiplier = 3.0
	mat.albedo_color               = color
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)

	# Stagger particles evenly + random size
	for i in particle_count:
		_particles.append({
			"t":      float(i) / float(particle_count),
			"size":   randf_range(particle_size_min, particle_size_max),
			"speed":  particle_speed * randf_range(0.8, 1.2)   # slight speed variation
		})

func _process(delta: float) -> void:
	if not is_instance_valid(_base_a) or not is_instance_valid(_base_b):
		return
	_time += delta

	# Advance particles
	for p in _particles:
		p["t"] = fmod(p["t"] + p["speed"] * delta, 1.0)

	_immediate_mesh.clear_surfaces()
	var cam     := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if is_instance_valid(cam) else Vector3.UP * 999

	# ── 1. Arc ribbon ────────────────────────────────────────────────
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var t0 := float(i)     / float(segments)
		var t1 := float(i + 1) / float(segments)
		_add_ribbon_quad(t0, t1, cam_pos, color, width)
	_immediate_mesh.surface_end()

	# ── 2. Particle streaks ──────────────────────────────────────────
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in _particles:
		var t_head: float = p["t"]
		var t_tail: float = max(t_head - particle_trail_length, 0.0)
		var sz:     float = p["size"]

		# Bright core streak
		var streak_color := Color(
			min(color.r * 1.8, 1.0),
			min(color.g * 1.8, 1.0),
			min(color.b * 1.8, 1.0),
			1.0
		)
		_add_ribbon_quad(t_tail, t_head, cam_pos, streak_color, width * sz)

		# Soft glowing halo around the head
		var head_pos := _arc_point(t_head)
		_add_billboard_quad(head_pos, cam_pos, width * sz * 1.6, color)
	_immediate_mesh.surface_end()

# ── Helpers ──────────────────────────────────────────────────────────

func _add_ribbon_quad(t0: float, t1: float, cam_pos: Vector3,
		col: Color, w: float) -> void:
	var p0    := _arc_point(t0)
	var p1    := _arc_point(t1)
	var mid   := (p0 + p1) * 0.5
	var dir   := (p1 - p0).normalized()
	var right := dir.cross((cam_pos - mid).normalized()).normalized() * (w * 0.5)
	var v0 := p0 - right;  var v1 := p0 + right
	var v2 := p1 - right;  var v3 := p1 + right
	_immediate_mesh.surface_set_color(col); _immediate_mesh.surface_add_vertex(v0)
	_immediate_mesh.surface_set_color(col); _immediate_mesh.surface_add_vertex(v1)
	_immediate_mesh.surface_set_color(col); _immediate_mesh.surface_add_vertex(v2)
	_immediate_mesh.surface_set_color(col); _immediate_mesh.surface_add_vertex(v1)
	_immediate_mesh.surface_set_color(col); _immediate_mesh.surface_add_vertex(v3)
	_immediate_mesh.surface_set_color(col); _immediate_mesh.surface_add_vertex(v2)

func _add_billboard_quad(pos: Vector3, cam_pos: Vector3,
		size: float, col: Color) -> void:
	var to_cam := (cam_pos - pos).normalized()
	var up     := Vector3.UP
	if abs(to_cam.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var right  := to_cam.cross(up).normalized() * (size * 0.5)
	var up_vec := to_cam.cross(right).normalized() * (size * 0.5)
	var v0 := pos - right - up_vec;  var v1 := pos + right - up_vec
	var v2 := pos - right + up_vec;  var v3 := pos + right + up_vec
	_immediate_mesh.surface_set_color(col); _immediate_mesh.surface_add_vertex(v0)
	_immediate_mesh.surface_set_color(col); _immediate_mesh.surface_add_vertex(v1)
	_immediate_mesh.surface_set_color(col); _immediate_mesh.surface_add_vertex(v2)
	_immediate_mesh.surface_set_color(col); _immediate_mesh.surface_add_vertex(v1)
	_immediate_mesh.surface_set_color(col); _immediate_mesh.surface_add_vertex(v3)
	_immediate_mesh.surface_set_color(col); _immediate_mesh.surface_add_vertex(v2)

func _arc_point(t: float) -> Vector3:
	var a := _base_a.global_position
	var b := _base_b.global_position
	var p := a.lerp(b, t)
	p.y += arc_height * 4.0 * t * (1.0 - t)
	return p
