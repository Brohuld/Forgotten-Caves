extends RefCounted
## Sprint 18 : table centrale des competences des nains.
##
## Pour AJOUTER une nouvelle competence, il suffit d'ajouter une entree dans
## le tableau SKILLS ci-dessous (aucune autre modification de code n'est
## necessaire pour qu'elle soit generee aleatoirement a la creation d'un nain
## et affichee dans sa fiche personnage). Pour qu'elle ait un effet sur le
## gameplay (vitesse de travail + bonus de recolte), il faut relier son champ
## "tache" a un type de tache existant ("miner", "couper", "construire" ou
## "cueillir") ; laisser "tache": "" pour une competence purement affichee,
## sans effet pour l'instant (comme Combat, pas encore de mecanique associee).
##
## Champs de chaque entree :
## - id    : identifiant interne stable (utilise pour stocker niveau/xp)
## - nom   : nom affiche dans la fiche personnage
## - tache : type de tache qui fait progresser cette competence, ou "" si
##           aucune tache ne lui correspond encore
##
## Sprint 24septies : Agriculture reliee a "cueillir" - augmente la vitesse de
## cueillette et la chance de recolter un fruit bonus (meme mecanique que
## Minage/Bucheronnage, voir Dwarf.gd/_complete_task).

const SKILLS := [
	{"id": "minage", "nom": "Minage", "tache": "miner"},
	{"id": "bucheronnage", "nom": "Bucheronnage", "tache": "couper"},
	{"id": "construction", "nom": "Construction", "tache": "construire"},
	{"id": "agriculture", "nom": "Agriculture", "tache": "cueillir"},
]


## Renvoie l'id de la competence liee a un type de tache donne, ou "" si
## aucune competence n'y est encore reliee.
static func skill_for_task(task_type: String) -> String:
	if task_type == "":
		return ""
	for skill in SKILLS:
		if skill["tache"] == task_type:
			return skill["id"]
	return ""


## Renvoie le nom affichable d'une competence a partir de son id.
static func display_name(skill_id: String) -> String:
	for skill in SKILLS:
		if skill["id"] == skill_id:
			return skill["nom"]
	return skill_id
