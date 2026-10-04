class_name RegistryList
extends Resource
## A list of definition resources (games, items, minigames, maps, modes). The Registry autoload
## indexes each list by the entries' `id`. New content is added here, never in code.

@export var entries: Array[Resource] = []
