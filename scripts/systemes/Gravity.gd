extends RefCounted
## Mecanique de gravite GENERIQUE : un objet pose au sol (tas de ressources
## aujourd'hui - tout futur objet respectant la meme convention demain, voir
## GRAVITY_GROUPS) retombe au premier SOL disponible des que le bloc qui le
## supportait est retire (mine/creuse/detruit) - Francois 2026-07-10 :
## "un objet tombe jusqu'au premier SOL disponible", regle generique voulue
## des le depart plutot que corrigee au cas par cas a chaque futur type
## d'objet (meme esprit de factorisation que ViewLevelIndex.gd).
##
## Contrairement a ViewLevelIndex (bucket + scan incremental, necessaire car
## appele a CHAQUE cran de molette), pas de registre ici : un evenement de
## gravite (bloc retire) est rare compare aux changements de niveau de vue -
## un simple scan du/des groupe(s) concernes a chaque appel suffit. VoxelWorld
## reste volontairement ignorant des entites (voir sa doc de tete) : c'est
## donc l'appelant (DwarfTaskResolver, juste apres avoir reellement retire le
## bloc de la grille) qui declenche ce recalcul.
##
## Convention requise pour qu'un objet soit soumis a la gravite : etre dans
## un groupe liste dans GRAVITY_GROUPS, porter la metadonnee "ground_block_y"
## (deja pose par DwarfResourcePile, voir add_to_resource_pile/
## spawn_starting_wood_stock) et etre positionne sur sa case (position.x/z
## tronques = coordonnees de colonne, meme convention que le reste du jeu).

const VoxelMeshBuilderScript := preload("res://scripts/monde/voxel/VoxelMeshBuilder.gd")

## Un seul endroit a completer pour qu'un futur type d'objet tombe aussi.
const GRAVITY_GROUPS := ["resource_piles"]


## A appeler pour la colonne (x,z) d'au moins un bloc vient d'etre retire de
## "grid" (mine/creuse/detruit) - recalcule la position de tout objet de
## GRAVITY_GROUPS dont le support ("ground_block_y") n'est plus solide, et le
## fait "tomber" instantanement jusqu'au nouveau sommet reel de la colonne.
## Chute en chaine geree gratuitement : si un autre bloc est retire plus tard
## sous un objet qui vient de tomber, ce meme appel se redeclenche et le fait
## retomber encore, jusqu'au premier SOL reellement disponible.
static func apply_at_column(tree: SceneTree, voxel_world: Node3D, x: int, z: int) -> void:
	var new_top: int = -1
	var new_top_computed := false
	for group in GRAVITY_GROUPS:
		for item in tree.get_nodes_in_group(group):
			if int(item.position.x) != x or int(item.position.z) != z:
				continue
			# Garde de convention (revue de code M103) : un futur objet du
			# groupe qui oublierait de poser "ground_block_y" tombait avant
			# silencieusement (sentinelle -999 non solide -> chute a tort) -
			# on avertit desormais au lieu d'ignorer.
			if not item.has_meta("ground_block_y"):
				push_warning("Gravity.apply_at_column : objet du groupe '%s' sans metadonnee ground_block_y (convention non respectee)." % group)
				continue
			var ground_block_y: int = int(item.get_meta("ground_block_y"))
			if voxel_world.is_solid(x, ground_block_y, z):
				continue  # encore soutenu, rien a faire
			if not new_top_computed:
				new_top = voxel_world.get_top_block_y(x, z)
				new_top_computed = true
			var new_y: float = float(new_top) + VoxelMeshBuilderScript.SOL_THICKNESS if new_top >= 0 else 0.0
			item.position.y = new_y
			item.set_meta("ground_block_y", new_top)
