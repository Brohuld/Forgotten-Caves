extends CanvasLayer
## Sprint 9 : icone du nain en haut de l'ecran, cliquable, qui ouvre une
## fiche de personnage basique (PV factice, Faim, Energie, tache en cours).

@onready var dwarf: Node3D = %Dwarf
@onready var icon_button: Button = $DwarfIcon
@onready var panel: Panel = $SheetPanel
@onready var pv_bar: ProgressBar = $SheetPanel/VBox/PVBar
@onready var hunger_bar: ProgressBar = $SheetPanel/VBox/HungerBar
@onready var energy_bar: ProgressBar = $SheetPanel/VBox/EnergyBar
@onready var task_label: Label = $SheetPanel/VBox/TaskLabel


func _ready() -> void:
	icon_button.icon = _make_circle_icon(Color(0.8, 0.6, 0.4), 40)
	icon_button.expand_icon = true
	icon_button.pressed.connect(_on_icon_pressed)
	panel.visible = false

	pv_bar.max_value = 100
	pv_bar.value = 100
	hunger_bar.max_value = dwarf.hunger_max
	energy_bar.max_value = dwarf.energy_max


func _process(_delta: float) -> void:
	if not panel.visible:
		return
	hunger_bar.value = dwarf.hunger
	energy_bar.value = dwarf.energy
	task_label.text = "Tache en cours : %s" % _task_description()


func _task_description() -> String:
	if dwarf.is_working:
		return String(dwarf.current_task.get("type", "?")).capitalize()
	elif dwarf.is_resting:
		return "Repos"
	elif dwarf.is_eating:
		return "Manger"
	elif dwarf.is_seeking_food:
		return "Va manger"
	elif not dwarf.current_task.is_empty():
		return String(dwarf.current_task.get("type", "?")).capitalize()
	return "Errance"


func _on_icon_pressed() -> void:
	panel.visible = not panel.visible


## Genere une icone circulaire coloree sans avoir besoin d'un fichier image
func _make_circle_icon(color: Color, size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := size / 2.0
	var radius := size / 2.0 - 2.0
	for y in range(size):
		for x in range(size):
			var dx := x - center
			var dy := y - center
			if dx * dx + dy * dy <= radius * radius:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)
