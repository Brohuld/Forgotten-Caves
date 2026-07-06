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
## 2026-07-05 (revue de code, dette d'architecture A1) : le systeme de
## caracteristiques/competences (generation + xp + duree de travail + bonus
## de recolte) a ete extrait dans DwarfSkills.gd (RefCounted, voir "skills"
## ci-dessous) - Dwarf.gd garde la propriete des donnees (skill_levels/
## skill_xp/force/etc.), DwarfSkills.gd ne fait que le calcul. Aucun
## changement d'API externe (CharacterSheetUI.gd inchange).
## 2026-07-06 (revue de code, dette d'architecture A1, I60) : le reste des
## responsabilites (apparence/accessoires, deplacement/steering, besoins
## critiques repos/repas/boisson, resolution des taches, tas de ressources)
## a ete extrait mecaniquement en 5 nouveaux fichiers - voir
## DwarfVisuals.gd/DwarfMovement.gd/DwarfNeeds.gd/DwarfTaskResolver.gd/
## DwarfResourcePile.gd. Dwarf.gd ne garde que l'orchestration de la boucle
## de jeu (_ready/_process/_handle_critical_needs/_update_needs/
## _process_work/_pick_new_target/temperature_status) + toutes les donnees
## (proprietes @export/var), lues/ecrites par les fichiers extraits via
## get()/set(). Aucun changement de comportement/API interne ; les fonctions
## ci-dessous qui delegent sont marquees "simple delegation".

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
## 2026-07-05 (revue de code, item F010) : uniquement pour le garde-fou de
## _ready() ci-dessous (grid_width/grid_depth/ground_level dupliques ci-dessous).
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")
## 2026-07-05 (revue de code, dette d'architecture A1) : voir commentaire de
## classe ci-dessus - systeme de caracteristiques/competences extrait.
const DwarfSkillsScript := preload("res://scripts/entites/DwarfSkills.gd")
var skills: DwarfSkillsScript = DwarfSkillsScript.new()

## 2026-07-06 (dette A1, I60) : apparence/accessoires visuels, deplacement/
## steering, besoins critiques et resolution des taches extraits - voir
## commentaire de classe ci-dessus.
const DwarfVisualsScript := preload("res://scripts/entites/DwarfVisuals.gd")
const DwarfMovementScript := preload("res://scripts/entites/DwarfMovement.gd")
const DwarfNeedsScript := preload("res://scripts/entites/DwarfNeeds.gd")
const DwarfTaskResolverScript := preload("res://scripts/entites/DwarfTaskResolver.gd")

## 2026-07-06 (dette A1, I60) : emis via dwarf.emit_signal("build_task_finished",
## ...) depuis DwarfTaskResolver.gd (complete_construire_task) plutot qu'un
## "build_task_finished.emit(...)" direct - necessaire car ce fichier recoit
## "dwarf" type generiquement Node3D (voir doc de classe). L'analyseur
## GDScript ne detecte pas cet usage indirect, d'ou l'avertissement
## UNUSED_SIGNAL sans consequence (le signal reste emis/connecte normalement,
## voir ActionController.gd/_on_build_task_finished) - supprime explicitement.
@warning_ignore("unused_signal")
signal build_task_finished(task_id: int, bx: int, bz: int)
## Sprint 26 : signal generique emis a la fin de N'IMPORTE QUELLE tache
## (miner/couper/cueillir/construire), utilise par ActionController.gd pour
## retirer l'icone temporaire affichee sur l'objet designe. Independant de
## build_task_finished ci-dessus (garde pour le mur fantome, inchange).
## 2026-07-06 (dette A1, I60) : meme remarque que ci-dessus - emis via
## dwarf.emit_signal("task_finished", ...) depuis DwarfTaskResolver.gd.
@warning_ignore("unused_signal")
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
# le nain traverse une case d'eau (voir DwarfMovement.gd).
# Sprint 38 (reliefs, "impacte le deplacement") : facteur applique en montee -
# effet simple (pas de vraie physique de pente), meme principe que
# ci-dessus. Voir DwarfMovement.gd.
# 2026-07-06 (dette A1, I60) : WATER_SLOWDOWN_FACTOR/SLOPE_SLOWDOWN_FACTOR
# deplaces dans DwarfMovement.gd (consts, plus utilisees ici).

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
# 2026-07-06 (dette A1, I60) : HEAD_HEIGHT_APPROX deplace/duplique dans
# DwarfVisuals.gd et DwarfNeeds.gd (consts, plus utilise ici).

var hunger: float = 100.0
var energy: float = 100.0
var thirst: float = 100.0

# Caracteristiques de base (Sprint 12) : 1-10 pour les 5 premieres, un
# pourcentage pour le bonheur. Generees une fois a la creation du nain
# (voir DwarfSkills.generate_characteristics(), 2026-07-05).
var force: int = 0
var agilite: int = 0
var constitution: int = 0
var intelligence: int = 0
var beaute: int = 0
var bonheur: int = 0

# Competences (Sprint 18) : id (voir SkillDefinitions.gd) -> niveau / xp
# dans le niveau actuel. Generees a la creation, progressent avec l'usage
# (voir DwarfSkills.generate_skills()/gain_xp(), 2026-07-05).
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
# l'eau, il marche d'abord jusqu'a une case seche (voir DwarfMovement.gd/
# process_seeking_dry_land) avant de reellement commencer a se reposer.
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
# hide_tree_visuals() avant de couper un arbre - voir DwarfTaskResolver.gd.
@onready var forest: Node3D = %Forest
# 2026-07-05 (correctif bug "decoration ne disparait pas au minage") :
# reference a GroundDecoration.gd, necessaire pour remove_decoration_at()
# apres avoir mine un bloc - voir DwarfTaskResolver.gd.
@onready var ground_decoration: Node3D = %GroundDecoration
# Sprint 37 (backlog Phase 1 item 6) : confort thermique, voir temperature_status()
@onready var temperature_system: Node = %TemperatureSystem


func _ready() -> void:
	# 2026-07-05 (revue de code, item F010) : grid_width/grid_depth/ground_level
	# dupliques en dur (aucune garde-fou automatique auparavant) - avertissement
	# si desynchronise de VoxelWorld.gd, sans changer le comportement.
	if grid_width != VoxelWorldScript.WIDTH or grid_depth != VoxelWorldScript.DEPTH or not is_equal_approx(ground_level, float(VoxelWorldScript.HEIGHT)):
		push_warning("Dwarf.grid_width/grid_depth/ground_level (%d/%d/%.1f) desynchronise de VoxelWorld (%d/%d/%d)" % [grid_width, grid_depth, ground_level, VoxelWorldScript.WIDTH, VoxelWorldScript.DEPTH, VoxelWorldScript.HEIGHT])
	# Petit decalage aleatoire au demarrage pour eviter que plusieurs nains
	# ne se superposent exactement au meme endroit (Sprint 11)
	# 2026-07-06 (revue de code, paquet A) : flux GameRandom dedie
	# "nains_spawn" au lieu de randf_range() global - voir GameRandom.gd.
	var spawn_rng: RandomNumberGenerator = GameRandom.get_rng("nains_spawn")
	var jitter_x := spawn_rng.randf_range(-1.5, 1.5)
	var jitter_z := spawn_rng.randf_range(-1.5, 1.5)
	var spawn_x: float = grid_width / 2.0 + jitter_x
	var spawn_z: float = grid_depth / 2.0 + jitter_z
	global_position = Vector3(spawn_x, _ground_y_at(spawn_x, spawn_z), spawn_z)
	add_to_group("dwarves")
	if dwarf_name == "":
		dwarf_name = NainNames.random_name()
	# 2026-07-05 (dette d'architecture A1) : generation deleguee a
	# DwarfSkills.gd, Dwarf.gd assigne juste le resultat a ses propres champs
	# (aucun changement de forme des donnees, CharacterSheetUI.gd inchange).
	var chars: Dictionary = skills.generate_characteristics()
	force = chars["force"]
	agilite = chars["agilite"]
	constitution = chars["constitution"]
	intelligence = chars["intelligence"]
	beaute = chars["beaute"]
	bonheur = chars["bonheur"]
	var sk: Dictionary = skills.generate_skills()
	skill_levels = sk["levels"]
	skill_xp = sk["xp"]
	var t0: int = Time.get_ticks_msec()
	_build_appearance()
	var build_ms: int = Time.get_ticks_msec() - t0
	var elapsed_since_scene_start_ms: int = Time.get_ticks_msec() - DayNightCycleScript.scene_start_ms
	# 2026-07-06 (revue de code, paquet D, I61) : instrumentation de perf
	# conditionnee a OS.is_debug_build() - reste visible pendant le
	# developpement (editeur/export debug) mais disparait automatiquement
	# d'un export final, sans avoir a retirer le diagnostic maintenant.
	if OS.is_debug_build():
		print("[Perf] Nain '%s' : modele 3D construit en %.2f s (temps ecoule depuis debut de scene : %.1f s)" % [dwarf_name, build_ms / 1000.0, elapsed_since_scene_start_ms / 1000.0])
	_pick_new_target()


## 2026-07-05 (correctif dette A1) : passe-plat conserve pour compatibilite -
## CharacterSheetUI.gd appelle directement dwarf._xp_needed_for_level(level)
## (affichage de la barre d'xp), ce nom doit donc rester disponible sur Dwarf.gd
## meme si le calcul reel vit maintenant dans DwarfSkills.gd.
func _xp_needed_for_level(level: int) -> float:
	return skills.xp_needed_for_level(level)


## 2026-07-06 (dette A1, I60) : apparence/accessoires - simple delegation
## vers DwarfVisuals.gd (voir sa doc). Aucun changement de comportement/API
## interne.
func _build_appearance() -> void:
	DwarfVisualsScript.build_appearance(self)


func _reset_pose() -> void:
	DwarfVisualsScript.reset_pose(self)


func _show_tool_for_task() -> void:
	DwarfVisualsScript.show_tool_for_task(self)


func _hide_tools() -> void:
	DwarfVisualsScript.hide_tools(self)


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

	if _handle_critical_needs(delta):
		return

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
			current_work_duration = skills.compute_work_duration(skill_levels, current_task, work_duration)
			_reset_pose()
			_show_tool_for_task()
			return
		_pick_new_target()
		_reset_pose()
		return

	_move_toward(to_target, distance, delta)


## Les besoins critiques passent avant les taches et l'errance. La soif est
## verifiee avant la faim (Sprint 36, priorite un peu plus urgente). Renvoie
## true si un besoin critique a pris le dessus ce frame (l'appelant _process
## doit alors return immediatement, un traitement est deja en cours).
## 2026-07-06 (revue de code Phase 3, C16) : extrait de _process() -
## depassait le seuil de 50 lignes de l'axe 1. Aucun changement de
## comportement.
func _handle_critical_needs(delta: float) -> bool:
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
		return true
	if thirst <= thirst_critical:
		if _try_start_drinking():
			return true
		# sinon (aucune eau en inventaire) : on continue normalement
	if hunger <= hunger_critical:
		if _try_start_eating():
			return true
		# sinon (aucune nourriture en inventaire) : on continue normalement
	return false


## Diminue faim, energie et soif au fil du temps
func _update_needs(delta: float) -> void:
	hunger = max(hunger - hunger_depletion_rate * delta, 0.0)
	energy = max(energy - energy_depletion_rate * delta, 0.0)
	thirst = max(thirst - thirst_depletion_rate * delta, 0.0)


## 2026-07-06 (dette A1, I60) : deplacement/steering/relief - simples
## delegations vers DwarfMovement.gd (voir sa doc). Aucun changement de
## comportement/API interne.
func _move_toward(to_target: Vector3, distance: float, delta: float) -> void:
	DwarfMovementScript.advance_toward(self, to_target, distance, delta)


func _ground_y_at(x: float, z: float) -> float:
	return DwarfMovementScript.ground_y_at(self, x, z)


func _is_on_water() -> bool:
	return DwarfMovementScript.is_on_water(self)


func _find_dry_target() -> Vector3:
	return DwarfMovementScript.find_dry_target(self)


func _process_seeking_dry_land(delta: float) -> void:
	DwarfMovementScript.process_seeking_dry_land(self, delta)


## 2026-07-06 (dette A1, I60) : besoins critiques (repos/repas/boisson) -
## simples delegations vers DwarfNeeds.gd (voir sa doc). Aucun changement de
## comportement/API interne.
func _start_resting() -> void:
	DwarfNeedsScript.start_resting(self)


func _process_resting(delta: float) -> void:
	DwarfNeedsScript.process_resting(self, delta)


func _try_start_eating() -> bool:
	return DwarfNeedsScript.try_start_eating(self)


func _process_eating(delta: float) -> void:
	DwarfNeedsScript.process_eating(self, delta)


func _try_start_drinking() -> bool:
	return DwarfNeedsScript.try_start_drinking(self)


func _process_drinking(delta: float) -> void:
	DwarfNeedsScript.process_drinking(self, delta)


## --- Taches (miner / couper / construire) ---

func _process_work(delta: float) -> void:
	work_timer += delta
	dwarf_model.preview_animation = "Travail"

	if work_timer >= current_work_duration:
		_hide_tools()
		_complete_task()


## 2026-07-06 (dette A1, I60) : resolution de tache terminee - simple
## delegation vers DwarfTaskResolver.gd (voir sa doc). Aucun changement de
## comportement/API interne.
func _complete_task() -> void:
	DwarfTaskResolverScript.complete_task(self)


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
