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

const SkillDefs := preload("res://scripts/data/creatures/nains/caracteristiques/SkillDefinitions.gd")
const VeinMaterials := preload("res://scripts/data/materiaux/types/VeinMaterials.gd")
const TreeSpecies := preload("res://scripts/data/materiaux/types/bois/TreeSpecies.gd")
const BerryTypes := preload("res://scripts/data/materiaux/types/baies/BerryTypes.gd")
const DwarfModel3DScript := preload("res://scripts/prototypes/DwarfModel3D.gd")
const NainNames := preload("res://scripts/data/creatures/nains/NainNames.gd")

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
@export var grid_width: int = 20
@export var grid_depth: int = 20
@export var ground_level: float = 30.0  # sommet de la carte (HEIGHT, Sprint 23 : 10 -> 30)

@export var move_speed: float = 3.0        # unites / seconde
@export var rotation_speed: float = 8.0    # vitesse de rotation vers la direction
@export var work_duration: float = 1.5     # secondes pour miner/couper une fois arrive

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

@onready var body: Node3D = $Body
@onready var task_queue: Node = %TaskQueue
@onready var voxel_world: Node3D = %VoxelWorld
@onready var inventory: Node = %Inventory


func _ready() -> void:
	# Petit decalage aleatoire au demarrage pour eviter que plusieurs nains
	# ne se superposent exactement au meme endroit (Sprint 11)
	var jitter_x := randf_range(-1.5, 1.5)
	var jitter_z := randf_range(-1.5, 1.5)
	global_position = Vector3(grid_width / 2.0 + jitter_x, ground_level, grid_depth / 2.0 + jitter_z)
	add_to_group("dwarves")
	if dwarf_name == "":
		dwarf_name = NainNames.random_name()
	_generate_characteristics()
	_generate_skills()
	_build_appearance()
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

func _build_appearance() -> void:
	dwarf_model = Node3D.new()
	dwarf_model.set_script(DwarfModel3DScript)
	dwarf_model.name = "DwarfModel"
	body.add_child(dwarf_model)

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
	dwarf_model._rebuild()
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

	# Les besoins critiques passent avant les taches et l'errance
	if energy <= energy_critical:
		_start_resting()
		return
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


## Diminue faim et energie au fil du temps
func _update_needs(delta: float) -> void:
	hunger = max(hunger - hunger_depletion_rate * delta, 0.0)
	energy = max(energy - energy_depletion_rate * delta, 0.0)


## Deplacement generique reutilise par la marche normale et la recherche de nourriture
func _move_toward(to_target: Vector3, distance: float, delta: float) -> void:
	var direction := to_target.normalized()
	var step: float = min(move_speed * delta, distance)
	global_position += direction * step

	# Le modele 3D n'est plus un billboard (contrairement au sprite,
	# Sprint 15) : cette rotation tourne desormais reellement le nain vers sa
	# direction de deplacement.
	var target_yaw: float = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, rotation_speed * delta)

	dwarf_model.preview_animation = "Marche"


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


## Ajoute la ressource a l'inventaire et fait apparaitre un petit tas au sol
## (Sprint 5 : cube qui sautait puis disparaissait ; Sprint 24septies : la
## ressource est deja comptee en inventaire tout de suite comme avant, seul
## le visuel change - un petit tas qui reste en place indefiniment, en
## attendant un futur systeme de transport vers des zones de stockage).
func _collect_resource(resource_name: String) -> void:
	inventory.add_resource(resource_name, 1)
	_spawn_resource_pile(resource_name, global_position)
	print("Recolte : +1 %s (total %d)" % [resource_name, inventory.get_count(resource_name)])


## Petit tas de 3-4 morceaux colores pose au sol a l'endroit de la recolte -
## purement visuel/repere pour l'instant, ne disparait pas tout seul.
func _spawn_resource_pile(resource_name: String, pos: Vector3) -> void:
	var pile := Node3D.new()
	pile.position = pos
	get_parent().add_child(pile)

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


## Choisit une nouvelle case cible aleatoire sur la carte (marge de 1 bloc au bord)
func _pick_new_target() -> void:
	var x := randf_range(1.0, float(grid_width - 1))
	var z := randf_range(1.0, float(grid_depth - 1))
	target_position = Vector3(x, ground_level, z)
