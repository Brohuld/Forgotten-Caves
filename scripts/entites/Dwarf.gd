extends Node3D
## Sprint 3 : nain provisoire (capsule) qui se deplace et s'anime.
## Sprint 4 : pioche ses destinations dans la TaskQueue (miner/couper/construire)
## en priorite, et erre au hasard seulement s'il n'y a rien a faire.
## Sprint 8 : jauges faim/energie. Si un besoin devient critique, le nain
## interrompt ce qu'il fait pour manger (buisson a baies) ou se reposer.
## Sprint 9bis : signale la fin d'une tache de construction (succes ou
## echec) pour que l'UI puisse retirer le mur "fantome" correspondant.
## Sprint 11 : plusieurs nains simultanes. Chaque instance rejoint le
## groupe "dwarves" (pour que l'UI et les autres scripts puissent tous
## les retrouver) et a un nom d'affichage (dwarf_name).
## Sprint 12 : caracteristiques de base (Force, Agilite, Constitution,
## Intelligence, Beaute, Bonheur), generees aleatoirement a la creation.
## Purement informatif pour l'instant (visible dans la fiche personnage),
## sans effet sur le gameplay : ca viendra avec les competences.
## Sprint 13/14 : silhouette "BD" articulee generee par code (abandonnee
## au Sprint 15 au profit d'une vraie illustration).
## Sprint 15/15bis/16 : sprite 2D illustre en billboard, avec relief (normal
## map) et personnalisation par region (masque de couleurs + shader de
## recolor). Remplace au Sprint 28decies (voir plus bas) par un vrai modele
## 3D - toute cette section a ete retiree.
## Sprint 17 : accessoires d'action (sans nouvel art du personnage). Un outil
## (pioche/hache/marteau, formes 3D simples generees par code) apparait pres
## des mains et se balance pendant le travail, selon le type de tache. Un
## "Z z z" flotte au-dessus de la tete pendant le repos. Une petite baie
## flotte pres de la bouche pendant le repas. Objectif : rendre les actions
## plus lisibles sans avoir a redessiner/ré-animer le personnage lui-meme.
## Sprint 18 : competences (Minage/Bucheronnage/Construction pour l'instant,
## liste dans SkillDefinitions.gd, facile a etendre). Chaque nain recoit un
## niveau de depart aleatoire par competence (repartition a "budget" constant,
## donc pas de nain generaliste dans toutes les competences a la fois), puis
## gagne de l'XP a chaque tache terminee du type correspondant. Le niveau
## reduit la duree de travail et augmente la chance d'obtenir une ressource
## bonus a la recolte.
## Sprint 24ter : tache "cueillir" (recolte de fruits/baies sans abattre la
## cible, voir _complete_task) - generique entre arbres fruitiers (Forest.gd)
## et buissons (BerryBushes.gd), les deux portant les memes metadonnees
## fruit_resource/fruits_left et le groupe "cueillette".
## Sprint 24quater : la faim ne fait plus marcher le nain jusqu'a un buisson -
## il mange directement depuis l'inventaire commun (n'importe quel fruit/baie
## disponible, voir _try_start_eating), qui est maintenant la seule source de
## nourriture (les buissons/arbres fruitiers doivent d'abord etre cueillis).
## Sprint 24septies : trois ajouts lies a la recolte/nourriture -
## (1) chaque ressource recoltee (bois/pierre/terre/filon/fruit/baie) fait
## apparaitre un petit tas persistant au sol (_spawn_resource_pile) au lieu
## de l'ancienne animation qui sautait puis disparaissait - la ressource est
## toujours comptee en inventaire immediatement, le tas est pour l'instant
## purement visuel/repere, en attendant un futur systeme de transport vers
## des zones de stockage ; (2) la cueillette peut donner un fruit bonus selon
## la competence Agriculture (SkillDefinitions.gd), meme mecanique que
## minage/bucheronnage ; (3) chaque fruit/baie restaure une quantite de faim
## qui lui est propre ("calories", voir TreeSpecies.gd/BerryTypes.gd) au lieu
## d'un montant fixe pour tous.
## Sprint 28decies : remplacement complet du sprite 2D (Sprint 15/15bis/16)
## par le modele 3D procedural developpe en prototype isole (Sprint 28 a
## 28novies, voir scripts/prototypes/DwarfModel3D.gd) - _build_appearance()
## instancie desormais ce script sur un noeud enfant de "body" au lieu de
## Sprite3D. Les 4 couleurs personnalisables existantes (hair/beard/
## clothing/armor_color) sont conservees telles quelles et transmises au
## modele ; le reste de l'apparence (coiffure/barbe/tenue/corpulence) est
## tire au hasard via DwarfModel3D._randomize_variation() a la creation du
## nain. Les armes ne sont PAS integrees pour l'instant (weapon_loadout
## force a "Aucune") : le jeu principal n'a pas encore de systeme de combat,
## ca viendra avec la Phase 4. Les animations marche/travail/repos/repas,
## avant simulees en position/echelle (limitation du billboard), pilotent
## maintenant directement DwarfModel3D.preview_animation - un vrai objet 3D
## peut etre anime par rotation d'articulations (voir _process ci-dessous).
## Sprint 36 (2026-07-03) : soif, demande explicite en meme temps que les
## lacs/rivieres ("gerer la soif des nains"). Meme mecanique que la faim
## (Sprint 24quater) : le nain boit directement depuis l'inventaire commun
## (ressource "eau", remplie par la tache "puiser" designee sur une case d'eau,
## voir ActionController.gd/VoxelWorld.is_water), pas de deplacement jusqu'au
## bord de l'eau. Reutilise food_indicator (teinte en bleu) plutot que de
## creer un second indicateur 3D - repas et boisson ne sont jamais simultanes.

const SkillDefs := preload("res://scripts/data/creatures/nains/caracteristiques/SkillDefinitions.gd")
const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")
const TreeSpecies := preload("res://scripts/data/materiaux/types/bois/TreeSpecies.gd")
const BerryTypes := preload("res://scripts/data/materiaux/types/baies/BerryTypes.gd")
const DwarfModel3DScript := preload("res://scripts/prototypes/DwarfModel3D.gd")
const NainNames := preload("res://scripts/data/creatures/nains/NainNames.gd")
## Sprint 34quinquies : mesure de duree de chargement - pour savoir si le
## temps passe entre la fin de GroundDecoration et le debut de
## CharacterSheetUI (voir memoire perf) vient bien de _build_appearance()
## (construction du modele 3D, voir DwarfModel3D.gd) et si oui, si le cout
## est reparti sur les 3 nains ou concentre sur le premier (indice d'un
## "rechauffement" ponctuel, ex. compilation de shader au premier usage).
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")

signal build_task_finished(task_id: int, bx: int, bz: int)
## Sprint 26 : signal generique emis a la fin de N'IMPORTE QUELLE tache
## (miner/couper/cueillir/construire), utilise par ActionController.gd pour
## retirer l'icone temporaire affichee sur l'objet designe. Independant de
## build_task_finished ci-dessus (garde pour le mur fantome, inchange).
signal task_finished(task_id: int)

# 2026-07-02 : nom laisse vide par defaut -> genere aleatoirement a la
# creation (voir _ready, NainNames.gd). Toujours possible de forcer un nom
# precis a la main (Inspecteur/.tscn) pour un futur nain nomme/unique - dans
# ce cas la valeur fournie est respectee et n'est pas ecrasee.
@export var dwarf_name: String = ""

# Personnalisation par region (Sprint 16) : couleurs par defaut proches de
# l'image d'origine, pour qu'un nain sans reglage particulier ressemble a
# l'illustration de base.
@export var hair_color: Color = Color(0.59, 0.45, 0.33)
@export var beard_color: Color = Color(0.80, 0.71, 0.53)
@export var clothing_color: Color = Color(0.68, 0.51, 0.41)
@export var armor_color: Color = Color(0.55, 0.55, 0.58)

# Ajustement de gabarit (2026-07-02) : nains juges trop grands par rapport
# aux arbres/buissons - reduction uniforme de 20% appliquee au modele 3D
# (voir _build_appearance). Les pieds restent au sol : le modele a son
# origine locale a y=0 (au niveau des pieds), un scale uniforme autour de
# cette origine ne decale donc pas verticalement le nain.
@export var model_scale: float = 0.8

# Doivent correspondre a VoxelWorld.gd
@export var grid_width: int = 100  # 2026-07-03 : map resize (etait 20)
@export var grid_depth: int = 100  # 2026-07-03 : map resize (etait 20)
@export var ground_level: float = 50.0  # sommet de la carte (HEIGHT, 2026-07-03 : map resize, etait 30)
# Sprint 38 (reliefs) : ground_level ci-dessus ne sert plus que de repli (terrain
# plat sans collines, ou position hors carte) - la hauteur reelle du nain suit
# desormais le relief case par case via _ground_y_at (voir plus bas).

@export var move_speed: float = 3.0        # unites / seconde
@export var rotation_speed: float = 8.0    # vitesse de rotation vers la direction
@export var work_duration: float = 1.5     # secondes pour miner/couper une fois arrive

# Sprint 37 (backlog Phase 1 item 13c) : facteur applique a move_speed quand
# le nain traverse une case d'eau (voir _move_toward/_is_on_water).
const WATER_SLOWDOWN_FACTOR := 0.4

# Sprint 38 (reliefs, "impacte le deplacement") : facteur applique en montee -
# effet simple (pas de vraie physique de pente), meme principe que
# WATER_SLOWDOWN_FACTOR ci-dessus. Voir _is_climbing/_move_toward.
const SLOPE_SLOWDOWN_FACTOR := 0.6

# Besoins (Sprint 8) - vitesses volontairement rapides pour tester sans attendre
@export var hunger_max: float = 100.0
@export var energy_max: float = 100.0
@export var hunger_depletion_rate: float = 8.0   # points / seconde
@export var energy_depletion_rate: float = 5.0   # points / seconde
@export var hunger_critical: float = 20.0
@export var energy_critical: float = 15.0
@export var energy_rest_target: float = 70.0     # niveau vise avant de reprendre l'activite
@export var energy_regen_rate: float = 20.0      # points / seconde au repos
@export var hunger_restore_per_berry: float = 40.0
@export var eat_duration: float = 1.2            # secondes, animation de manger

# Soif (Sprint 36) - meme principe que la faim ci-dessus, taux de depletion
# legerement superieur (la soif devient critique un peu plus vite que la faim,
# comme dans la realite)
@export var thirst_max: float = 100.0
@export var thirst_depletion_rate: float = 9.0   # points / seconde
@export var thirst_critical: float = 20.0
@export var thirst_restore_per_gorgee: float = 50.0
@export var drink_duration: float = 1.2          # secondes, animation de boire

# Repere approximatif de la hauteur de tete du modele 3D (voir DwarfModel3D
# proportions par defaut : leg_height + torso_height + head_radius), utilise
# pour positionner l'indicateur de sommeil et l'indicateur de repas au bon
# endroit sans dupliquer le calcul exact du prototype.
const HEAD_HEIGHT_APPROX := 0.95

# Competences (Sprint 18)
const SKILL_BUDGET_PER_SKILL := 5      # budget total distribue = nb de competences * cette valeur
const SKILL_MAX_START_LEVEL := 10      # plafond du tirage aleatoire initial (l'xp peut aller au-dela ensuite)
const SKILL_XP_PER_TASK := 10.0        # xp gagnee a chaque tache terminee du bon type
const SKILL_XP_BASE := 20.0            # xp necessaire pour passer du niveau 0 au niveau 1
const SKILL_XP_PER_LEVEL := 10.0       # xp supplementaire requise par niveau deja atteint
const SKILL_WORK_SPEED_BONUS := 0.05   # par niveau : -5% de duree de travail
const SKILL_MIN_DURATION_FACTOR := 0.4 # la duree ne descend jamais sous 40% de la duree de base
const SKILL_BONUS_YIELD_PER_LEVEL := 0.05  # par niveau : +5% de chance de ressource bonus
const SKILL_BONUS_YIELD_MAX := 0.6         # plafond de la chance de bonus

var hunger: float = 100.0
var energy: float = 100.0
var thirst: float = 100.0

# Caracteristiques de base (Sprint 12) : 1-10 pour les 5 premieres, un
# pourcentage pour le bonheur. Generees une fois a la creation du nain.
var force: int = 0
var agilite: int = 0
var constitution: int = 0
var intelligence: int = 0
var beaute: int = 0
var bonheur: int = 0

# Competences (Sprint 18) : id (voir SkillDefinitions.gd) -> niveau / xp
# dans le niveau actuel. Generees a la creation, progressent avec l'usage.
var skill_levels: Dictionary = {}
var skill_xp: Dictionary = {}
var current_work_duration: float = 1.5  # duree effective de la tache en cours (ajustee par la competence)

var target_position: Vector3
var dwarf_model: Node3D  # instance de DwarfModel3D (Sprint 28decies), enfant de "body"

# Accessoires d'action (Sprint 17)
var tool_pivot: Node3D
var tool_pickaxe: Node3D
var tool_axe: Node3D
var tool_hammer: Node3D
var sleep_indicator: Label3D
var food_indicator: MeshInstance3D

var current_task: Dictionary = {}
var is_working: bool = false
var work_timer: float = 0.0

var is_resting: bool = false
var is_eating: bool = false
var eat_timer: float = 0.0
var eating_food_id: String = ""  # Sprint 24quater : id de la ressource en train d'etre mangee (inventaire)

var is_drinking: bool = false
var drink_timer: float = 0.0

# Sprint 37 (backlog Phase 1 item 14) : le nain ne doit pas s'endormir sur une
# case d'eau - si l'energie devient critique alors qu'il se trouve sur de
# l'eau, il marche d'abord jusqu'a une case seche (voir _process_seeking_dry_land)
# avant de reellement commencer a se reposer.
var is_seeking_dry_land: bool = false

## Sprint 37 (backlog Phase 1 item 11bis, "inventaire personnel des nains") :
## stub minimal - juste des emplacements nommes avec un contenu texte libre
## ("" = vide), affiches en lecture seule dans l'onglet Equipement de la fiche
## personnage (CharacterSheetUI). Un vrai systeme d'equipement (artisanat,
## bonus de stats, habits qui protegent du froid - voir temperature_status)
## est du scope Phase 2 "Ateliers & artisanat" et n'est pas implemente ici.
var personal_inventory: Dictionary = {
	"gourde": "",
	"sac_a_dos": "",
	"habit": "",
	"arme": "",
}

@onready var body: Node3D = $Body
@onready var task_queue: Node = %TaskQueue
@onready var voxel_world: Node3D = %VoxelWorld
@onready var inventory: Node = %Inventory
# Sprint 34 (2026-07-03, perf) : reference a Forest.gd, necessaire pour
# hide_tree_visuals() avant de couper un arbre - voir _process_work ci-dessous.
@onready var forest: Node3D = %Forest
# Sprint 37 (backlog Phase 1 item 6) : confort thermique, voir temperature_status()
@onready var temperature_system: Node = %TemperatureSystem


func _ready() -> void:
	# Petit decalage aleatoire au demarrage pour eviter que plusieurs nains
	# ne se superposent exactement au meme endroit (Sprint 11)
	var jitter_x := randf_range(-1.5, 1.5)
	var jitter_z := randf_range(-1.5, 1.5)
	var spawn_x: float = grid_width / 2.0 + jitter_x
	var spawn_z: float = grid_depth / 2.0 + jitter_z
	global_position = Vector3(spawn_x, _ground_y_at(spawn_x, spawn_z), spawn_z)
	add_to_group("dwarves")
	if dwarf_name == "":
		dwarf_name = NainNames.random_name()
	_generate_characteristics()
	_generate_skills()
	var t0: int = Time.get_ticks_msec()
	_build_appearance()
	var build_ms: int = Time.get_ticks_msec() - t0
	var elapsed_since_scene_start_ms: int = Time.get_ticks_msec() - DayNightCycleScript.scene_start_ms
	print("[Perf] Nain '%s' : modele 3D construit en %.2f s (temps ecoule depuis debut de scene : %.1f s)" % [dwarf_name, build_ms / 1000.0, elapsed_since_scene_start_ms / 1000.0])
	_pick_new_target()


## Genere les caracteristiques de base du nain (Sprint 12). Purement
## informatif pour l'instant, aucun effet sur le gameplay.
func _generate_characteristics() -> void:
	force = randi_range(1, 10)
	agilite = randi_range(1, 10)
	constitution = randi_range(1, 10)
	intelligence = randi_range(1, 10)
	beaute = randi_range(1, 10)
	bonheur = randi_range(40, 80)


## --- Competences (Sprint 18) ---

## Repartit un niveau de depart aleatoire par competence, a "budget" constant
## (total = nb de competences * SKILL_BUDGET_PER_SKILL) : un nain fort dans
## une competence le sera un peu moins dans les autres, plutot que d'avoir
## des nains generalistes forts partout.
func _generate_skills() -> void:
	var defs: Array = SkillDefs.SKILLS
	var count: int = defs.size()
	if count == 0:
		return
	var budget: int = count * SKILL_BUDGET_PER_SKILL
	var values: Array = _distribute_skill_points(budget, count, SKILL_MAX_START_LEVEL)
	for i in range(count):
		var id: String = defs[i]["id"]
		skill_levels[id] = values[i]
		skill_xp[id] = 0.0


## Distribue "total_budget" points entre "count" competences au hasard
## (poids aleatoires normalises), chaque competence plafonnee a
## "max_per_skill". Le reste eventuel (du a l'arrondi) est distribue un point
## a la fois, au hasard, parmi les competences pas encore au plafond.
func _distribute_skill_points(total_budget: int, count: int, max_per_skill: int) -> Array:
	var weights: Array = []
	var weight_sum: float = 0.0
	for i in range(count):
		var w: float = randf() + 0.1  # + 0.1 pour eviter un poids quasi nul
		weights.append(w)
		weight_sum += w

	var values: Array = []
	var allocated: int = 0
	for i in range(count):
		var v: int = int(floor(weights[i] / weight_sum * float(total_budget)))
		v = clampi(v, 0, max_per_skill)
		values.append(v)
		allocated += v

	var remaining: int = total_budget - allocated
	var guard: int = 0
	while remaining > 0 and guard < 500:
		var idx: int = randi_range(0, count - 1)
		if values[idx] < max_per_skill:
			values[idx] += 1
			remaining -= 1
		guard += 1

	return values


## Ajoute de l'xp a une competence et fait passer les niveaux necessaires
## (l'xp requise augmente a chaque niveau, voir SKILL_XP_BASE/SKILL_XP_PER_LEVEL)
func _gain_skill_xp(skill_id: String, amount: float) -> void:
	if skill_id == "" or not skill_levels.has(skill_id):
		return
	skill_xp[skill_id] += amount
	var guard: int = 0
	while skill_xp[skill_id] >= _xp_needed_for_level(skill_levels[skill_id]) and guard < 100:
		skill_xp[skill_id] -= _xp_needed_for_level(skill_levels[skill_id])
		skill_levels[skill_id] += 1
		print("%s : %s passe niveau %d" % [dwarf_name, SkillDefs.display_name(skill_id), skill_levels[skill_id]])
		guard += 1


func _xp_needed_for_level(level: int) -> float:
	return SKILL_XP_BASE + float(level) * SKILL_XP_PER_LEVEL


## Duree de travail effective pour la tache en cours, reduite selon le
## niveau de la competence liee (voir SkillDefinitions.skill_for_task)
func _compute_work_duration() -> float:
	var skill_id: String = SkillDefs.skill_for_task(current_task.get("type", ""))
	if skill_id == "" or not skill_levels.has(skill_id):
		return work_duration
	var level: int = skill_levels[skill_id]
	var factor: float = max(1.0 - float(level) * SKILL_WORK_SPEED_BONUS, SKILL_MIN_DURATION_FACTOR)
	return work_duration * factor


## Tire au sort si la recolte donne une ressource bonus, avec une chance qui
## augmente avec le niveau de competence (plafonnee a SKILL_BONUS_YIELD_MAX)
func _roll_bonus_yield(skill_id: String) -> bool:
	if skill_id == "" or not skill_levels.has(skill_id):
		return false
	var level: int = skill_levels[skill_id]
	var chance: float = min(float(level) * SKILL_BONUS_YIELD_PER_LEVEL, SKILL_BONUS_YIELD_MAX)
	return randf() < chance


## --- Apparence (Sprint 28decies) : modele 3D procedural, remplace le sprite
## 2D en billboard (Sprint 15/15bis/16) ---
## Le modele est un vrai objet 3D (voir scripts/prototypes/DwarfModel3D.gd,
## developpe et valide en scene isolee du Sprint 28 au 28novies) : feet a
## y=0 dans son propre repere local, donc ajoute directement comme enfant de
## "body" sans decalage vertical necessaire (contrairement au sprite, dont
## l'origine devait etre relevee de sprite_neutral_y).

## Sprint 34duodecies (2026-07-03) : reordonnee pour eviter un aller-retour
## de construction inutile - voir memoire perf "lancement lent" pour le detail
## du diagnostic. AVANT : dwarf_model etait ajoute a l'arbre (body.add_child)
## PUIS recevait son apparence (couleurs, style aleatoire) - l'ajout a
## l'arbre declenche automatiquement _ready()->_rebuild() (voir DwarfModel3D)
## AVEC LES VALEURS PAR DEFAUT, immediatement jete et reconstruit par un appel
## EXPLICITE a _rebuild() juste apres. Ce gaspillage (construire le modele
## 2 fois a chaque nain) etait sans consequence mesurable pour les nains 2 et
## 3 d'une partie (~0.01-0.02s), mais causait une pause de ~5-6s pour le TOUT
## PREMIER nain construit : nettoyer les ~47 noeuds de ce premier essai jetable
## (remove_child + free, voir DwarfModel3D._rebuild) forcait une
## synchronisation couteuse avec le moteur de rendu, juste apres les ~7s de
## generation du monde qui laissent une file d'attente de rendu tres chargee.
## En fixant l'apparence AVANT d'ajouter le noeud a l'arbre, le _rebuild()
## automatique (declenche par _ready() a l'ajout) construit directement la
## BONNE apparence du premier coup - plus jamais besoin d'un 2e essai, donc
## plus jamais rien a nettoyer, pour aucun nain.
func _build_appearance() -> void:
	dwarf_model = Node3D.new()
	dwarf_model.set_script(DwarfModel3DScript)
	dwarf_model.name = "DwarfModel"

	# Tire une apparence aleatoire complete (coiffure/barbe/tenue/corpulence/
	# couleurs) via la meme fonction que la grille de verification du
	# prototype, puis les 4 couleurs "region" historiques (Sprint 16,
	# personnalisables par nain, voir Main.tscn) reprennent la main pour
	# rester coherentes avec le reste du jeu (fiche personnage, etc.).
	dwarf_model._randomize_variation()
	dwarf_model.hair_color = hair_color
	dwarf_model.beard_color = beard_color
	dwarf_model.clothing_color = clothing_color
	dwarf_model.armor_color = armor_color
	# Pas de systeme de combat dans le jeu principal pour l'instant (Phase 4,
	# voir README) : on force "sans arme" quel que soit le tirage aleatoire.
	dwarf_model.weapon_loadout = "Aucune"

	# add_child declenche _ready()->_rebuild() (voir DwarfModel3D.gd) qui
	# construit directement la bonne apparence, deja fixee ci-dessus - plus
	# aucun appel explicite a _rebuild() necessaire ici.
	body.add_child(dwarf_model)
	dwarf_model.scale = Vector3.ONE * model_scale

	_build_tool_accessory()
	_build_sleep_indicator()
	_build_food_indicator()


## Remet l'animation en position neutre (utilise a chaque arret de marche :
## travail, repos, repas). Le modele 3D gere lui-meme sa pose de repos des
## que preview_animation repasse a "Aucune" (voir DwarfModel3D._process).
func _reset_pose() -> void:
	dwarf_model.preview_animation = "Aucune"


## --- Accessoires d'action (Sprint 17) : pas de nouvel art du personnage,
## juste des elements simples (formes 3D generees par code / Label3D) qui
## se montrent pendant l'etat correspondant, pour rendre les actions plus
## lisibles (outil qui se balance, "Z z z", baie pres de la bouche).

## Construit les 3 outils possibles (pioche/hache/marteau), caches par
## defaut ; seul celui qui correspond au type de tache en cours est montre
## (voir _show_tool_for_task).
## Sprint 28decies : attache maintenant a la main droite du modele 3D
## (DwarfModel3D._hand_r, meme noeud utilise par le prototype pour tenir les
## armes) plutot qu'a un offset fixe sur "body" - l'outil suit desormais
## naturellement le bras pendant l'animation "Travail" (voir _process),
## sans avoir besoin d'un tremblement anime manuellement en plus.
func _build_tool_accessory() -> void:
	tool_pivot = Node3D.new()
	dwarf_model._hand_r.add_child(tool_pivot)

	tool_pickaxe = _make_tool_mesh(Vector3(0.05, 0.32, 0.05), Vector3(0.26, 0.07, 0.05), Color(0.4, 0.28, 0.15), Color(0.5, 0.5, 0.55))
	tool_axe = _make_tool_mesh(Vector3(0.05, 0.30, 0.05), Vector3(0.20, 0.16, 0.05), Color(0.4, 0.28, 0.15), Color(0.72, 0.74, 0.78))
	tool_hammer = _make_tool_mesh(Vector3(0.045, 0.26, 0.045), Vector3(0.16, 0.14, 0.14), Color(0.4, 0.28, 0.15), Color(0.42, 0.42, 0.46))

	tool_pivot.add_child(tool_pickaxe)
	tool_pivot.add_child(tool_axe)
	tool_pivot.add_child(tool_hammer)
	tool_pickaxe.visible = false
	tool_axe.visible = false
	tool_hammer.visible = false


## Cree un outil simple (manche + tete) a partir de 2 boites, sans texture
## (couleurs unies non eclairees, coherent avec le style "icone")
func _make_tool_mesh(handle_size: Vector3, head_size: Vector3, handle_color: Color, head_color: Color) -> Node3D:
	var root := Node3D.new()

	var handle := MeshInstance3D.new()
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = handle_size
	handle.mesh = handle_mesh
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = handle_color
	handle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	handle.set_surface_override_material(0, handle_mat)
	root.add_child(handle)

	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = head_size
	head.mesh = head_mesh
	head.position = Vector3(0, handle_size.y * 0.5, 0)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = head_color
	head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	head.set_surface_override_material(0, head_mat)
	root.add_child(head)

	return root


## Montre le bon outil selon le type de tache en cours (masque les autres)
func _show_tool_for_task() -> void:
	tool_pickaxe.visible = false
	tool_axe.visible = false
	tool_hammer.visible = false
	match current_task.get("type"):
		"miner":
			tool_pickaxe.visible = true
		"couper":
			tool_axe.visible = true
		"construire":
			tool_hammer.visible = true


func _hide_tools() -> void:
	tool_pickaxe.visible = false
	tool_axe.visible = false
	tool_hammer.visible = false
	tool_pivot.rotation = Vector3.ZERO


## "Z z z" flottant au-dessus de la tete pendant le repos
func _build_sleep_indicator() -> void:
	sleep_indicator = Label3D.new()
	sleep_indicator.text = "Z z z"
	sleep_indicator.font_size = 48
	sleep_indicator.outline_size = 10
	sleep_indicator.modulate = Color(0.85, 0.9, 1.0)
	sleep_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sleep_indicator.no_depth_test = true
	sleep_indicator.position = Vector3(0, (HEAD_HEIGHT_APPROX + 0.35) * model_scale, 0)
	sleep_indicator.visible = false
	body.add_child(sleep_indicator)


## Petite baie qui flotte pres de la bouche pendant le repas
func _build_food_indicator() -> void:
	food_indicator = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	food_indicator.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.1, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	food_indicator.set_surface_override_material(0, mat)
	food_indicator.position = Vector3(0, HEAD_HEIGHT_APPROX * 0.9 * model_scale, 0.18 * model_scale)  # hauteur approximative de la bouche
	food_indicator.visible = false
	body.add_child(food_indicator)


func _process(delta: float) -> void:
	# Sprint 37 (backlog Phase 1 item 8) : multiplicateur de vitesse du temps
	# (Pause/x1/x2/x4, voir ActionController.gd/DayNightCycle.game_speed) -
	# en multipliant delta une seule fois ici, TOUT ce qui suit (deplacement,
	# besoins, travail, repas/boisson, repos) suit deja la meme vitesse sans
	# devoir toucher chaque ligne individuellement. Sciemment PAS applique a
	# CameraRig.gd : la camera doit rester utilisable meme en pause.
	delta *= DayNightCycleScript.game_speed
	_update_needs(delta)

	if is_working:
		_process_work(delta)
		return

	if is_resting:
		_process_resting(delta)
		return

	if is_eating:
		_process_eating(delta)
		return

	if is_drinking:
		_process_drinking(delta)
		return

	if is_seeking_dry_land:
		_process_seeking_dry_land(delta)
		return

	# Les besoins critiques passent avant les taches et l'errance. La soif est
	# verifiee avant la faim (Sprint 36, priorite un peu plus urgente).
	if energy <= energy_critical:
		# Sprint 37 (backlog Phase 1 item 14) : pas de sieste dans l'eau -
		# si le nain s'y trouve, il marche d'abord vers une case seche.
		if _is_on_water():
			is_seeking_dry_land = true
			target_position = _find_dry_target()
			if not current_task.is_empty():
				task_queue.requeue_task(current_task)
				current_task = {}
			_process_seeking_dry_land(delta)
		else:
			_start_resting()
		return
	if thirst <= thirst_critical:
		if _try_start_drinking():
			return
		# sinon (aucune eau en inventaire) : on continue normalement
	if hunger <= hunger_critical:
		if _try_start_eating():
			return
		# sinon (aucune nourriture en inventaire) : on continue normalement

	# Priorite aux taches designees par l'utilisateur, la plus proche d'abord
	if current_task.is_empty() and task_queue.has_tasks():
		current_task = task_queue.pop_nearest_task(global_position)
		target_position = current_task["position"]

	var to_target: Vector3 = target_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()

	if distance < 0.15:
		if not current_task.is_empty():
			is_working = true
			work_timer = 0.0
			current_work_duration = _compute_work_duration()
			_reset_pose()
			_show_tool_for_task()
			return
		_pick_new_target()
		_reset_pose()
		return

	_move_toward(to_target, distance, delta)


## Diminue faim, energie et soif au fil du temps
func _update_needs(delta: float) -> void:
	hunger = max(hunger - hunger_depletion_rate * delta, 0.0)
	energy = max(energy - energy_depletion_rate * delta, 0.0)
	thirst = max(thirst - thirst_depletion_rate * delta, 0.0)


## Deplacement generique reutilise par la marche normale et la recherche de
## nourriture/eau/case seche. Sprint 37 (backlog Phase 1 item 13c, "l'eau
## ralentit la marche des nains") : vitesse reduite tant que le nain se trouve
## sur une case d'eau (voir _is_on_water/VoxelWorld.is_water). Sprint 37
## (item 13a, "les arbres sont non traversables") : pas de vraie navigation
## avec obstacles (aucun A* dans ce projet), mais une legere deviation de
## direction ("steering") qui ecarte le nain des troncs proches, voir
## _tree_avoidance_offset ci-dessous.
func _move_toward(to_target: Vector3, distance: float, delta: float) -> void:
	var direction := to_target.normalized()
	var avoidance := _tree_avoidance_offset(direction)
	if avoidance != Vector3.ZERO:
		direction = (direction + avoidance).normalized()
	var effective_speed: float = move_speed
	if _is_on_water():
		effective_speed *= WATER_SLOWDOWN_FACTOR
	elif _is_climbing(direction):
		effective_speed *= SLOPE_SLOWDOWN_FACTOR
	var step: float = min(effective_speed * delta, distance)
	global_position += direction * step
	# Sprint 38 (reliefs) : la hauteur suit desormais le relief case par case
	# (avant : y fige a ground_level, le nain "flottait"/"s'enfoncait" sur une
	# colline). Voir _ground_y_at.
	global_position.y = _ground_y_at(global_position.x, global_position.z)

	# Le modele 3D n'est plus un billboard (contrairement au sprite,
	# Sprint 15) : cette rotation tourne desormais reellement le nain vers sa
	# direction de deplacement.
	var target_yaw: float = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, rotation_speed * delta)

	dwarf_model.preview_animation = "Marche"


## Sprint 38 (reliefs) : hauteur du sol (sommet de colonne + 1) a une position
## XZ donnee. Repli sur ground_level si hors carte (get_top_block_y renvoie -1).
func _ground_y_at(x: float, z: float) -> float:
	var top: int = voxel_world.get_top_block_y(int(floor(x)), int(floor(z)))
	if top < 0:
		return ground_level
	return float(top) + 1.0


## Sprint 38 (reliefs, "impacte le deplacement") : compare la hauteur du sol
## juste devant le nain (dans le sens de deplacement) a sa hauteur actuelle -
## effet simple, pas de vraie physique de pente (voir SLOPE_SLOWDOWN_FACTOR).
func _is_climbing(direction: Vector3) -> bool:
	var ahead_x: float = global_position.x + direction.x * 0.5
	var ahead_z: float = global_position.z + direction.z * 0.5
	var here_y := _ground_y_at(global_position.x, global_position.z)
	var ahead_y := _ground_y_at(ahead_x, ahead_z)
	return ahead_y > here_y + 0.1


## --- Repos (energie critique) : le nain s'allonge et dort sur place ---
## Sprint 28decies : le modele 3D n'est plus un billboard, "Dormir" incline
## donc reellement tout le corps a l'horizontale (voir DwarfModel3D._process)
## au lieu de l'ancien tassement en echelle qui simulait ca sur le sprite.

func _start_resting() -> void:
	is_resting = true
	dwarf_model.preview_animation = "Dormir"
	sleep_indicator.visible = true
	if not current_task.is_empty():
		task_queue.requeue_task(current_task)
		current_task = {}


func _process_resting(delta: float) -> void:
	energy = min(energy + energy_regen_rate * delta, energy_max)
	# le "Z z z" flotte doucement au-dessus de la tete
	sleep_indicator.position.y = (HEAD_HEIGHT_APPROX + 0.35) * model_scale + sin(Time.get_ticks_msec() / 600.0) * 0.08
	if energy >= energy_rest_target:
		is_resting = false
		sleep_indicator.visible = false
		_reset_pose()


## --- Recherche de case seche avant repos (Sprint 37, backlog Phase 1 item
## 14) : "les nains ne peuvent pas dormir dans l'eau" - si l'energie devient
## critique alors que le nain se trouve sur de l'eau (ex: apres une tache
## "puiser"), il marche d'abord jusqu'a une case seche (reutilise _move_toward,
## donc profite aussi du ralentissement dans l'eau ci-dessus) avant de
## reellement commencer a se reposer (voir _start_resting).

func _is_on_water() -> bool:
	return voxel_world.is_water(int(floor(global_position.x)), int(floor(global_position.z)))


## Sprint 37 (backlog Phase 1 item 13a) : les arbres n'ont pas de vraie
## collision/pathfinding (voir les notes du projet - aucun A* dans ce jeu),
## donc on approxime "traversable/non traversable" par une deviation de
## direction ("steering") qui repousse doucement le nain des troncs proches
## situes globalement devant lui. Les arbres restent dans le groupe "trees"
## (voir Forest.gd/_spawn_tree) meme apres la conversion en MultiMesh visuel.
const TREE_AVOID_RADIUS := 1.3
const TREE_AVOID_STRENGTH := 1.6

func _tree_avoidance_offset(direction: Vector3) -> Vector3:
	var avoid := Vector3.ZERO
	for tree in get_tree().get_nodes_in_group("trees"):
		var to_tree: Vector3 = tree.global_position - global_position
		to_tree.y = 0.0
		var dist: float = to_tree.length()
		if dist < 0.001 or dist > TREE_AVOID_RADIUS:
			continue
		if direction.dot(to_tree.normalized()) < 0.2:
			continue
		var push: Vector3 = global_position - tree.global_position
		push.y = 0.0
		var weight: float = (TREE_AVOID_RADIUS - dist) / TREE_AVOID_RADIUS
		avoid += push.normalized() * weight * TREE_AVOID_STRENGTH
	return avoid


## Tire des positions au hasard sur la carte jusqu'a en trouver une qui n'est
## pas de l'eau (essais bornes par securite) ; repli sur le centre de la carte
## si vraiment aucune n'est trouvee (tres improbable, les lacs/la riviere ne
## couvrent qu'une petite partie de la carte).
func _find_dry_target() -> Vector3:
	var guard := 0
	while guard < 20:
		var x := randf_range(1.0, float(grid_width - 1))
		var z := randf_range(1.0, float(grid_depth - 1))
		if not voxel_world.is_water(int(x), int(z)):
			return Vector3(x, _ground_y_at(x, z), z)
		guard += 1
	return Vector3(grid_width / 2.0, ground_level, grid_depth / 2.0)


func _process_seeking_dry_land(delta: float) -> void:
	var to_target: Vector3 = target_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance < 0.15 or not _is_on_water():
		is_seeking_dry_land = false
		_start_resting()
		return
	_move_toward(to_target, distance, delta)


## --- Repas depuis l'inventaire (faim critique, Sprint 24quater) ---
## Avant : le nain marchait jusqu'a un buisson et mangeait sur place. Depuis
## que les baies/fruits sont recoltes en inventaire (voir BerryBushes.gd/
## Forest.gd/_complete_task "cueillir"), le nain mange directement depuis le
## stock commun, sans se deplacer - comme la construction consomme des
## materiaux sans que le nain aille les chercher physiquement.

## Toutes les ressources considerees comme nourriture (baies + fruits d'arbres)
func _food_resource_ids() -> Array:
	var ids: Array = BerryTypes.all_ids()
	for s in TreeSpecies.FRUIT_SPECIES:
		ids.append(s["fruit_resource"])
	return ids


## Cherche une ressource de nourriture disponible en inventaire ; si trouvee,
## interrompt la tache en cours (comme avant) et lance l'animation du repas
## sur place (pas de deplacement). Renvoie false si aucune nourriture stockee.
func _try_start_eating() -> bool:
	var food_id: String = ""
	for id in _food_resource_ids():
		if inventory.has_resource(id, 1):
			food_id = id
			break
	if food_id == "":
		return false

	eating_food_id = food_id
	var indicator_mat: StandardMaterial3D = food_indicator.get_surface_override_material(0)
	if indicator_mat:
		indicator_mat.albedo_color = _resource_color(food_id)
	is_eating = true
	eat_timer = 0.0
	dwarf_model.preview_animation = "Manger"
	if not current_task.is_empty():
		task_queue.requeue_task(current_task)
		current_task = {}
	return true


## Les deux bras du modele 3D convergent vers la bouche pendant "Manger"
## (voir DwarfModel3D._process) ; on fait juste suivre le fruit/la baie au
## meme rythme, puis on consomme la ressource depuis l'inventaire.
func _process_eating(delta: float) -> void:
	eat_timer += delta
	food_indicator.visible = true
	food_indicator.position.z = (0.18 - absf(sin(eat_timer * 14.0)) * 0.10) * model_scale

	if eat_timer >= eat_duration:
		if eating_food_id != "" and inventory.remove_resource(eating_food_id, 1):
			hunger = min(hunger + _food_calories(eating_food_id), hunger_max)
			print("Le nain mange : %s (faim: %d)" % [eating_food_id, int(hunger)])
		eating_food_id = ""
		is_eating = false
		food_indicator.visible = false
		_reset_pose()


## --- Boisson depuis l'inventaire (soif critique, Sprint 36) ---
## Meme principe que le repas ci-dessus (_try_start_eating/_process_eating) :
## le nain boit directement depuis le stock commun d'"eau" (rempli par la
## tache "puiser", voir ActionController.gd/TaskQueue.gd), sans se deplacer.
## Reutilise food_indicator (teinte en bleu) au lieu d'un second indicateur 3D
## dedie - is_eating et is_drinking ne sont jamais vrais en meme temps.

## Tente de commencer a boire ; interrompt la tache en cours (comme la faim) et
## lance l'animation depuis l'inventaire. Renvoie false si pas d'eau stockee.
func _try_start_drinking() -> bool:
	if not inventory.has_resource("eau", 1):
		return false

	var indicator_mat: StandardMaterial3D = food_indicator.get_surface_override_material(0)
	if indicator_mat:
		indicator_mat.albedo_color = _resource_color("eau")
	is_drinking = true
	drink_timer = 0.0
	dwarf_model.preview_animation = "Manger"  # meme geste mains->bouche, pas d'animation "Boire" dediee
	if not current_task.is_empty():
		task_queue.requeue_task(current_task)
		current_task = {}
	return true


func _process_drinking(delta: float) -> void:
	drink_timer += delta
	food_indicator.visible = true
	food_indicator.position.z = (0.18 - absf(sin(drink_timer * 14.0)) * 0.10) * model_scale

	if drink_timer >= drink_duration:
		if inventory.remove_resource("eau", 1):
			thirst = min(thirst + thirst_restore_per_gorgee, thirst_max)
			print("Le nain boit de l'eau (soif: %d)" % int(thirst))
		is_drinking = false
		food_indicator.visible = false
		_reset_pose()


## Sprint 24septies : valeur de faim restauree par la nourriture "food_id"
## (calories propres a chaque fruit/baie, voir TreeSpecies.calories_for /
## BerryTypes.calories_for) - retombe sur hunger_restore_per_berry si aucune
## valeur n'est trouvee (securite, ne devrait pas arriver en pratique).
func _food_calories(food_id: String) -> float:
	var berry_cal: float = BerryTypes.calories_for(food_id)
	if berry_cal >= 0.0:
		return berry_cal
	var fruit_cal: float = TreeSpecies.calories_for(food_id)
	if fruit_cal >= 0.0:
		return fruit_cal
	return hunger_restore_per_berry


## --- Taches (miner / couper / construire) ---

func _process_work(delta: float) -> void:
	work_timer += delta
	dwarf_model.preview_animation = "Travail"

	if work_timer >= current_work_duration:
		_hide_tools()
		_complete_task()


func _complete_task() -> void:
	# Sprint 18 : competence liee au type de tache (si il y en a une), pour
	# le gain d'xp et la chance de ressource bonus a la recolte
	var skill_id: String = SkillDefs.skill_for_task(current_task.get("type", ""))

	if current_task.get("type") == "miner":
		var resource_name: String = voxel_world.remove_block(
			current_task["bx"], current_task["by"], current_task["bz"]
		)
		if resource_name != "":
			_collect_resource(resource_name)
			if _roll_bonus_yield(skill_id):
				_collect_resource(resource_name)
	elif current_task.get("type") == "couper":
		var tree = current_task.get("tree")
		# Sprint 20 : chaque arbre porte son type de bois en metadonnee
		# (espece de l'arbre, voir Forest.gd/TreeSpecies.gd) ; a lire avant
		# de detruire le noeud
		var wood_type: String = "bois"
		if is_instance_valid(tree):
			wood_type = tree.get_meta("wood_resource", "bois")
			# Sprint 34 : depuis la refonte perf de Forest.gd, tout le visuel
			# de l'arbre (tronc/branches/feuillage) vit dans des maillages
			# partages entre TOUS les arbres, plus comme enfants de "tree" -
			# il faut donc explicitement les cacher ici, sinon ils restent
			# visibles pour toujours meme apres tree.queue_free().
			if forest and forest.has_method("hide_tree_visuals"):
				forest.hide_tree_visuals(tree)
			tree.queue_free()
		var wood_count: int = 2 if _roll_bonus_yield(skill_id) else 1
		for i in range(wood_count):
			_collect_resource(wood_type)
			# Le compteur generique "bois" reste alimente en plus du type
			# specifique, pour que la construction (qui ne connait que
			# "bois" generique) continue de fonctionner sans etre modifiee
			if wood_type != "bois":
				inventory.add_resource("bois", 1)
	elif current_task.get("type") == "construire":
		var material: String = current_task["material"]
		var bx: int = current_task["bx"]
		var bz: int = current_task["bz"]
		if inventory.remove_resource(material, 1):
			voxel_world.build_block(bx, bz, material)
			print("Mur en %s construit a (%d, %d)" % [material, bx, bz])
		else:
			print("Pas assez de %s pour construire (tache annulee)" % material)
		build_task_finished.emit(current_task.get("id", -1), bx, bz)
	elif current_task.get("type") == "cueillir":
		# Sprint 24ter : recolte un fruit/une baie sans detruire la cible -
		# generique entre arbres fruitiers (Forest.gd) et buissons
		# (BerryBushes.gd), qui partagent les memes metadonnees
		# fruit_resource/fruits_left et la convention de nommage Fruit_%d.
		var target: Node = current_task.get("tree")
		if is_instance_valid(target):
			var fruit_resource: String = target.get_meta("fruit_resource", "")
			var fruits_left: int = target.get_meta("fruits_left", 0)
			if fruit_resource != "" and fruits_left > 0:
				fruits_left = _harvest_one_fruit(target, fruits_left)
				_collect_resource(fruit_resource)
				# Sprint 24septies : bonus de recolte (competence Agriculture,
				# voir SkillDefinitions.gd) - meme principe que miner/couper,
				# mais limite aux fruits reellement encore disponibles sur la
				# cible (pas question de recolter plus qu'il n'y en a).
				if fruits_left > 0 and _roll_bonus_yield(skill_id):
					_harvest_one_fruit(target, fruits_left)
					_collect_resource(fruit_resource)
	elif current_task.get("type") == "puiser":
		# Sprint 36 : contrairement a "miner", on ne retire rien de VoxelWorld -
		# l'eau est une ressource renouvelable (voir VoxelWorld.is_water).
		_collect_resource("eau")

	if skill_id != "":
		_gain_skill_xp(skill_id, SKILL_XP_PER_TASK)

	# Sprint 26 : signale la fin de la tache (quel que soit son type) pour
	# que ActionController.gd retire l'icone temporaire affichee au moment
	# de la designation
	task_finished.emit(current_task.get("id", -1))

	current_task = {}
	is_working = false
	_pick_new_target()


## Sprint 24septies : retire un fruit de "target" (fruits_left-1 -> meta +
## suppression du noeud Fruit_%d correspondant), utilise pour la recolte de
## base et pour le fruit bonus eventuel (voir _complete_task/"cueillir").
## Renvoie le nouveau nombre de fruits restants.
func _harvest_one_fruit(target: Node, fruits_left: int) -> int:
	var new_count: int = fruits_left - 1
	target.set_meta("fruits_left", new_count)
	var fruit_node: Node = target.get_node_or_null("Fruit_%d" % new_count)
	if fruit_node:
		fruit_node.queue_free()
	return new_count


## Ajoute la ressource a l'inventaire et fait apparaitre/grossir un tas au sol
## (Sprint 5 : cube qui sautait puis disparaissait ; Sprint 24septies : la
## ressource est deja comptee en inventaire tout de suite comme avant, seul
## le visuel change - un petit tas qui reste en place indefiniment, en
## attendant un futur systeme de transport vers des zones de stockage).
## Sprint 37 (backlog Phase 1 items 10/11, "objets de recolte a part entiere"
## + "piles d'objets") : le tas est desormais une vraie entite (groupe
## "resource_piles", meta resource_name/count) au lieu d'un simple decor -
## les recoltes proches du meme type fusionnent dans le meme tas au lieu de
## creer un nouveau tas a chaque fois, et le compte est affiche au survol
## (voir ActionController._describe_resource_pile).
const PILE_MERGE_RADIUS := 1.2
const PILE_MAX_SCALE := 1.8

func _collect_resource(resource_name: String) -> void:
	inventory.add_resource(resource_name, 1)
	_add_to_resource_pile(resource_name, global_position)
	print("Recolte : +1 %s (total %d)" % [resource_name, inventory.get_count(resource_name)])


## Cherche un tas existant du meme type de ressource a proximite ; l'agrandit
## et incremente son compteur si trouve, sinon en cree un nouveau.
func _add_to_resource_pile(resource_name: String, pos: Vector3) -> void:
	var pile: Node3D = _find_nearby_pile(resource_name, pos)
	if pile != null:
		var count: int = int(pile.get_meta("count")) + 1
		pile.set_meta("count", count)
		pile.scale = Vector3.ONE * clampf(1.0 + float(count) * 0.03, 1.0, PILE_MAX_SCALE)
		return
	pile = Node3D.new()
	pile.position = pos
	pile.add_to_group("resource_piles")
	pile.set_meta("resource_name", resource_name)
	pile.set_meta("count", 1)
	get_parent().add_child(pile)
	_build_pile_visual(pile, resource_name)


func _find_nearby_pile(resource_name: String, pos: Vector3) -> Node3D:
	for pile in get_tree().get_nodes_in_group("resource_piles"):
		if String(pile.get_meta("resource_name")) != resource_name:
			continue
		if pile.global_position.distance_to(pos) <= PILE_MERGE_RADIUS:
			return pile
	return null


## Petit tas de 3-4 morceaux colores pose au sol a l'endroit de la recolte -
## visuel construit une seule fois a la creation du tas (les recoltes
## suivantes du meme tas se contentent d'agrandir le node, voir
## _add_to_resource_pile, pour eviter d'accumuler des noeuds a l'infini).
func _build_pile_visual(pile: Node3D, resource_name: String) -> void:
	var color := _resource_color(resource_name)
	var chunk_count := randi_range(3, 4)
	for i in range(chunk_count):
		var chunk := MeshInstance3D.new()
		var box := BoxMesh.new()
		var size: float = randf_range(0.12, 0.20)
		box.size = Vector3(size, size * 0.7, size)
		chunk.mesh = box
		var angle := randf_range(0.0, TAU)
		var dist := randf_range(0.0, 0.12)
		chunk.position = Vector3(cos(angle) * dist, size * 0.35, sin(angle) * dist)
		chunk.rotation.y = randf_range(0.0, TAU)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		chunk.set_surface_override_material(0, mat)
		pile.add_child(chunk)


func _resource_color(resource_name: String) -> Color:
	if resource_name.begins_with("bois"):  # "bois", "bois_chene", "bois_sapin", "bois_bouleau" (Sprint 20)
		return Color(0.4, 0.25, 0.1)
	match resource_name:
		"pierre":
			return Color(0.55, 0.55, 0.55)
		"terre":
			return Color(0.35, 0.25, 0.15)
		"eau":
			return Color(0.25, 0.55, 0.85)
		_:
			# Sprint 23 : metaux/pierres precieuses recoltes en filon - couleur
			# reprise directement de MetalTypes.gd/GemTypes.gd (via VeinMaterials)
			# pour que l'item recolte corresponde visuellement au filon mine.
			var vein: Dictionary = VeinMaterials.get_type(resource_name)
			if not vein.is_empty():
				return vein["couleur"]
			# Sprint 24ter/quater : fruits d'arbres et baies - couleur reprise
			# de TreeSpecies.gd (FRUIT_SPECIES) / BerryTypes.gd
			var berry: Dictionary = BerryTypes.get_type(resource_name)
			if not berry.is_empty():
				return berry["couleur"]
			if TreeSpecies.is_fruit(resource_name):
				return TreeSpecies.fruit_color_for(resource_name)
			return Color(1, 1, 1)


## Sprint 37 (backlog Phase 1 item 6, "confort thermique") : statut
## chaud/froid/normal du nain, base sur la temperature ambiante actuelle
## (TemperatureSystem.gd). Purement informatif pour l'instant (affiche dans la
## fiche personnage) - aucun effet sur le gameplay, en attendant un futur
## systeme d'habits qui viendra attenuer cet effet (voir memoire backlog).
const COLD_THRESHOLD := 0.0
const HOT_THRESHOLD := 30.0

func temperature_status() -> String:
	if temperature_system == null:
		return "Normal"
	var temp: float = temperature_system.current_temperature()
	if temp <= COLD_THRESHOLD:
		return "Froid"
	elif temp >= HOT_THRESHOLD:
		return "Chaud"
	return "Normal"


## Choisit une nouvelle case cible aleatoire sur la carte (marge de 1 bloc au bord).
## Sprint 37 (backlog Phase 1 item 13b) : evite de choisir une case d'eau
## profonde (>1 niveau) comme destination de balade - les lacs profonds sont
## donc contournes plutot que traverses (voir VoxelWorld.water_depth_at).
func _pick_new_target() -> void:
	var x := randf_range(1.0, float(grid_width - 1))
	var z := randf_range(1.0, float(grid_depth - 1))
	var guard := 0
	while voxel_world.water_depth_at(int(x), int(z)) > 1 and guard < 20:
		x = randf_range(1.0, float(grid_width - 1))
		z = randf_range(1.0, float(grid_depth - 1))
		guard += 1
	target_position = Vector3(x, ground_level, z)
