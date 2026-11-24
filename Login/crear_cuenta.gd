extends Control

@onready var input_username: LineEdit = $Panel/Contenido/input_username
@onready var input_email: LineEdit = $Panel/Contenido/input_email
@onready var input_password: LineEdit = $Panel/Contenido/input_password
@onready var input_confirm_password: LineEdit = $Panel/Contenido/input_confirm_password
@onready var lbl_message: Label = $Panel/Contenido/lbl_message
@onready var btn_register: Button = $Panel/Contenido/btn_register

const MAP_SCENE_PATH := "res://Mapa_TESH/mapa_tesh.tscn"

func _ready() -> void:
	SupabaseManager.register_succeeded.connect(_on_register_succeeded)
	SupabaseManager.register_failed.connect(_on_register_failed)

func _on_register_pressed() -> void:
	var username := input_username.text.strip_edges()
	var email := input_email.text.strip_edges()
	var password := input_password.text
	var confirm_password := input_confirm_password.text

	if username.is_empty() or email.is_empty() or password.is_empty() or confirm_password.is_empty():
		_show_error("Todos los campos son obligatorios.")
		return

	if not email.contains("@") or not email.contains("."):
		_show_error("Ingresa un correo electrónico válido.")
		return

	if password.length() < 6:
		_show_error("La contraseña debe tener al menos 6 caracteres.")
		return

	if password != confirm_password:
		_show_error("Las contraseñas no coinciden.")
		return

	btn_register.disabled = true
	lbl_message.text = "Creando cuenta..."
	lbl_message.modulate = Color.YELLOW
	SupabaseManager.register(email, password, username)

func _on_register_succeeded(user_data: Dictionary) -> void:
	btn_register.disabled = false

	if user_data.get("pending_confirmation", false):
		lbl_message.text = "Cuenta creada. Revisa tu correo para confirmar el registro."
	else:
		lbl_message.text = "Cuenta creada correctamente."

	lbl_message.modulate = Color.GREEN

func _on_register_failed(error_message: String) -> void:
	btn_register.disabled = false
	var message := error_message.strip_edges()
	if message.is_empty():
		message = "No se pudo completar el registro. Revisa tu conexión."
	_show_error(message)

func _show_error(message: String) -> void:
	lbl_message.text = message
	lbl_message.modulate = Color.RED

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Login/login.tscn")
