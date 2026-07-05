extends RefCounted
## Extrait de Dwarf.gd le 2026-07-05 (revue de code, dette d'architecture A1 :
## separation presentation/regles). Regroupe la logique de gestion pure des
## caracteristiques/competences des nains - aucune dependance a la
## presentation (mesh/animation/Node3D). Suit le meme pattern que les
## companions RefCounted de VoxelWorld.gd (VoxelVeins/VoxelMeshBuilder/
## VoxelHydrology) : pas de reference typee vers Dwarf.gd lui-meme, les
## donnees (skill_levels/skill_xp/current_task/etc.) sont passees en
## parametres plutot que stockees ici - Dwarf.gd garde la propriete de ses
## propres champs, cette classe ne fait que le calcul. Ca evite tout
## changement d'API externe : CharacterSheetUI.gd continue de lire
## dwarf.skill_levels/dwarf.force/etc. sans aucune modification.

const SkillDefs := preload("res://scripts/data/creatures/nains/caracteristiques/SkillDefinitions.gd")

const SKILL_BUDGET_PER_SKILL := 5      # budget total distribue = nb de competences * cette valeur
const SKILL_MAX_START_LEVEL := 10      # plafond du tirage aleatoire initial (l'xp peut aller au-dela ensuite)
const SKILL_XP_PER_TASK := 10.0        # xp gagnee a chaque tache terminee du bon type
const SKILL_XP_BASE := 20.0            # xp necessaire pour passer du niveau 0 au niveau 1
const SKILL_XP_PER_LEVEL := 10.0       # xp supplementaire requise par niveau deja atteint
const SKILL_WORK_SPEED_BONUS := 0.05   # par niveau : -5% de duree de travail
const SKILL_MIN_DURATION_FACTOR := 0.4 # la duree ne descend jamais sous 40% de la duree de base
const SKILL_BONUS_YIELD_PER_LEVEL := 0.05  # par niveau : +5% de chance de ressource bonus
const SKILL_BONUS_YIELD_MAX := 0.6         # plafond de la chance de bonus


## Genere les caracteristiques de base du nain (Sprint 12), retournees en
## Dictionary (force/agilite/constitution/intelligence/beaute/bonheur) -
## purement informatif pour l'instant, aucun effet sur le gameplay.
func generate_characteristics() -> Dictionary:
	return {
		"force": randi_range(1, 10),
		"agilite": randi_range(1, 10),
		"constitution": randi_range(1, 10),
		"intelligence": randi_range(1, 10),
		"beaute": randi_range(1, 10),
		"bonheur": randi_range(40, 80),
	}


## --- Competences (Sprint 18) ---

## Repartit un niveau de depart aleatoire par competence, a "budget" constant
## (total = nb de competences * SKILL_BUDGET_PER_SKILL) : un nain fort dans
## une competence le sera un peu moins dans les autres, plutot que d'avoir
## des nains generalistes forts partout. Retourne {"levels": Dictionary,
## "xp": Dictionary}, a assigner par l'appelant (skill_levels/skill_xp).
func generate_skills() -> Dictionary:
	var levels: Dictionary = {}
	var xp: Dictionary = {}
	var defs: Array = SkillDefs.SKILLS
	var count: int = defs.size()
	if count == 0:
		return {"levels": levels, "xp": xp}
	var budget: int = count * SKILL_BUDGET_PER_SKILL
	var values: Array = _distribute_skill_points(budget, count, SKILL_MAX_START_LEVEL)
	for i in range(count):
		var id: String = defs[i]["id"]
		levels[id] = values[i]
		xp[id] = 0.0
	return {"levels": levels, "xp": xp}


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
## (l'xp requise augmente a chaque niveau, voir SKILL_XP_BASE/SKILL_XP_PER_LEVEL).
## Mutate skill_levels/skill_xp EN PLACE (Dictionary passe par reference en
## GDScript) - l'appelant garde donc les memes objets qu'avant. dwarf_name
## uniquement pour le message de log (montee de niveau).
func gain_xp(skill_levels: Dictionary, skill_xp: Dictionary, skill_id: String, amount: float, dwarf_name: String) -> void:
	if skill_id == "" or not skill_levels.has(skill_id):
		return
	skill_xp[skill_id] += amount
	var guard: int = 0
	while skill_xp[skill_id] >= xp_needed_for_level(skill_levels[skill_id]) and guard < 100:
		skill_xp[skill_id] -= xp_needed_for_level(skill_levels[skill_id])
		skill_levels[skill_id] += 1
		print("%s : %s passe niveau %d" % [dwarf_name, SkillDefs.display_name(skill_id), skill_levels[skill_id]])
		guard += 1


func xp_needed_for_level(level: int) -> float:
	return SKILL_XP_BASE + float(level) * SKILL_XP_PER_LEVEL


## Duree de travail effective pour la tache en cours, reduite selon le
## niveau de la competence liee (voir SkillDefinitions.skill_for_task).
func compute_work_duration(skill_levels: Dictionary, current_task: Dictionary, base_work_duration: float) -> float:
	var skill_id: String = SkillDefs.skill_for_task(current_task.get("type", ""))
	if skill_id == "" or not skill_levels.has(skill_id):
		return base_work_duration
	var level: int = skill_levels[skill_id]
	var factor: float = max(1.0 - float(level) * SKILL_WORK_SPEED_BONUS, SKILL_MIN_DURATION_FACTOR)
	return base_work_duration * factor


## Tire au sort si la recolte donne une ressource bonus, avec une chance qui
## augmente avec le niveau de competence (plafonnee a SKILL_BONUS_YIELD_MAX).
func roll_bonus_yield(skill_levels: Dictionary, skill_id: String) -> bool:
	if skill_id == "" or not skill_levels.has(skill_id):
		return false
	var level: int = skill_levels[skill_id]
	var chance: float = min(float(level) * SKILL_BONUS_YIELD_PER_LEVEL, SKILL_BONUS_YIELD_MAX)
	return randf() < chance
