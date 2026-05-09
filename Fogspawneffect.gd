# ============================================================
# FogSpawnEffect.gd — AUTOLOAD as "FogSpawnEffect"
# Uses Godot 4 FogVolume for physically accurate volumetric fog.
# Requires Forward+ renderer + Volumetric Fog in WorldEnvironment.
# ============================================================
extends Node

@export var fog_lifetime     : float = 14.0
@export var fog_rise_time    : float = 4.0
@export var fog_fade_time    : float = 5.0
@export var fog_radius       : float = 8.0
@export var minion_fade_time : float = 2.0

const MAX_PATCHES : int = 16
var _pool : Array = []


func _ready() -> void:
	add_to_group("fog_spawn_effect")
	get_tree().process_frame.connect(_deferred_init, CONNECT_ONE_SHOT)


func _deferred_init() -> void:
	for i in MAX_PATCHES:
		var p := _make_patch()
		p.visible = false
		_pool.append(p)

	var ls := get_tree().get_first_node_in_group("lane_spawner")
	if is_instance_valid(ls) and ls.has_signal("wave_spawned"):
		ls.wave_spawned.connect(_on_wave_spawned)

	var gpc := get_tree().get_first_node_in_group("game_manager")
	if is_instance_valid(gpc):
		for sig in ["match_started_signal", "match_started"]:
			if gpc.has_signal(sig):
				gpc.connect(sig, _on_match_started); break

	_enable_volumetric_fog()


func _enable_volumetric_fog() -> void:
	var we := get_tree().current_scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if not is_instance_valid(we): return
	var env := we.environment
	if not is_instance_valid(env): return
	env.volumetric_fog_enabled        = true
	env.volumetric_fog_density        = 0.0
	env.volumetric_fog_albedo         = Color(0.82, 0.86, 0.95)
	env.volumetric_fog_emission       = Color(0.04, 0.05, 0.08)
	env.volumetric_fog_anisotropy     = 0.25
	env.volumetric_fog_gi_inject      = 0.8
	env.volumetric_fog_length         = 128.0   # longer = more visible volume
	env.volumetric_fog_detail_spread  = 2.0     # sharper local patches


func _on_wave_spawned(team_id: int, lane: int, _count: int) -> void:
	var ls := get_tree().get_first_node_in_group("lane_spawner")
	if not is_instance_valid(ls): return
	var wps : Array = ls.get_lane_waypoints(team_id, lane)
	if wps.is_empty(): return
	var pos : Vector3 = wps[1] if wps.size() > 1 else wps[0]
	pos.y = 0.0
	_spawn_fog_patch(pos, fog_radius)


func _on_match_started() -> void:
	var we := get_tree().current_scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if is_instance_valid(we) and is_instance_valid(we.environment):
		var tw := create_tween()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(we.environment, "volumetric_fog_density", 0.025, 6.0)
	for b in get_tree().get_nodes_in_group("bases"):
		if b is Node3D:
			var pos : Vector3 = (b as Node3D).global_position; pos.y = 0.0
			_spawn_fog_patch(pos, fog_radius * 1.6)


func _spawn_fog_patch(world_pos: Vector3, radius: float = -1.0) -> void:
	if radius < 0.0: radius = fog_radius
	var patch : Node3D = _get_from_pool()
	if not is_instance_valid(patch): return
	patch.global_position = world_pos
	patch.visible = true

	var fv := patch.get_node_or_null("FogVolume") as FogVolume
	if is_instance_valid(fv):
		fv.size = Vector3(radius * 2.2, 3.5, radius * 2.2)
		fv.position = Vector3(0, 1.75, 0)  # shift up so bottom sits at ground

	var mat := _get_mat(patch)
	if is_instance_valid(mat):
		mat.density = 0.0
		var tw := patch.create_tween()
		tw.tween_property(mat, "density", 0.18, fog_rise_time) 			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	var ps := patch.get_node_or_null("Wisps") as GPUParticles3D
	if is_instance_valid(ps):
		var pm := ps.process_material as ParticleProcessMaterial
		if is_instance_valid(pm): pm.emission_sphere_radius = radius * 0.7
		ps.amount = int(radius * 5.0); ps.emitting = true

	get_tree().create_timer(fog_lifetime - fog_fade_time).timeout.connect(
		func(): _fade_patch(patch), CONNECT_ONE_SHOT)


func _fade_patch(patch: Node3D) -> void:
	if not is_instance_valid(patch): return
	var ps := patch.get_node_or_null("Wisps") as GPUParticles3D
	if is_instance_valid(ps): ps.emitting = false
	var mat := _get_mat(patch)
	if is_instance_valid(mat):
		var tw := patch.create_tween()
		tw.tween_property(mat, "density", 0.0, fog_fade_time) 			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func(): _return_patch(patch))
	else:
		get_tree().create_timer(fog_fade_time).timeout.connect(
			func(): _return_patch(patch), CONNECT_ONE_SHOT)


func _get_mat(patch: Node3D) -> FogMaterial:
	var fv := patch.get_node_or_null("FogVolume") as FogVolume
	if not is_instance_valid(fv): return null
	return fv.material as FogMaterial


func fade_in_minion(minion: Node3D) -> void:
	if not is_instance_valid(minion): return
	_set_alpha(minion, 0.0)
	var tw := minion.create_tween()
	tw.tween_method(func(a: float): _set_alpha(minion, a),
		0.0, 1.0, minion_fade_time).set_ease(Tween.EASE_IN)

func _set_alpha(node: Node, alpha: float) -> void:
	if not is_instance_valid(node): return
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			for s in mi.get_surface_override_material_count():
				var mat := mi.get_surface_override_material(s)
				# If no override yet, duplicate from mesh resource
				if not is_instance_valid(mat):
					var src := mi.mesh.surface_get_material(s) if is_instance_valid(mi.mesh) else null
					if not is_instance_valid(src): continue
					mat = src.duplicate()
					mi.set_surface_override_material(s, mat)
				if mat is StandardMaterial3D:
					(mat as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					(mat as StandardMaterial3D).albedo_color.a = alpha
		if child is Node3D: _set_alpha(child, alpha)


func _get_from_pool() -> Node3D:
	for p in _pool:
		if is_instance_valid(p) and not p.visible:
			_pool.erase(p); return p as Node3D
	return _make_patch()

func _return_patch(patch: Node3D) -> void:
	if not is_instance_valid(patch): return
	patch.visible = false
	var mat := _get_mat(patch)
	if is_instance_valid(mat): mat.density = 0.0
	_pool.append(patch)


func _make_patch() -> Node3D:
	var root := Node3D.new()
	root.name = "FogPatch"
	get_tree().current_scene.add_child(root)

	# ── FogVolume — physically accurate volumetric fog ────────
	var fv := FogVolume.new()
	fv.name = "FogVolume"
	fv.size = Vector3(fog_radius * 2.2, 3.5, fog_radius * 2.2)
	var fm := FogMaterial.new()
	fm.density        = 0.0
	fm.albedo         = Color(0.78, 0.83, 0.92)
	fm.emission       = Color(0.03, 0.04, 0.07)
	fm.height_falloff = 1.8  # strong ground hugging
	fm.edge_fade      = 0.18
	fv.material = fm
	root.add_child(fv)

	# ── Wisp particles — turbulent rising mist tendrils ──────
	var ps := GPUParticles3D.new()
	ps.name = "Wisps"; ps.amount = 30; ps.lifetime = 5.0
	ps.emitting = false; ps.local_coords = false; ps.fixed_fps = 0

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = fog_radius * 0.7
	pm.direction              = Vector3(0, 1, 0)
	pm.spread                 = 22.0
	pm.initial_velocity_min   = 0.12
	pm.initial_velocity_max   = 0.50
	pm.gravity                = Vector3(0.0, -0.02, 0.0)
	pm.scale_min              = 0.8; pm.scale_max = 2.4
	pm.damping_min            = 0.1; pm.damping_max = 0.35
	pm.turbulence_enabled          = true
	pm.turbulence_noise_strength   = 1.4
	pm.turbulence_noise_scale      = 0.35
	pm.turbulence_influence_min    = 0.06
	pm.turbulence_influence_max    = 0.20

	var grad := Gradient.new()
	grad.add_point(0.00, Color(0.88, 0.92, 1.00, 0.00))
	grad.add_point(0.12, Color(0.85, 0.90, 0.98, 0.42))
	grad.add_point(0.45, Color(0.80, 0.86, 0.95, 0.28))
	grad.add_point(0.80, Color(0.75, 0.82, 0.93, 0.10))
	grad.add_point(1.00, Color(0.70, 0.78, 0.92, 0.00))
	var gt := GradientTexture1D.new(); gt.gradient = grad
	pm.color_ramp = gt

	var quad := QuadMesh.new(); quad.size = Vector2(2.8, 2.8)
	var pmat := StandardMaterial3D.new()
	pmat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color    = Color(0.88, 0.92, 1.0, 0.5)
	pmat.billboard_mode  = BaseMaterial3D.BILLBOARD_ENABLED
	pmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	quad.material = pmat
	ps.draw_pass_1 = quad; ps.process_material = pm
	root.add_child(ps)

	return root
