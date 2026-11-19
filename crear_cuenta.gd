extends Control

func _on_create_pressed() -> void:
	get_tree().change_scene_to_file("res://mapa_tesh.tscn")

func _on_google_pressed() -> void:
	get_tree().change_scene_to_file("res://mapa_tesh.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://login.tscn")
