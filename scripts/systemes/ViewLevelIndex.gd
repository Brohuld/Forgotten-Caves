extends RefCounted
## Logique GENERIQUE de visibilite par niveau de vue (view_level / molette),
## partagee par tout type d'objet indexe par son "niveau de sol" (tas,
## arbres, buissons, decorations, et tout futur type - armes, mobilier,
## vetements...). Meme esprit que Hoverable.gd pour le survol : chaque type
## garde son propre stockage/representation (Node3D individuel, instance
## MultiMesh partagee, etc.) et fournit juste une petite fonction
## "apply_fn(item, hidden)" qui sait (dés)afficher SA representation - c'est
## la seule partie non factorisable, le reste (regle de seuil, indexation,
## calcul de la plage a rescanner) est ici, un seul endroit a toucher.
##
## Pour un futur type d'objet : appeler register() a la creation avec son
## niveau de sol, puis appeler full_scan()/delta_scan() depuis sa propre
## fonction update_view_level(level) avec une fonction de bascule visuelle -
## voir Forest.gd/BerryBushes.gd/DwarfResourcePile.gd/GroundDecoration.gd
## pour des exemples d'integration (Francois 2026-07-10, suite a la demande
## de factorisation - un seuil >/>= duplique dans 4 fichiers etait devenu
## intenable a maintenir).


## Regle de seuil : UN SEUL endroit a changer si elle evolue encore. Un
## objet (arbre/tas/decoration) occupe la couche AU-DESSUS de son bloc de
## sol (ground_block_y+1, la ou son SOL synthetique herbe est calcule) - il
## reste visible tant que le niveau de vue est a cette couche ou au-dessus,
## et disparait des qu'on descend au niveau du bloc de sol lui-meme (qui
## affiche desormais les 2 boites CUBE+SOL, voir VoxelMeshBuilder.gd
## _add_boundary_cube_faces) : "niveau 3 = tout (herbe/arbres/objets),
## niveau 2 et en dessous = uniquement les blocs, plus aucun objet"
## (Francois 2026-07-10, apres l'ajout du rendu CUBE+SOL a la
## couche-frontiere - avant cet ajout, niveau 2 ressemblait encore a de
## l'herbe et la regle inverse semblait correcte, ce n'est plus le cas).
static func is_hidden(ground_block_y: int, view_level: int) -> bool:
	return ground_block_y >= view_level


## Indexe "item" dans buckets[ground_block_y] (cree le tableau si absent) -
## a appeler a la creation de chaque objet, pour permettre le scan
## incremental de delta_scan(). "item" est opaque ici (Node3D, index entier
## dans un MultiMesh, etc.) - passe tel quel a apply_fn plus tard.
static func register(buckets: Dictionary, item, ground_block_y: int) -> void:
	if not buckets.has(ground_block_y):
		buckets[ground_block_y] = []
	buckets[ground_block_y].append(item)


## Balayage complet (tout premier appel de update_view_level, ou tout
## evenement pouvant affecter tous les objets d'un coup) : appelle
## apply_fn(item, hidden) pour chaque item de "items", "ground_y_fn(item)"
## fournissant son niveau de sol.
static func full_scan(items: Array, view_level: int, ground_y_fn: Callable, apply_fn: Callable) -> void:
	for item in items:
		var ground_block_y: int = int(ground_y_fn.call(item))
		apply_fn.call(item, is_hidden(ground_block_y, view_level))


## Balayage incremental (tout appel de update_view_level APRES le premier) :
## seuls les objets dont le niveau de sol L se trouve dans
## [min(old,new), max(old,new)[ peuvent changer d'etat (le point de bascule
## de is_hidden() est entre L et L+1) - on ne parcourt donc que les buckets
## de cet intervalle au lieu de tous les objets. apply_fn(item, hidden)
## recoit le "hidden" deja calcule pour new_level - un type avec d'autres
## raisons de masquage combinees (ex: GroundDecoration, saison/mine) peut
## l'ignorer et recalculer son propre etat combine dans apply_fn.
static func delta_scan(buckets: Dictionary, old_level: int, new_level: int, apply_fn: Callable) -> void:
	if old_level == new_level:
		return
	var lo: int = min(old_level, new_level)
	var hi: int = max(old_level, new_level)
	for lvl in range(lo, hi):
		if not buckets.has(lvl):
			continue
		for item in buckets[lvl]:
			apply_fn.call(item, is_hidden(lvl, new_level))
