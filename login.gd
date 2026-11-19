extends Control

func _on_login_pressed() -> void:
	get_tree().change_scene_to_file("res://mapa_tesh.tscn")

func _on_create_account_pressed() -> void:
	get_tree().change_scene_to_file("res://crear_cuenta.tscn")
