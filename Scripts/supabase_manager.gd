extends Node
## Manager central de Supabase para Safi Odisey
## Centraliza autenticación y peticiones a la API

# ============================================
# CONFIGURACIÓN (cambia estos valores)
# ============================================
const SUPABASE_URL := "https://dvsjkciiactzvwtqjqgu.supabase.co"
const SUPABASE_ANON_KEY := "sb_publishable_gA90fmD_RwElkcO2bcjAjA_N16tGU7W"

# ============================================
# ESTADO DE SESIÓN
# ============================================
var access_token: String = ""
var refresh_token: String = ""
var current_user: Dictionary = {}
var is_logged_in: bool = false

# ============================================
# SEÑALES (para que otras escenas escuchen)
# ============================================
signal login_succeeded(user_data: Dictionary)
signal login_failed(error_message: String)
signal register_succeeded(user_data: Dictionary)
signal register_failed(error_message: String)
signal logged_out

# ============================================
# CICLO DE VIDA
# ============================================
func _ready() -> void:
	# La sesión debe iniciarse de nuevo cada vez que se ejecuta el juego.
	# Los tokens se mantienen únicamente durante esta ejecución.
	pass

# ============================================
# AUTENTICACIÓN - REGISTRO
# ============================================
func register(email: String, password: String, username: String) -> void:
	var metadata := {
		"data": {
			"username": username
		}
	}
	
	var body := {
		"email": email,
		"password": password,
		"data": metadata["data"]
	}
	
	var http := _create_request()
	http.request_completed.connect(_on_register_completed.bind(http))
	
	var error := http.request(
		SUPABASE_URL + "/auth/v1/signup",
		_common_headers(),
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	
	if error != OK:
		register_failed.emit("No se pudo iniciar la conexión con Supabase (código %d)." % error)
		http.queue_free()

func _on_register_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		register_failed.emit(_get_network_error_message(result))
		return
	
	var response := _parse_json_object(body)

	if response_code < 200 or response_code >= 300:
		var msg: String = _get_error_message(response, "Error al registrar. Verifica los datos.")
		register_failed.emit(msg)
		return

	if response.is_empty():
		register_failed.emit("El servidor devolvió una respuesta inválida al registrar.")
		return
	
	# Si Supabase tiene confirmación de email desactivada, viene el token
	if response.has("access_token"):
		_save_session(response)
		register_succeeded.emit(response.get("user", {}))
	else:
		# Confirmación de email activada
		register_succeeded.emit({"pending_confirmation": true})

# ============================================
# AUTENTICACIÓN - LOGIN
# ============================================
func login(email: String, password: String) -> void:
	var body := {
		"email": email,
		"password": password
	}
	
	var http := _create_request()
	http.request_completed.connect(_on_login_completed.bind(http))
	
	var error := http.request(
		SUPABASE_URL + "/auth/v1/token?grant_type=password",
		_common_headers(),
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	
	if error != OK:
		login_failed.emit("No se pudo iniciar la conexión con Supabase (código %d)." % error)
		http.queue_free()

func _on_login_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		login_failed.emit(_get_network_error_message(result))
		return

	var response := _parse_json_object(body)
	
	if response_code < 200 or response_code >= 300:
		var msg: String = _get_error_message(response, "Credenciales incorrectas.")
		login_failed.emit(msg)
		return

	if response.is_empty() or not response.has("access_token"):
		login_failed.emit("El servidor devolvió una respuesta inválida al iniciar sesión.")
		return
	
	_save_session(response)
	login_succeeded.emit(current_user)

# ============================================
# LOGOUT
# ============================================
func logout() -> void:
	access_token = ""
	refresh_token = ""
	current_user = {}
	is_logged_in = false
	
	var config := ConfigFile.new()
	config.clear()
	config.save("user://sesion.cfg")
	
	logged_out.emit()

# ============================================
# PETICIONES A LA BASE DE DATOS (ejemplos)
# ============================================
func get_current_profile() -> void:
	var http := _create_request()
	http.request_completed.connect(_on_profile_received.bind(http))
	
	http.request(
		SUPABASE_URL + "/rest/v1/profiles?select=*",
		_auth_headers(),
		HTTPClient.METHOD_GET
	)

func _on_profile_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	
	if response_code == 200:
		var profiles: Array = JSON.parse_string(body.get_string_from_utf8())
		if profiles.size() > 0:
			print("Perfil cargado: ", profiles[0])
	else:
		print("Error al cargar perfil: ", response_code)

# ============================================
# UTILIDADES INTERNAS
# ============================================
func _create_request() -> HTTPRequest:
	var http := HTTPRequest.new()
	add_child(http)
	return http

func _common_headers() -> PackedStringArray:
	return [
		"Content-Type: application/json",
		"apikey: " + SUPABASE_ANON_KEY
	]

func _get_error_message(response: Dictionary, fallback: String) -> String:
	var keys: Array[String] = ["message", "error_description", "msg", "error"]

	for key: String in keys:
		var value: Variant = response.get(key)
		if typeof(value) == TYPE_STRING:
			var text: String = value
			if not text.is_empty():
				return text

	return fallback

func _parse_json_object(body: PackedByteArray) -> Dictionary:
	var body_text := body.get_string_from_utf8().strip_edges()
	if body_text.is_empty():
		return {}

	var json := JSON.new()
	if json.parse(body_text) != OK:
		return {}

	return json.data if json.data is Dictionary else {}

func _get_network_error_message(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "No se encontró el servidor de Supabase. Verifica SUPABASE_URL y tu DNS."
		HTTPRequest.RESULT_CANT_CONNECT:
			return "No se pudo conectar con Supabase. Revisa tu conexión o si el proyecto está activo."
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "No se pudo establecer una conexión segura con Supabase (TLS)."
		HTTPRequest.RESULT_TIMEOUT:
			return "La conexión con Supabase tardó demasiado. Revisa tu conexión a internet."
		HTTPRequest.RESULT_NO_RESPONSE:
			return "Supabase no respondió. Verifica que el proyecto esté activo."
		_:
			return "No se pudo conectar con Supabase (código HTTPRequest: %d)." % result

func _auth_headers() -> PackedStringArray:
	return [
		"Content-Type: application/json",
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + access_token
	]

func _save_session(response: Dictionary) -> void:
	access_token = response.get("access_token", "")
	refresh_token = response.get("refresh_token", "")
	current_user = response.get("user", {})
	is_logged_in = true
	
	# Guardar sesión localmente
	var config := ConfigFile.new()
	config.set_value("sesion", "access_token", access_token)
	config.set_value("sesion", "refresh_token", refresh_token)
	config.save("user://sesion.cfg")

func _load_saved_session() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://sesion.cfg")
	if err == OK:
		access_token = config.get_value("sesion", "access_token", "")
		refresh_token = config.get_value("sesion", "refresh_token", "")
		if access_token != "":
			is_logged_in = true
			print("✅ Sesión restaurada desde archivo local.")