extends Node

var saved_map_position := Vector2.ZERO
var has_saved_map_position := false

func save_map_position(position: Vector2) -> void:
	saved_map_position = position
	has_saved_map_position = true

func consume_map_position() -> Vector2:
	if not has_saved_map_position:
		return Vector2.INF

	has_saved_map_position = false
	return saved_map_position
