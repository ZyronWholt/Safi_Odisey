extends CharacterBody2D

var animated_sprite_2d: AnimatedSprite2D = null
var camera_2d: Camera2D = null
var speed: float = 115.0
var last_direction: StringName = &"Frontal"

func _ready() -> void:
	for child in get_children():
		if child is AnimatedSprite2D:
			animated_sprite_2d = child as AnimatedSprite2D
		elif child is Camera2D:
			camera_2d = child as Camera2D
	play_direction_animation()
	if is_instance_valid(camera_2d):
		camera_2d.enabled = true
		call_deferred("activate_camera")

func activate_camera() -> void:
	if is_instance_valid(camera_2d):
		camera_2d.enabled = true
		camera_2d.position = Vector2.ZERO
		camera_2d.make_current()
	configure_camera_limits()

func configure_camera_limits() -> void:
	if not is_instance_valid(camera_2d):
		return

	var bounds := Rect2()
	var has_bounds := false
	var tile_map_layers := get_tree().current_scene.find_children("*", "TileMapLayer", true, false)

	for node in tile_map_layers:
		var layer := node as TileMapLayer
		var used_rect := layer.get_used_rect()
		if used_rect.size == Vector2i.ZERO:
			continue

		var top_left := layer.to_global(layer.map_to_local(used_rect.position))
		var bottom_right := layer.to_global(layer.map_to_local(used_rect.end))
		var layer_bounds := Rect2(
			min(top_left.x, bottom_right.x),
			min(top_left.y, bottom_right.y),
			abs(bottom_right.x - top_left.x),
			abs(bottom_right.y - top_left.y)
		)

		if has_bounds:
			bounds = bounds.merge(layer_bounds)
		else:
			bounds = layer_bounds
			has_bounds = true

	if not has_bounds:
		return

	camera_2d.limit_left = floori(bounds.position.x)
	camera_2d.limit_top = floori(bounds.position.y)
	camera_2d.limit_right = ceili(bounds.end.x)
	camera_2d.limit_bottom = ceili(bounds.end.y)

func _physics_process(_delta: float) -> void:
	var input_direction = Input.get_vector("Izquierda", "Derecha", "Arriba", "Abajo")
	
	# Determinar dirección y mapear a nombres de animación
	if input_direction != Vector2.ZERO:
		if abs(input_direction.x) > abs(input_direction.y):
			# Movimiento horizontal
			if input_direction.x > 0:
				last_direction = "Lateral_1"  # Derecha
			else:
				last_direction = "Lateral_2"  # Izquierda
		else:
			# Movimiento vertical
			if input_direction.y > 0:
				last_direction = "Frontal"  # Abajo
			else:
				last_direction = "Espalda"  # Arriba
	
	if input_direction != Vector2.ZERO:
		play_direction_animation()
	elif is_instance_valid(animated_sprite_2d):
		animated_sprite_2d.stop()
			
	velocity = input_direction * speed
	move_and_slide()

func play_direction_animation() -> void:
	if not is_instance_valid(animated_sprite_2d):
		return

	var sprite_frames: SpriteFrames = animated_sprite_2d.sprite_frames
	if sprite_frames == null or not sprite_frames.has_animation(last_direction):
		return

	if animated_sprite_2d.animation != last_direction:
		animated_sprite_2d.play(last_direction)
	elif not animated_sprite_2d.is_playing():
		animated_sprite_2d.play(last_direction)
