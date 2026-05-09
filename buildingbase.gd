# base.gd
extends Node3D

@export var team_id : int = 1

func _ready() -> void:
	add_to_group("bases")
	add_to_group("units")
	print("[Base] '%s' ready | team=%d" % [name, team_id])
