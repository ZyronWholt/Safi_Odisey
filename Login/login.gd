extends Control

@onready var input_email: LineEdit = $Panel/Contenido/input_email
@onready var input_password: LineEdit = $Panel/Contenido/input_password
@onready var lbl_message: Label = $Panel/Contenido/lbl_message
@onready var btn_login: Button = $Panel/Contenido/btn_login

const MAP_SCENE_PATH := "res://Mapa_TESH/mapa_tesh.tscn"

func _ready() -> void:
	SupabaseManager.login_succeeded.connect(_on_login_ok)
	SupabaseManager.login_failed.connect(_on_login_fail)

func _on_login_pressed() -> void:
	var email := input_email.text.strip_edges()
	var password := input_password.text

	if email.is_empty() or password.is_empty():
		_show_error("Completa todos los campos.")
		return

	if not email.contains("@") or not email.contains("."):
		_show_error("Ingresa un correo electrónico válido.")
		return

	btn_login.disabled = true
	lbl_message.text = "Iniciando sesión..."
	lbl_message.modulate = Color.YELLOW
	SupabaseManager.login(email, password)

func _on_login_ok(user_data: Dictionary) -> void:
	btn_login.disabled = false
	lbl_message.text = "¡Bienvenido!"
	lbl_message.modulate = Color.GREEN
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file(MAP_SCENE_PATH)

func _on_login_fail(error_msg: String) -> void:
	btn_login.disabled = false
	var message := error_msg.strip_edges()
	if message.is_empty():
		message = "No se pudo iniciar sesión. Revisa tu conexión."
	_show_error(message)

func _show_error(message: String) -> void:
	lbl_message.text = message
	lbl_message.modulate = Color.RED

func _on_go_to_register_pressed() -> void:
	get_tree().change_scene_to_file("res://Login/crear_cuenta.tscn")

func _on_forgot_password_pressed() -> void:
	var email := input_email.text.strip_edges()
	if email.is_empty():
		_show_error("Ingresa tu correo para recuperar la contraseña.")
		return
	lbl_message.text = "Recuperación de contraseña no configurada."
	lbl_message.modulate = Color.YELLOW

func _on_google_login_pressed() -> void:
	lbl_message.text = "Inicio de sesión con Google no configurado."
	lbl_message.modulate = Color.YELLOW