extends CharacterBody2D

var animated_sprite_2d: AnimatedSprite2D
var speed: float = 115.0
var last_direction: StringName = &"Frontal"

func _ready() -> void:
	animated_sprite_2d = get_node_or_null("AnimatedSprite2D")

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
	
	# Reproducir animación correspondiente
	if is_instance_valid(animated_sprite_2d):
		if input_direction != Vector2.ZERO:
			if animated_sprite_2d.animation != last_direction:
				animated_sprite_2d.play(last_direction)
		else:
			# Animación idle cuando no hay movimiento
			animated_sprite_2d.stop()
			
	velocity = input_direction * speed
	move_and_slide()
