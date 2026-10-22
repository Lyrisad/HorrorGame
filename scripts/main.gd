extends Node
## Scène racine : sert de conteneur aux niveaux. Toute la logique est dans l'autoload `Game`.


func _ready() -> void:
	Game.boot(self)
