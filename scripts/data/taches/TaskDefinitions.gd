extends RefCounted
## Table centrale des metadonnees d'une tache designable (miner/couper/
## construire/cueillir/puiser/detruire/escalier) : label affichable, icone de
## marqueur (voir IconRenderer.get_icon_texture), couleur de marqueur/fantome,
## effort de base (secondes de travail avant modif par competence, voir
## DwarfSkills.compute_work_duration). Point d'entree unique pour ne plus
## eparpiller ces informations dans ActionDragController.gd (marqueurs),
## ActionController.gd (_material_color) et Dwarf.gd (work_duration) - pour
## AJOUTER une future tache, une seule entree ici suffit pour son menu/icone/
## effort ; SEULE la logique de resolution reste par tache (TaskQueue.add_*_task
## + DwarfTaskResolver.complete_*_task), parce que c'est la que vit le vrai
## comportement de jeu et qu'aucune table de donnees ne peut la remplacer.
##
## Ne couvre PAS les modes qui n'ont pas de tache associee (ANNULER : clic
## instantane, pas de TaskQueue ; INTERDIRE : bascule un etat, pas de duree de
## travail) - voir ActionMenuBar.MODE_ENTRIES pour le menu des MODES
## (distinct des TACHES : un mode peut couvrir plusieurs types de tache, ex.
## Mode.MINER -> "miner" ou "escalier" selon le sous-type choisi).
##
## "color" absent de l'entree "construire" : Construire n'affiche pas de
## marqueur de tache generique, ses fantomes reprennent la couleur du
## MATERIAU choisi (bois/pierre/terre, voir ActionController._material_color),
## pas une couleur fixe par tache.
##
## "arrival_radius" (voir get_arrival_radius) : distance sous laquelle un nain
## est considere comme arrive sur sa cible (Dwarf.gd, _process). Repli 0.15
## pour les taches ciblant une position de marche pre-calculee a cote du bloc
## (miner/construire/puiser/detruire/escalier). "couper"/"cueillir" ciblent
## directement le centre de l'arbre/plante (voir TaskQueue.add_chop_task et
## add_gather_task) - exiger 0.15 la force a atteindre le tronc lui-meme, ce
## qui peut devenir inatteignable si un arbre voisin (repousse par
## DwarfMovement.tree_avoidance_offset) bloque l'approche : le nain reste
## bloque indefiniment pres d'un groupe d'arbres serres (bug rapporte par
## Francois 2026-07-08, capture d'ecran d'un nain coince). 0.8 laisse assez
## de marge pour "arriver" sans devoir se coller au tronc exact.
const DEFINITIONS := {
	"miner": {"label": "Miner", "icon_kind": "pioche", "color": Color(0.95, 0.75, 0.15), "base_effort": 1.5},
	"couper": {"label": "Couper", "icon_kind": "hache", "color": Color(0.25, 0.55, 0.15), "base_effort": 1.5, "arrival_radius": 0.8},
	"cueillir": {"label": "Cueillir", "icon_kind": "panier", "color": Color(0.85, 0.25, 0.25), "base_effort": 1.5, "arrival_radius": 0.8},
	"construire": {"label": "Construire", "icon_kind": "construire", "base_effort": 1.5},
	"puiser": {"label": "Puiser", "icon_kind": "puiser", "color": Color(0.25, 0.55, 0.85), "base_effort": 1.5},
	"detruire": {"label": "Détruire", "icon_kind": "pioche", "color": Color(0.75, 0.25, 0.05), "base_effort": 1.5},
	"escalier": {"label": "Escalier", "icon_kind": "escalier", "color": Color(0.62, 0.48, 0.30), "base_effort": 1.5},
}


static func get_label(task_type: String) -> String:
	return DEFINITIONS.get(task_type, {}).get("label", task_type.capitalize())


static func get_icon_kind(task_type: String) -> String:
	return DEFINITIONS.get(task_type, {}).get("icon_kind", "")


## Couleur par defaut (blanc) si "task_type" est inconnu ou n'a pas de
## couleur propre (voir doc de tete, cas "construire").
static func get_color(task_type: String) -> Color:
	return DEFINITIONS.get(task_type, {}).get("color", Color(1, 1, 1))


## "fallback" (Dwarf.work_duration, voir sa doc) utilise si "task_type" est
## inconnu - permet d'ajouter un futur type de tache sans casser le travail
## des nains tant que son entree n'a pas encore ete ajoutee ici.
static func get_base_effort(task_type: String, fallback: float = 1.5) -> float:
	return DEFINITIONS.get(task_type, {}).get("base_effort", fallback)


## Voir doc de "arrival_radius" dans DEFINITIONS.
static func get_arrival_radius(task_type: String, fallback: float = 0.15) -> float:
	return DEFINITIONS.get(task_type, {}).get("arrival_radius", fallback)
