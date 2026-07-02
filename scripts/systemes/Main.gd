extends Node3D
## Positionne la camera pour voir l'ensemble de la carte de test au demarrage.

func _ready() -> void:
	var cam := $Camera3D
	cam.global_position = Vector3(10, 22, 38)
	cam.look_at(Vector3(10, 0, 10), Vector3.UP)
