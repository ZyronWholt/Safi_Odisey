extends Node
## Manager central de Supabase para Safi Odisey
## Centraliza autenticación y peticiones a la API

# ============================================
# CONFIGURACIÓN (cambia estos valores)
# ============================================
const SUPABASE_URL := "https://dvsjkciiactzvwtqjqgu.supabase.co"
const SUPABASE_ANON_KEY := "sb_publishable_gA90fmD_RwElkcO2bcjAjA_N16tGU7W"
const GOOGLE_OAUTH_REDIRECT_URI := "http://127.0.0.1:49152/oauth/callback"
const GOOGLE_OAUTH_TIMEOUT_MSEC := 300000

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
signal password_recovery_succeeded
signal password_recovery_failed(error_message: String)
signal register_succeeded(user_data: Dictionary)
signal register_failed(error_message: String)
signal google_registration_succeeded(user_data: Dictionary)
signal logged_out

var _google_oauth_server: TCPServer
var _google_oauth_peer: StreamPeerTCP
var _google_oauth_code_verifier := ""
var _google_oauth_deadline_msec := 0
var _google_oauth_request_buffer := PackedByteArray()
var _google_oauth_is_registration := false

# ============================================
# CICLO DE VIDA
# ============================================
func _ready() -> void:
	# La sesión debe iniciarse de nuevo cada vez que se ejecuta el juego.
	# Los tokens se mantienen únicamente durante esta ejecución.
	pass

func _process(_delta: float) -> void:
	if _google_oauth_server == null:
		return

	if Time.get_ticks_msec() >= _google_oauth_deadline_msec:
		_fail_google_login("Se agotó el tiempo de espera del inicio de sesión con Google.")
		return

	if _google_oauth_peer == null and _google_oauth_server.is_connection_available():
		_google_oauth_peer = _google_oauth_server.take_connection()

	if _google_oauth_peer == null:
		return

	var poll_error := _google_oauth_peer.poll()
	if poll_error != OK or _google_oauth_peer.get_status() == StreamPeerSocket.STATUS_ERROR:
		_fail_google_login("No se pudo recibir la respuesta del navegador.")
		return

	var available_bytes := _google_oauth_peer.get_available_bytes()
	if available_bytes <= 0:
		return
	if available_bytes > 8192:
		_fail_google_login("La respuesta de Google excede el tamaño permitido.")
		return

	var request_result: Array = _google_oauth_peer.get_data(available_bytes)
	if request_result[0] != OK:
		_fail_google_login("No se pudo leer la respuesta del navegador.")
		return

	_google_oauth_request_buffer.append_array(request_result[1])
	if _google_oauth_request_buffer.size() > 8192:
		_fail_google_login("La respuesta de Google excede el tamaño permitido.")
		return

	var request_text := _google_oauth_request_buffer.get_string_from_utf8()
	if not request_text.contains("\r\n\r\n"):
		return

	_handle_google_oauth_callback(request_text)

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

func login_with_google() -> void:
	_start_google_oauth(false)

func register_with_google() -> void:
	_start_google_oauth(true)

func _start_google_oauth(is_registration: bool) -> void:
	if _google_oauth_server != null:
		login_failed.emit("Ya hay un inicio de sesión con Google en curso.")
		return

	_google_oauth_is_registration = is_registration
	if is_registration:
		_clear_session_state()

	var crypto := Crypto.new()
	var verifier_bytes := crypto.generate_random_bytes(32)
	if verifier_bytes.size() != 32:
		login_failed.emit("No se pudo preparar el inicio seguro con Google.")
		return

	_google_oauth_code_verifier = _base64url_encode(verifier_bytes)
	var hash_context := HashingContext.new()
	var hash_error := hash_context.start(HashingContext.HASH_SHA256)
	if hash_error != OK:
		_fail_google_login("No se pudo preparar el inicio seguro con Google.")
		return
	hash_error = hash_context.update(_google_oauth_code_verifier.to_utf8_buffer())
	if hash_error != OK:
		_fail_google_login("No se pudo preparar el inicio seguro con Google.")
		return
	var code_challenge := _base64url_encode(hash_context.finish())

	_google_oauth_server = TCPServer.new()
	var error := _google_oauth_server.listen(49152, "127.0.0.1")
	if error != OK:
		_fail_google_login("No se pudo abrir el puerto local para completar Google OAuth (código %d)." % error)
		return

	_google_oauth_deadline_msec = Time.get_ticks_msec() + GOOGLE_OAUTH_TIMEOUT_MSEC
	var authorize_url := "%s/auth/v1/authorize?provider=google&redirect_to=%s&code_challenge=%s&code_challenge_method=s256" % [
		SUPABASE_URL,
		GOOGLE_OAUTH_REDIRECT_URI.uri_encode(),
		code_challenge.uri_encode()
	]
	error = OS.shell_open(authorize_url)
	if error != OK:
		_fail_google_login("No se pudo abrir el navegador para Google (código %d)." % error)

func _handle_google_oauth_callback(request_text: String) -> void:
	var request_line := request_text.get_slice("\r\n", 0)
	var request_target := request_line.get_slice(" ", 1)
	var callback_path := request_target.get_slice("?", 0)
	if callback_path != "/oauth/callback":
		_send_google_callback_page(false)
		_fail_google_login("La respuesta del navegador no corresponde al callback de Google.")
		return

	var oauth_error := _get_query_parameter(request_target, "error")
	if not oauth_error.is_empty():
		_send_google_callback_page(false)
		_fail_google_login("Google rechazó la autenticación: " + oauth_error)
		return

	var code := _get_query_parameter(request_target, "code")
	if code.is_empty():
		_send_google_callback_page(false)
		_fail_google_login("Google no devolvió un código de autorización.")
		return

	_send_google_callback_page(true)
	_close_google_oauth_listener()
	_exchange_google_oauth_code(code)

func _exchange_google_oauth_code(code: String) -> void:
	var http := _create_request()
	http.request_completed.connect(_on_google_oauth_token_completed.bind(http))
	var error := http.request(
		SUPABASE_URL + "/auth/v1/token?grant_type=pkce",
		_oauth_headers(),
		HTTPClient.METHOD_POST,
		JSON.stringify({
			"auth_code": code,
			"code_verifier": _google_oauth_code_verifier
		})
	)
	_google_oauth_code_verifier = ""

	if error != OK:
		http.queue_free()
		_fail_google_login("No se pudo intercambiar el código de Google con Supabase (código %d)." % error)

func _on_google_oauth_token_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	_google_oauth_deadline_msec = 0
	var registration_flow := _google_oauth_is_registration
	_google_oauth_is_registration = false

	if result != HTTPRequest.RESULT_SUCCESS:
		login_failed.emit(_get_network_error_message(result))
		return

	var response := _parse_json_object(body)
	if response_code < 200 or response_code >= 300:
		login_failed.emit(_get_error_message(response, "Supabase no pudo completar el inicio de sesión con Google."))
		return

	var user_value: Variant = response.get("user", {})
	if response.is_empty() or not response.has("access_token") or typeof(user_value) != TYPE_DICTIONARY:
		login_failed.emit("Supabase devolvió una respuesta inválida al iniciar sesión con Google.")
		return

	if registration_flow:
		_clear_session_state()
		google_registration_succeeded.emit(user_value)
		return

	_save_session(response)
	login_succeeded.emit(current_user)

func _send_google_callback_page(success: bool) -> void:
	if _google_oauth_peer == null:
		return

	var page := "Respuesta recibida. Vuelve al juego mientras termina la autenticación."
	if not success:
		page = "No se pudo completar la autenticación. Vuelve al juego para ver el error."
	var body := ("<!doctype html><html><meta charset=\"utf-8\"><title>Google OAuth</title><body><p>" + page + "</p></body></html>").to_utf8_buffer()
	var headers := "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nContent-Length: %d\r\n\r\n" % body.size()
	var response := headers.to_utf8_buffer()
	response.append_array(body)
	var error := _google_oauth_peer.put_data(response)
	if error != OK:
		push_error("No se pudo responder al callback OAuth local (código %d)." % error)
	_google_oauth_peer.disconnect_from_host()
	_google_oauth_peer = null

func _get_query_parameter(url: String, key: String) -> String:
	var query_start := url.find("?")
	if query_start < 0:
		return ""

	var query := url.substr(query_start + 1)
	for pair in query.split("&", false):
		var separator := pair.find("=")
		if separator < 0:
			continue
		if pair.substr(0, separator).uri_decode() == key:
			return pair.substr(separator + 1).uri_decode()
	return ""

func _base64url_encode(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").trim_suffix("=")

func _oauth_headers() -> PackedStringArray:
	return [
		"Content-Type: application/json",
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY
	]

func _close_google_oauth_listener() -> void:
	if _google_oauth_peer != null:
		_google_oauth_peer.disconnect_from_host()
		_google_oauth_peer = null
	if _google_oauth_server != null:
		_google_oauth_server.stop()
		_google_oauth_server = null
	_google_oauth_request_buffer.clear()

func _fail_google_login(message: String) -> void:
	_close_google_oauth_listener()
	_google_oauth_code_verifier = ""
	_google_oauth_deadline_msec = 0
	_google_oauth_is_registration = false
	login_failed.emit(message)

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

func recover_password(email: String) -> void:
	var http := _create_request()
	http.request_completed.connect(_on_password_recovery_completed.bind(http))

	var error := http.request(
		SUPABASE_URL + "/auth/v1/recover",
		_common_headers(),
		HTTPClient.METHOD_POST,
		JSON.stringify({"email": email})
	)

	if error != OK:
		password_recovery_failed.emit("No se pudo iniciar la conexión con Supabase (código %d)." % error)
		http.queue_free()

func _on_password_recovery_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		password_recovery_failed.emit(_get_network_error_message(result))
		return

	if response_code < 200 or response_code >= 300:
		var response := _parse_json_object(body)
		password_recovery_failed.emit(_get_error_message(response, "No se pudieron enviar las instrucciones de recuperación."))
		return

	password_recovery_succeeded.emit()

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

func _clear_session_state() -> void:
	access_token = ""
	refresh_token = ""
	current_user = {}
	is_logged_in = false

func _load_saved_session() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://sesion.cfg")
	if err == OK:
		access_token = config.get_value("sesion", "access_token", "")
		refresh_token = config.get_value("sesion", "refresh_token", "")
		if access_token != "":
			is_logged_in = true
			print("✅ Sesión restaurada desde archivo local.")