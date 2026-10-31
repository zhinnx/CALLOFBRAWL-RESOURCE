## CALLOFBRAWL — tiny bootstrap scene.
##
## The project's main scene. It forwards straight to the main menu (so a future
## splash/loading screen can be added without touching project.godot) and keeps the
## mouse captured on desktop builds.
extends Node


func _ready() -> void:
	if not DisplayServer.get_name() == "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# defer so the tree is fully initialised before the first scene swap
	get_tree().change_scene_to_file.call_deferred("res://scenes/menus/main_menu.tscn")
