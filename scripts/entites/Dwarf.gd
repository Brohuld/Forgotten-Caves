extends Node3D
## Nain : se deplace, travaille (miner/couper/construire/cueillir), gere ses
## besoins (faim/energie/soif) et affiche un modele 3D personnalisable.
## Plusieurs instances tournent simultanement, toutes dans le groupe
## "dwarves" (retrouvables par l'UI et les autres scripts).
##
## Le nain choisit ses destinations dans la TaskQueue en priorite (miner/
## couper/construire, la tache la plus proche d'abord), et erre au hasard
## pres du camp seulement s'il n'y a rien a faire. Quand un besoin devient
## critique, il interrompt son activite pour manger/boire/se reposer.
##
## La faim/soif se resolvent directement depuis l'inventaire commun (fruits/
## baies/eau recoltes au prealable) - le nain ne se deplace donc pas jusqu'a
## une source de nourriture ou d'eau pour se nourrir, seulement pour la
## recolte elle-meme (voir _try_start_eating/_try_start_drinking dans
## DwarfNeeds.gd).
##
## L'apparence est un modele 3D procedural (voir DwarfModel3D.gd) instancie
## en enfant de "body" ; 4 couleurs personnalisables (cheveux/barbe/tenue/
## armure) sont transmises au modele, le reste (coiffure/barbe/corpulence)
## est tire au hasard a la creation. Un outil (pioche/hache/marteau) apparait
## pres des mains pendant le travail, un repere "Zzz" pendant le repos, un
## repere de nourriture pendant le repas/la boisson.
##
## Architecture : ce fichier ne garde que l'orchestration de la boucle de jeu
## (_ready/_process/_handle_critical_needs/_update_needs/_process_work/
## _pick_new_target/temperature_status) et la propriete des donnees
## (proprietes @export/var). Les responsabilites specifiques sont extraites
## dans des fichiers dedies, lus/ecrits via get()/set() sur cette instance :
## - DwarfSkills.gd       : caracteristiques/competences (generation, xp, duree de travail, bonus de recolte)
## - DwarfVisuals.gd      : apparence et accessoires visuels
## - DwarfMovement.gd     : deplacement/steering, relief, eau
## - DwarfNeeds.gd        : besoins critiques (repos/repas/boisson)
## - DwarfTaskResolver.gd : resolution d'une tache terminee
## - DwarfResourcePile.gd : tas de ressources au sol
## Les fonctions de ce fichier qui ne font que rediriger vers ces scripts
## sont marquees "simple delegation".

const SkillDefs := preload("res://scripts/data/creatures/nains/caracteristiques/SkillDefinitions.gd")
const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")
const TreeSpecies := preload("res://scripts/data/materiaux/types/bois/TreeSpecies.gd")
const BerryTypes := preload("res://scripts/data/materiaux/types/baies/BerryTypes.gd")
const DwarfModel3DScript := preload("res://scripts/prototypes/DwarfModel3D.gd")
const NainNames := preload("res://scripts/data/creatures/nains/NainNames.gd")
const DayNightCycleScript := preload("res://scripts/systemes/DayNightCycle.gd")
const VoxelWorldScript := preload("res://scripts/monde/VoxelWorld.gd")
const DwarfSkillsScript := preload("res://scripts/entites/DwarfSkills.gd")
var skills: DwarfSkillsScript = DwarfSkillsScript.new()

const DwarfVisualsScript := preload("res://scripts/entites/DwarfVisuals.gd")
const DwarfMovementScript := preload("res://scripts/entites/DwarfMovement.gd")
const DwarfNeedsScript := preload("res://scripts/entites/DwarfNeeds.gd")
const DwarfTaskResolverScript := preload("res://scripts/entites/DwarfTaskResolver.gd")

## Emis par DwarfTaskResolver.gd (complete_construire_task) via
## dwarf.emit_signal("build_task_finished", ...) plutot qu'un appel direct,
## car ce fichier recoit "dwarf" type generiquement Node3D. L'analyseur
## GDScript ne detecte pas cet usage indirect, d'ou l'avertissement
## UNUSED_SIGNAL sans consequence (le signal reste bien emis/connecte, voir
## ActionController.gd/_on_build_task_finished) - supprime explicitement.
@warning_ignore("unused_signal")
signal build_task_finished(task_id: int, bx: int, bz: int)
## Signal generique emis a la fin de N'IMPORTE QUELLE tache (miner/couper/
## cueillir/construire), utilise par ActionController.gd pour retirer
## l'icone temporaire affichee sur l'objet designe. Independant de
## build_task_finished ci-dessus (reserve au mur fantome).
@warning_ignore("unused_signal")
signal task_finished(task_id: int)

## Vide par defaut -> genere aleatoirement a la creation (voir _ready,
## NainNames.gd). Une valeur forcee a la main (Inspecteur/.tscn) est
## respectee et n'est pas ecrasee - utile pour un futur nain nomme/unique.
@export var dwarf_name: String = ""

# Personnalisation par region : couleurs par defaut proches de
# l'illustration d'origine du personnage.
@export var hair_color: Color = Color(0.59, 0.45, 0.33)
@export var beard_color: Color = Color(0.80, 0.71, 0.53)
@export var clothing_color: Color = Color(0.68, 0.51, 0.41)
@export var armor_color: Color = Color(0.55, 0.55, 0.58)

# Le modele a son origine locale a y=0 (au niveau des pieds) : un scale
# uniforme autour de cette origine ne decale donc pas verticalement le nain,
# les pieds restent au sol.
@export var model_scale: float = 0.8

# Doivent correspondre a VoxelWorld.gd
## "var" (pas "const") car DwarfMovement.gd lit ces 3 valeurs dynamiquement
## via dwarf.get("grid_width") - un "const" n'est pas visible via get().
## Initialise directement depuis VoxelWorld.WIDTH/DEPTH/HEIGHT ; rien
## d'autre ne reaffecte ces proprietes ensuite, donc toujours synchronise.
var grid_width: int = VoxelWorldScript.WIDTH
var grid_depth: int = VoxelWorldScript.DEPTH
var ground_level: float = float(VoxelWorldScript.HEIGHT)  # sommet de la carte
# ground_level ne sert plus que de repli (terrain plat sans collines, ou
# position hors carte) - la hauteur reelle du nain suit le relief case par
# case via _ground_y_at.

@export var move_speed: float = 3.0        # unites / seconde
@export var rotation_speed: float = 8.0    # vitesse de rotation vers la direction
@export var work_duration: float = 1.5     # secondes pour miner/couper une fois arrive

# WATER_SLOWDOWN_FACTOR/SLOPE_SLOWDOWN_FACTOR (facteurs de ralentissement en
# eau/en montee, effet simple sans vraie physique de pente) vivent dans
# DwarfMovement.gd.

# Besoins - vitesses volontairement rapides pour tester sans attendre
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

# Soif - meme principe que la faim, taux de depletion legerement superieur
# (devient critique un peu plus vite que la faim).
@export var thirst_max: float = 100.0
@export var thirst_depletion_rate: float = 9.0   # points / seconde
@export var thirst_critical: float = 20.0
@export var thirst_restore_per_gorgee: float = 50.0
@export var drink_duration: float = 1.2          # secondes, animation de boire

# HEAD_HEIGHT_APPROX (repere de hauteur de tete pour positionner les
# indicateurs) vit dans DwarfVisuals.gd et DwarfNeeds.gd.

var hunger: float = 100.0
var energy: float = 100.0
var thirst: float = 100.0

# Caracteristiques de base : 1-10 pour les 5 premieres, un pourcentage pour
# le bonheur. Generees une fois a la creation (voir
# DwarfSkills.generate_characteristics()).
var force: int = 0
var agilite: int = 0
var constitution: int = 0
var intelligence: int = 0
var beaute: int = 0
var bonheur: int = 0

# Competences : id (voir SkillDefinitions.gd) -> niveau / xp dans le niveau
# actuel. Generees a la creation, progressent avec l'usage (voir
# DwarfSkills.generate_skills()/gain_xp()).
var skill_levels: Dictionary = {}
var skill_xp: Dictionary = {}
var current_work_duration: float = 1.5  # duree effective de la tache en cours (ajustee par la competence)

var target_position: Vector3
var dwarf_model: Node3D  # instance de DwarfModel3D, enfant de "body"

# Accessoires d'action
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
var eating_food_id: String = ""  # id de la ressource en train d'etre mangee (inventaire)

var is_drinking: bool = false
var drink_timer: float = 0.0

# Le nain ne doit pas s'endormir sur une case d'eau - si l'energie devient
# critique alors qu'il s'y trouve, il marche d'abord jusqu'a une case seche
# (voir DwarfMovement.gd/process_seeking_dry_land) avant de se reposer.
var is_seeking_dry_land: bool = false

## Inventaire personnel : stub minimal - emplacements nommes avec un contenu
## texte libre ("" = vide), affiches en lecture seule dans l'onglet
## Equipement de la fiche personnage (CharacterSheetUI). Un vrai systeme
## d'equipement (artisanat, bonus de stats, habits qui protegent du froid -
## voir temperature_status) n'est pas implemente ici.
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
@onready var forest: Node3D = %Forest  # necessaire pour hide_tree_visuals() avant de couper un arbre, voir DwarfTaskResolver.gd
@onready var ground_decoration: Node3D = %GroundDecoration  # necessaire pour remove_decoration_at() apres avoir mine un bloc, voir DwarfTaskResolver.gd
@onready var temperature_system: Node = %TemperatureSystem  # confort thermique, voir temperature_status()


func _ready() -> void:
	# Petit decalage aleatoire au demarrage pour eviter que plusieurs nains
	# ne se superposent exactement au meme endroit. Base sur
	# voxel_world.colony_spawn_center (calcule une seule fois par
	# VoxelWorld._ready(), garanti hors eau - meme point que le stock de
	# bois de depart, voir DwarfResourcePile.spawn_starting_wood_stock)
	# plutot que le centre brut de la carte, qui peut tomber dans l'eau.
	var spawn_rng: RandomNumberGenerator = GameRandom.get_rng("nains_spawn")
	var jitter_x := spawn_rng.randf_range(-1.5, 1.5)
	var jitter_z := spawn_rng.randf_range(-1.5, 1.5)
	var spawn_center: Vector2 = voxel_world.colony_spawn_center if voxel_world != null else Vector2(grid_width / 2.0, grid_depth / 2.0)
	var spawn_x: float = spawn_center.x + jitter_x
	var spawn_z: float = spawn_center.y + jitter_z
	global_position = Vector3(spawn_x, _ground_y_at(spawn_x, spawn_z), spawn_z)
	add_to_group("dwarves")
	if dwarf_name == "":
		dwarf_name = NainNames.random_name()
	if OS.is_debug_build():
		print("[Spawn nain] %s a (%.1f, %.1f), dans l'eau ? %s" % [dwarf_name, spawn_x, spawn_z, voxel_world.is_water(int(spawn_x), int(spawn_z)) if voxel_world != null else "voxel_world null"])
	# Generation deleguee a DwarfSkills.gd, Dwarf.gd assigne juste le
	# resultat a ses propres champs.
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
	if OS.is_debug_build():
		print("[Perf] Nain '%s' : modele 3D construit en %.2f s (temps ecoule depuis debut de scene : %.1f s)" % [dwarf_name, build_ms / 1000.0, elapsed_since_scene_start_ms / 1000.0])
	_pick_new_target()


## Passe-plat conserve pour compatibilite : CharacterSheetUI.gd appelle
## directement dwarf._xp_needed_for_level(level) (affichage de la barre
## d'xp), ce nom doit donc rester disponible sur Dwarf.gd meme si le calcul
## reel vit dans DwarfSkills.gd.
func _xp_needed_for_level(level: int) -> float:
	return skills.xp_needed_for_level(level)


## Apparence/accessoires - simple delegation vers DwarfVisuals.gd.
func _build_appearance() -> void:
	DwarfVisualsScript.build_appearance(self)


func _reset_pose() -> void:
	DwarfVisualsScript.reset_pose(self)


func _show_tool_for_task() -> void:
	DwarfVisualsScript.show_tool_for_task(self)


func _hide_tools() -> void:
	DwarfVisualsScript.hide_tools(self)


func _process(delta: float) -> void:
	# Multiplicateur de vitesse du temps (Pause/x1/x2/x4, voir
	# ActionController.gd/DayNightCycle.game_speed) : en multipliant delta
	# une seule fois ici, tout ce qui suit (deplacement, besoins, travail,
	# repas/boisson, repos) suit deja la meme vitesse. Volontairement pas
	# applique a CameraRig.gd : la camera doit rester utilisable en pause.
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
## verifiee avant la faim (priorite un peu plus urgente). Renvoie true si un
## besoin critique a pris le dessus ce frame (l'appelant _process doit alors
## return immediatement, un traitement est deja en cours).
func _handle_critical_needs(delta: float) -> bool:
	if energy <= energy_critical:
		# Pas de sieste dans l'eau - si le nain s'y trouve, il marche
		# d'abord vers une case seche.
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


## Deplacement/steering/relief - simples delegations vers DwarfMovement.gd.
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


## Besoins critiques (repos/repas/boisson) - simples delegations vers
## DwarfNeeds.gd.
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


## Resolution de tache terminee - simple delegation vers
## DwarfTaskResolver.gd.
func _complete_task() -> void:
	DwarfTaskResolverScript.complete_task(self)


## Statut chaud/froid/normal du nain, base sur la temperature ambiante
## actuelle (TemperatureSystem.gd). Purement informatif pour l'instant
## (affiche dans la fiche personnage) - aucun effet sur le gameplay, en
## attendant un futur systeme d'habits qui viendra attenuer cet effet.
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


## La balade au hasard des nains oisifs est bornee a un rayon fixe autour du
## point de spawn de la colonie (voxel_world.colony_spawn_center) plutot que
## de toute la carte, pour que les nains sans tache restent pres de la base
## quelle que soit la taille de la carte.
const IDLE_WANDER_RADIUS := 20.0

## Choisit une nouvelle case cible aleatoire pres du camp (voir
## IDLE_WANDER_RADIUS), avec une marge de 1 bloc au bord de la carte. Evite
## de choisir une case d'eau profonde (>1 niveau) comme destination - les
## lacs profonds sont donc contournes plutot que traverses (voir
## VoxelWorld.water_depth_at).
func _pick_new_target() -> void:
	var center: Vector2 = voxel_world.colony_spawn_center if voxel_world != null else Vector2(grid_width / 2.0, grid_depth / 2.0)
	var x := clampf(center.x + randf_range(-IDLE_WANDER_RADIUS, IDLE_WANDER_RADIUS), 1.0, float(grid_width - 1))
	var z := clampf(center.y + randf_range(-IDLE_WANDER_RADIUS, IDLE_WANDER_RADIUS), 1.0, float(grid_depth - 1))
	var guard := 0
	while voxel_world.water_depth_at(int(x), int(z)) > 1 and guard < 20:
		x = clampf(center.x + randf_range(-IDLE_WANDER_RADIUS, IDLE_WANDER_RADIUS), 1.0, float(grid_width - 1))
		z = clampf(center.y + randf_range(-IDLE_WANDER_RADIUS, IDLE_WANDER_RADIUS), 1.0, float(grid_depth - 1))
		guard += 1
	target_position = Vector3(x, ground_level, z)
