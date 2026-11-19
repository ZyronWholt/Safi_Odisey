extends Node2D

@onready var prompt: Label = $InteraccionSalon/CanvasLayer/Label

var player_inside := false

func _ready() -> void:
	prompt.visible = false
	$InteraccionSalon.body_entered.connect(_on_interaccion_salon_body_entered)
	$InteraccionSalon.body_exited.connect(_on_interaccion_salon_body_exited)

func _unhandled_input(event: InputEvent) -> void:
	if player_inside and event.is_action_pressed("Entrar"):
		get_tree().change_scene_to_file("res://mapa_tesh.tscn")

func _on_interaccion_salon_body_entered(body: Node2D) -> void:
	if body.name == "Jugador":
		player_inside = true
		prompt.visible = true

func _on_interaccion_salon_body_exited(body: Node2D) -> void:
	if body.name == "Jugador":
		player_inside = false
		prompt.visible = false
