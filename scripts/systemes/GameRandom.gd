@tool
extends Node
## 2026-07-06 (revue de code, paquet A "determinisme") : autoload global qui
## fournit un RandomNumberGenerator seede et INDEPENDANT par "flux" nomme
## (ex: "nains_noms", "hydrologie", futurs "biome_desert"/"incendies"/
## "orages"...).
##
## 2026-07-06 (bug) : "@tool" ajoute suite a une erreur "Attempt to call a
## method on a placeholder instance" declenchee par DwarfModel3D.gd/
## DwarfVariationGrid.gd (scripts @tool, executes aussi dans l'editeur) quand
## ils appellent GameRandom.get_rng() pendant une regeneration DANS
## L'EDITEUR. Sans @tool ici, Godot ne charge qu'un "placeholder" vide de cet
## autoload dans l'editeur (le vrai script ne s'y execute pas), d'ou l'echec
## des qu'une methode reelle est appelee. Sans effet en jeu (l'autoload y est
## toujours reel, @tool ou non) - ce fichier n'a ni _ready() ni logique
## dependante du contexte editeur/jeu, donc rien d'autre ne change.
##
## Pourquoi : avant ce fichier, tous les tirages aleatoires du jeu (noms des
## nains, types de baies/arbres, oiseaux, competences, bruit des filons,
## rivieres/lacs...) partageaient le meme flux aleatoire global (randi()/
## randf(), initialise une seule fois par seed(active_seed) dans
## VoxelWorld._ready()). Ce partage rend la reproductibilite par seed
## fragile : le moindre ajout d'un tirage aleatoire quelque part dans le jeu
## decale silencieusement TOUS les tirages qui suivent, meme avec le meme
## seed. En donnant a chaque systeme son propre flux (derive du seed de
## partie + du nom du flux), un changement dans un systeme ne peut plus
## jamais affecter le resultat d'un AUTRE systeme pour un meme seed.
##
## Usage : GameRandom.get_rng("nom_du_flux").randi_range(...)
## Le seed de partie reste UNIQUE (celui tape au menu de demarrage) - "setup"
## doit etre appele une seule fois, le plus tot possible (voir
## VoxelWorld.gd/_ready(), juste apres determination de active_seed).

var _master_seed: int = 0
var _rngs: Dictionary = {}


func setup(master_seed: int) -> void:
	_master_seed = master_seed
	_rngs.clear()


## Renvoie le RandomNumberGenerator dedie a "stream_name", cree et seede au
## premier appel puis reutilise tel quel (son etat continue d'avancer a
## chaque tirage, comme un randi()/randf() global classique, mais isole des
## autres flux).
func get_rng(stream_name: String) -> RandomNumberGenerator:
	if not _rngs.has(stream_name):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d::%s" % [_master_seed, stream_name])
		_rngs[stream_name] = rng
	return _rngs[stream_name]
