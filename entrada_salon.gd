extends Node2D

@onready var prompt: Label = $InteraccionSalon/CanvasLayer/Label

var player_inside := false

func _ready() -> void:
	prompt.visible = false
	$InteraccionSalon.body_entered.connect(_on_interaccion_salon_body_entered)
	$InteraccionSalon.body_exited.connect(_on_interaccion_salon_body_exited)
	_restore_map_position()

func _restore_map_position() -> void:
	var map_position := EstadoJugador.consume_map_position()
	if not map_position.is_finite():
		return

	var player := get_node_or_null("Objetos_YSort/Jugador") as CharacterBody2D
	if player == null:
		push_error("No se encontró el jugador para restaurar su posición en el mapa.")
		return

	player.global_position = map_position

func _unhandled_input(event: InputEvent) -> void:
	if player_inside and event.is_action_pressed("Entrar"):
		var player := get_node_or_null("Objetos_YSort/Jugador") as CharacterBody2D
		if player == null:
			push_error("No se encontró el jugador para guardar su posición antes de entrar al salón.")
			return

		EstadoJugador.save_map_position(player.global_position)
		get_tree().change_scene_to_file("res://salón_isc.tscn")

func _on_interaccion_salon_body_entered(body: Node2D) -> void:
	if body.name == "Jugador":
		player_inside = true
		prompt.visible = true

func _on_interaccion_salon_body_exited(body: Node2D) -> void:
	if body.name == "Jugador":
		player_inside = false
		prompt.visible = false
