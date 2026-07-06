extends Node
## Sprint 34quinquies/34septies (2026-07-03) : "prechauffage" du modele de
## nain 3D (DwarfModel3D.gd) tout au debut de Main.tscn, avant meme
## VoxelWorld (voir Main.tscn - premier noeud sous "Main", donc premier a
## executer son _ready(), meme principe d'ordre que DayNightCycle avant).
##
## Mesure de perf (voir memoire perf dediee "lancement lent") : construire le
## PREMIER DwarfModel3D d'une partie coute environ 6 secondes - mais UNE SEULE
## FOIS par lancement, jamais plus (les nains suivants et les 3 portraits de
## CharacterSheetUI.gd se construisent ensuite en ~0.01s chacun).
##
## 34sexies : une 1ere tentative plaçait ce prechauffage dans un AUTOLOAD
## (execute avant meme le chargement de Main.tscn) - inefficace, le cout
## complet reapparaissait quand meme sur le premier vrai nain. Le declencheur
## exact reste incertain (tres probablement une compilation/preparation liee
## au rendu - shader, pipeline - qui necessite le contexte reel de la scene :
## WorldEnvironment/camera/eclairage deja en place, absents dans un
## autoload qui tourne avant que Main.tscn n'existe). Cette version place
## donc le prechauffage DANS Main.tscn, en tout premier noeud (avant
## VoxelWorld), pour beneficier du meme contexte de rendu que les vrais nains
## tout en payant le cout AVANT la generation du monde plutot qu'apres.
##
## Le modele construit ici est entierement jetable : jamais visible (detruit
## immediatement apres construction), aucun lien avec les vrais nains du jeu
## (chacun construit toujours le sien normalement dans Dwarf.gd/
## _build_appearance - ce prechauffage ne remplace ni ne modifie ce code).

const DwarfModel3DScript := preload("res://scripts/prototypes/DwarfModel3D.gd")


func _ready() -> void:
	# 2026-07-06 (revue de code, paquet F, I28) : ce prechauffage n'a de sens
	# que s'il s'execute AVANT VoxelWorld (voir doc en tete de fichier) - garde-
	# fou qui avertit si ce noeud n'est plus le premier enfant de Main.tscn
	# (ex: reordonnancement accidentel de la scene), plutot que de perdre
	# silencieusement le benefice du prechauffage.
	if get_index() != 0:
		push_warning("DwarfModelPrewarm.gd n'est pas le premier noeud de sa scene (index %d) - le prechauffage doit avoir lieu AVANT VoxelWorld pour etre efficace, voir commentaire en tete de fichier." % get_index())
	var t0: int = Time.get_ticks_msec()
	var dummy := Node3D.new()
	dummy.set_script(DwarfModel3DScript)
	add_child(dummy)
	# Appel explicite (en plus de celui, automatique, declenche par
	# dummy._ready() a l'entree dans l'arbre ci-dessus) : garantit que la
	# construction est bien terminee de facon synchrone avant qu'on mesure/
	# detruise le modele, quel que soit l'ordre exact d'execution.
	# 2026-07-06 (revue de code, paquet H, M25) : garde has_method() avant cet
	# appel direct a une methode "privee" (prefixe _) d'un autre script - si
	# _rebuild() est un jour renommee/supprimee dans DwarfModel3D.gd, on
	# avertit au lieu de planter silencieusement.
	if dummy.has_method("_rebuild"):
		dummy._rebuild()
	else:
		push_warning("DwarfModelPrewarm.gd : DwarfModel3D.gd n'a plus de methode _rebuild() - le prechauffage risque d'etre incomplet.")
	var elapsed_ms: int = Time.get_ticks_msec() - t0
	# 2026-07-06 (revue de code, paquet D, M26) : instrumentation de perf
	# conditionnee a OS.is_debug_build() - diagnostic actif (declencheur exact
	# du cout de ~6s toujours incertain, voir commentaires ci-dessus), mais
	# ne doit pas s'afficher dans un export final.
	if OS.is_debug_build():
		print("[Perf] Prechauffage du modele de nain 3D termine en %.2f s (avant la generation du monde)" % (elapsed_ms / 1000.0))
	dummy.queue_free()
