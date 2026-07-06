extends Node3D
## Positionne la camera pour voir l'ensemble de la carte de test au demarrage.

func _ready() -> void:
	# 2026-07-06 (revue de code, paquet C, M22) : has_node() avant l'acces -
	# si "Camera3D" venait a etre renomme/retire de Main.tscn, on l'ignore
	# avec un avertissement plutot que de planter au demarrage.
	if not has_node("Camera3D"):
		push_warning("Main: noeud Camera3D introuvable, positionnement de camera ignore")
		return
	var cam := $Camera3D
	cam.global_position = Vector3(10, 22, 38)
	cam.look_at(Vector3(10, 0, 10), Vector3.UP)
