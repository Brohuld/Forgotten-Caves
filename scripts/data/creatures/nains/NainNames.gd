extends RefCounted
## 2026-07-02 : table centrale des noms de nains, tires au hasard a la
## creation de chaque nain (voir Dwarf.gd/_ready -> _generate_name).
##
## FIRST_NAMES : prenoms puises dans le "Dvergatal" (catalogue des nains),
## une liste de noms attestee dans l'Edda poetique (Voluspa, texte du domaine
## public, ~13e siecle) - c'est justement la source dans laquelle Tolkien
## lui-meme a puise la plupart des noms de ses nains (Thorin, Dvalin, Fili,
## Kili, Bombur, etc. en sont directement issus). Utiliser cette liste donne
## le style "nain classique" demande sans reprendre de noms de personnages
## d'une oeuvre protegee. Completee par des prenoms feminins authentiques du
## vieux norrois (themes bataille/nature, coherents avec la sonorite du
## Dvergatal), pour un tirage mixte.
##
## SURNAMES : noms de clan inventes (pas de source externe), sur le modele
## classique "adjectif/matiere + trait" utilise dans la plupart des fictions
## de nains (forge, pierre, barbe, metal).
##
## Pour ajouter des noms : completer un des deux tableaux ci-dessous, aucune
## autre modification necessaire.

const FIRST_NAMES := [
	# Dvergatal (Voluspa / Edda poetique, domaine public)
	"Thorin", "Durin", "Dvalin", "Bifur", "Bofur", "Bombur", "Dori", "Nori",
	"Ori", "Fili", "Kili", "Gloi", "Thrain", "Thror", "Frosti", "Fundin",
	"Ginnar", "Grimr", "Har", "Hepti", "Heri", "Jaki", "Jari", "Litr",
	"Ljomi", "Lofar", "Mondull", "Munin", "Naefr", "Rekkr", "Skirfir", "Uni",
	"Vitr", "Vili", "Yngvi", "Andvari", "Sindri", "Regin", "Alvis",
	"Draupnir", "Eitri", "Brokkr", "Dain", "Nyi", "Nidi", "Billing",
	"Farli", "Frar", "Fjalar", "Galar",
	# Prenoms feminins vieux norrois authentiques (themes bataille/nature)
	"Brynhild", "Gunnhild", "Ragnhild", "Sigrid", "Astrid", "Ingrid",
	"Thora", "Solveig", "Unnr", "Aud", "Drifa", "Liv", "Oda", "Hjordis",
	"Gerd", "Svanhild", "Thordis", "Hallgerd", "Vigdis", "Bergthora",
]

const SURNAMES := [
	"Barbe-de-Fer", "Barbe-Grise", "Barbe-Rousse", "Barbe-Tressee",
	"Barbe-Blanche", "Barbe-Doree",
	"Poing-de-Granit", "Poing-de-Fer",
	"Marteau-Noir", "Marteau-Rouge", "Marteau-de-Bronze",
	"Forge-Ancienne", "Forge-Vivante", "Forge-Rouge",
	"Coeur-de-Pierre", "Hache-Vive", "Hache-Longue",
	"Puits-Profond", "Puits-d'Ombre",
	"Veine-d'Or", "Veine-de-Cuivre",
	"Pierre-Grise", "Roc-Solide", "Roche-Ancienne",
	"Bouclier-Sur", "Bouclier-de-Chene",
	"Cave-Profonde", "Montagne-Grise",
	"Enclume-d'Argent", "Granit-Noir", "Filon-d'Argent", "Pic-Acere",
]


## Tire un nom complet aleatoire "Prenom Nom-de-clan".
## 2026-07-06 (revue de code, paquet A) : flux GameRandom dedie "nains_noms"
## au lieu de randi() global - voir GameRandom.gd.
static func random_name() -> String:
	var rng: RandomNumberGenerator = GameRandom.get_rng("nains_noms")
	var first: String = FIRST_NAMES[rng.randi() % FIRST_NAMES.size()]
	var last: String = SURNAMES[rng.randi() % SURNAMES.size()]
	return "%s %s" % [first, last]
