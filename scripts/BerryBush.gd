extends Node3D
## Sprint 8 : buisson a baies. Le nain vient manger ici quand il a faim.
## Chaque buisson a un nombre limite de baies ; une fois epuise, il disparait.

var berries_left: int = 3


## Consomme une baie si possible. Renvoie false si le buisson est deja vide.
func eat() -> bool:
	if berries_left <= 0:
		return false
	berries_left -= 1

	var berry_node := get_node_or_null("Berry_%d" % berries_left)
	if berry_node:
		berry_node.queue_free()

	if berries_left <= 0:
		call_deferred("queue_free")

	return true
