extends Node3D
## Script INUTILISE, non attache a un noeud dans le jeu. Les buissons sont
## recoltes en inventaire via l'action "Cueillir" (comme les arbres
## fruitiers), et les nains mangent depuis l'inventaire (voir
## Dwarf.gd/_try_start_eating), pas directement au buisson. La logique de
## recolte est portee par les metadonnees du noeud buisson
## (fruit_resource/fruits_left), construites dans BerryBushes.gd, exactement
## comme pour les arbres fruitiers (voir Forest.gd) - plus besoin d'un script
## dedie avec une methode eat(). Conserve tel quel dans le depot.
