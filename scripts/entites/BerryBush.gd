extends Node3D
## Sprint 8 : buisson a baies. Le nain venait manger ici directement quand il
## avait faim.
##
## Sprint 24quater : script INUTILISE - les buissons sont recoltes en
## inventaire via l'action "Cueillir" (comme les arbres fruitiers), et les
## nains mangent depuis l'inventaire (voir Dwarf.gd/_try_start_eating). La
## logique de recolte est directement portee par les metadonnees du noeud
## buisson (fruit_resource/fruits_left), construites dans BerryBushes.gd,
## exactement comme pour les arbres fruitiers (voir Forest.gd) - plus besoin
## d'un script dedie avec une methode eat(). Laisse en place (non nettoye,
## non re-attache a un noeud) pour tracer l'historique, voir le README.
