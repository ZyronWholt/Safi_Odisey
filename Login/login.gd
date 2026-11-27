extends Control

@onready var input_email: LineEdit = $input_email
@onready var input_password: LineEdit = $input_password
@onready var lbl_message: Label = $lbl_message
@onready var btn_login: Button = $btn_login
@onready var btn_forgot_password: Button = $btn_forgot_password

const MAP_SCENE_PATH := "res://Mapa_TESH/mapa_tesh.tscn"

func _ready() -> void:
	SupabaseManager.login_succeeded.connect(_on_login_ok)
	SupabaseManager.login_failed.connect(_on_login_fail)
	SupabaseManager.password_recovery_succeeded.connect(_on_password_recovery_succeeded)
	SupabaseManager.password_recovery_failed.connect(_on_password_recovery_failed)

func _on_login_pressed() -> void:
	var email := input_email.text.strip_edges()
	var password := input_password.text

	if email.is_empty() or password.is_empty():
		_show_error("Completa todos los campos.")
		return

	if not email.contains("@") or not email.contains("."):
		_show_error("Ingresa el correo usado al crear tu cuenta.")
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
		_show_error("Ingresa el correo usado al crear tu cuenta.")
		return
	if not email.contains("@") or not email.contains("."):
		_show_error("Ingresa un correo válido para recuperar tu cuenta.")
		return

	btn_forgot_password.disabled = true
	lbl_message.text = "Enviando instrucciones de recuperación..."
	lbl_message.modulate = Color.YELLOW
	SupabaseManager.recover_password(email)

func _on_password_recovery_succeeded() -> void:
	btn_forgot_password.disabled = false
	lbl_message.text = "Si la cuenta existe, recibirás instrucciones en tu correo."
	lbl_message.modulate = Color.GREEN

func _on_password_recovery_failed(error_msg: String) -> void:
	btn_forgot_password.disabled = false
	_show_error(error_msg)

func _on_google_login_pressed() -> void:
	lbl_message.text = "Continuando con Google en el navegador..."
	lbl_message.modulate = Color.YELLOW
	SupabaseManager.login_with_google()