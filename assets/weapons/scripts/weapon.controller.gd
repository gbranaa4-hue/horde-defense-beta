class_name	WeaponController extends Node

@export var	current_weapon:	Weapon 
@export var weapon_model_parent:Node3d

var current_weapon_model: Node3d

func _ready() -> void:
		if current_weapon:
			spawn_weapon_model()
			

func spawn_weapon_model():
		if current_weapon_model:
			current_weapon_model.queue_free()
			
		if current_weapon.weapon_model:
			current_weapon_model = current_weapon.weapon_model.instantiate()
			weapon_model_parent.add_child(current_weapon_model)
			current_weapon_model.position = current_weapon.weapon_position
