class_name RedP2P
extends Node
## Autoload «Red»: conexión P2P entre dos jugadores con WebRTC.
##
## No hay servidor de juego ni de señalización. La oferta/respuesta SDP y los
## candidatos ICE se intercambian copiando y pegando un «código»: un JSON
## {v, tipo, sdp, candidatos} codificado en base64.
##
## La interfaz es la misma en todas las plataformas. Lo único que cambia es quién
## implementa WebRTCPeerConnection por debajo:
##   * Web (OS.has_feature("web")): la implementación del navegador (RTCPeerConnection),
##     integrada en las plantillas web de Godot.
##   * Android / escritorio: el addon GDExtension «webrtc-native» en addons/webrtc/.
##     Si falta, initialize() devuelve error y lo explicamos al jugador.
##
## Negociación con señalización manual:
##
##   ANFITRIÓN                                      INVITADO
##   crear_partida()
##     create_data_channel(negotiated, id=1)
##     create_offer() ─► session_description_created("offer")
##     set_local_description("offer")
##     ... recolección de candidatos ICE ...
##     get_gathering_state() == COMPLETE ─► código A
##                 ── el jugador copia A y se lo envía ──►
##                                                  unirse(A)
##                                                    create_data_channel(negotiated, id=1)
##                                                    set_remote_description("offer")
##                                                    add_ice_candidate() × N
##                                                    ─► session_description_created("answer")
##                                                    set_local_description("answer")
##                                                    ... recolección de candidatos ...
##                                                    COMPLETE ─► código B
##                 ◄── el invitado copia B y se lo envía ──
##   aceptar_respuesta(B)
##     set_remote_description("answer")
##     add_ice_candidate() × N
##   ... ICE prueba los pares de candidatos ... el canal pasa a STATE_OPEN ─► «Conectado»
##
## Al ser un canal NEGOCIADO (mismo id en ambos lados) nadie espera la señal
## data_channel_received: los dos crean el canal antes de la oferta/respuesta.

signal estado_cambiado(nuevo_estado: Estado)
## El código local (oferta o respuesta) está listo para copiarse.
signal codigo_generado(codigo: String)
signal conectado
signal desconectado(motivo: String)
## Error recuperable (p. ej. código mal pegado): se puede reintentar.
signal aviso(mensaje: String)

enum Estado {
	INACTIVO,
	GENERANDO_CODIGO,
	ESPERANDO_RIVAL,
	CONECTANDO,
	CONECTADO,
	DESCONECTADO,
	ERROR,
}

const SERVIDOR_STUN := "stun:stun.l.google.com:19302"
const ID_CANAL_NEGOCIADO := 1
const ETIQUETA_CANAL := "cocodrilo"
const VERSION_CODIGO := 1
const TIPO_OFERTA := "offer"
const TIPO_RESPUESTA := "answer"

## La recolección termina cuando el estado pasa a GATHERING_STATE_COMPLETE.
## Este límite NO es una espera fija: solo evita quedarse colgado para siempre
## si una red rara nunca completa la recolección (se usa lo recolectado hasta ahí).
const TIEMPO_MAXIMO_RECOLECCION_S := 25.0
## Frames de poll() extra tras COMPLETE para vaciar candidatos que el hilo nativo
## haya encolado justo antes del cambio de estado.
const FRAMES_DRENAJE_CANDIDATOS := 2
const TIEMPO_MAXIMO_CONEXION_S := 40.0
## ICE puede pasar por «disconnected» y recuperarse solo; damos un margen.
const TIEMPO_GRACIA_DESCONEXION_S := 6.0
const INTERVALO_LATIDO_S := 2.0
const TIEMPO_SIN_NOTICIAS_S := 20.0
## Evita que un frame enorme (app en segundo plano) dispare los temporizadores.
const DELTA_MAXIMO_S := 0.25

const MENSAJE_LATIDO := "_latido"
const MENSAJE_HOLA := "_hola"

const TEXTO_SIN_ADDON := "Falta el addon webrtc-native.\n" \
	+ "Ejecuta tools/instalar_webrtc.sh (ver README) y vuelve a exportar."
const TEXTO_TURN := "No se pudo conectar. Algunas redes móviles bloquean las conexiones P2P " \
	+ "directas y necesitarían un servidor TURN. Prueba con Wi-Fi."

var es_anfitrion := false
var estado: Estado = Estado.INACTIVO
## Marcador de la sesión actual (se reinicia al cerrar la conexión).
var sesion := {"ronda": 0, "victorias": 0, "derrotas": 0}

var _peer: WebRTCPeerConnection = null
var _canal: WebRTCDataChannel = null
var _tipo_local := ""
var _sdp_local := ""
var _candidatos_locales: Array[Dictionary] = []
var _recolectando := false
var _tiempo_recoleccion := 0.0
var _frames_drenaje := 0
var _tiempo_conectando := 0.0
var _tiempo_desconectado := 0.0
var _tiempo_latido := 0.0
var _tiempo_sin_noticias := 0.0
## Quién recibe los mensajes de juego. Mientras no haya receptor (p. ej. durante
## una transición de escena) los mensajes se guardan en la cola y no se pierden.
var _receptor := Callable()
var _cola: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what: int) -> void:
	# Al volver del segundo plano no contamos el tiempo que la app estuvo pausada.
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_tiempo_sin_noticias = 0.0
		_tiempo_desconectado = 0.0


# --- API pública -------------------------------------------------------------------

func nombre_implementacion() -> String:
	if OS.has_feature("web"):
		return "WebRTC del navegador"
	return "addon webrtc-native"


## Estados internos de WebRTC en texto (para depurar y para las pruebas).
func diagnostico() -> String:
	if _peer == null:
		return "sin conexión (estado %d)" % estado
	return "estado=%d conexion=%d recoleccion=%d senalizacion=%d canal=%d candidatos=%d" % [
		estado, _peer.get_connection_state(), _peer.get_gathering_state(), _peer.get_signaling_state(),
		_canal.get_ready_state() if _canal != null else -1, _candidatos_locales.size()]


func esta_conectado() -> bool:
	return estado == Estado.CONECTADO and _canal != null \
		and _canal.get_ready_state() == WebRTCDataChannel.STATE_OPEN


## ANFITRIÓN: crea la conexión y genera la oferta. El código llega por codigo_generado.
func crear_partida() -> bool:
	es_anfitrion = true
	if not _crear_conexion():
		return false
	_cambiar_estado(Estado.GENERANDO_CODIGO)
	var error := _peer.create_offer()
	if error != OK:
		_fallar("No se pudo crear la oferta WebRTC (error %d)." % error)
		return false
	return true


## INVITADO: aplica la oferta del anfitrión y genera la respuesta.
func unirse(codigo_anfitrion: String) -> bool:
	var datos := decodificar_codigo(codigo_anfitrion)
	if datos.is_empty() or datos["tipo"] != TIPO_OFERTA:
		aviso.emit("Ese código no es válido. Copia el código del anfitrión completo.")
		return false
	es_anfitrion = false
	if not _crear_conexion():
		return false
	_cambiar_estado(Estado.GENERANDO_CODIGO)
	# Al recibir una OFERTA, Godot crea la RESPUESTA automáticamente y la entrega
	# por session_description_created("answer", sdp).
	var error := _peer.set_remote_description(TIPO_OFERTA, datos["sdp"])
	if error != OK:
		_fallar("El código del anfitrión no se pudo aplicar (error %d)." % error)
		return false
	_agregar_candidatos_remotos(datos["candidatos"])
	return true


## ANFITRIÓN: aplica la respuesta del invitado. A partir de aquí ICE conecta solo.
func aceptar_respuesta(codigo_invitado: String) -> bool:
	if not es_anfitrion or _peer == null or estado != Estado.ESPERANDO_RIVAL:
		aviso.emit("Primero espera a que se genere tu código." if estado == Estado.GENERANDO_CODIGO
			else "La respuesta ya se aplicó; espera a que conecte.")
		return false
	var datos := decodificar_codigo(codigo_invitado)
	if datos.is_empty() or datos["tipo"] != TIPO_RESPUESTA:
		aviso.emit("Esa respuesta no es válida. Pega el código que generó tu rival.")
		return false
	var error := _peer.set_remote_description(TIPO_RESPUESTA, datos["sdp"])
	if error != OK:
		_fallar("La respuesta del rival no se pudo aplicar (error %d)." % error)
		return false
	_agregar_candidatos_remotos(datos["candidatos"])
	_cambiar_estado(Estado.CONECTANDO)
	return true


## Envía un mensaje de juego (Dictionary → JSON). Devuelve false si no hay conexión.
func enviar(mensaje: Dictionary) -> bool:
	if not esta_conectado():
		return false
	return _enviar_crudo(mensaje)


## Define quién recibe los mensajes. Callable() vacío = encolar hasta nuevo aviso.
func establecer_receptor(receptor: Callable) -> void:
	_receptor = receptor


func cerrar() -> void:
	_liberar_conexion()
	es_anfitrion = false
	sesion = {"ronda": 0, "victorias": 0, "derrotas": 0}
	_cola.clear()
	_cambiar_estado(Estado.INACTIVO)


# --- Código de conexión (JSON + base64) ----------------------------------------------

static func codificar_codigo(tipo: String, sdp: String, candidatos: Array) -> String:
	var datos := {"v": VERSION_CODIGO, "tipo": tipo, "sdp": sdp, "candidatos": candidatos}
	return Marshalls.utf8_to_base64(JSON.stringify(datos))


## Devuelve {} si el código no es válido. Normaliza los índices a int
## porque JSON los entrega como float.
static func decodificar_codigo(codigo: String) -> Dictionary:
	var limpio := limpiar_codigo(codigo)
	if limpio.length() < 8 or limpio.length() % 4 != 0:
		return {}
	var bytes := Marshalls.base64_to_raw(limpio)
	if bytes.is_empty():
		return {}
	var datos: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(datos) != TYPE_DICTIONARY:
		return {}
	var tipo: Variant = datos.get("tipo")
	var sdp: Variant = datos.get("sdp")
	var candidatos: Variant = datos.get("candidatos", [])
	if typeof(tipo) != TYPE_STRING or (tipo != TIPO_OFERTA and tipo != TIPO_RESPUESTA):
		return {}
	if typeof(sdp) != TYPE_STRING or (sdp as String).is_empty():
		return {}
	if typeof(candidatos) != TYPE_ARRAY:
		return {}
	var normalizados: Array[Dictionary] = []
	for candidato: Variant in candidatos:
		if typeof(candidato) != TYPE_DICTIONARY:
			continue
		var media: Variant = candidato.get("media")
		var nombre: Variant = candidato.get("nombre")
		var indice := Protocolo.a_entero(candidato.get("indice"), -1)
		if typeof(media) != TYPE_STRING or typeof(nombre) != TYPE_STRING or indice < 0:
			continue
		normalizados.append({"media": media, "indice": indice, "nombre": nombre})
	return {"tipo": tipo, "sdp": sdp, "candidatos": normalizados}


## Los mensajeros (WhatsApp, Telegram...) a veces añaden saltos de línea,
## espacios o comillas al copiar. Nos quedamos solo con caracteres base64.
static func limpiar_codigo(codigo: String) -> String:
	var permitido := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
	var limpio := ""
	for caracter in codigo:
		if permitido.contains(caracter):
			limpio += caracter
	return limpio


# --- Interno --------------------------------------------------------------------------

func _crear_conexion() -> bool:
	_liberar_conexion()
	_cola.clear()
	_peer = WebRTCPeerConnection.new()
	var configuracion := {"iceServers": [{"urls": [SERVIDOR_STUN]}]}
	var error := _peer.initialize(configuracion)
	if error != OK:
		# En Android/escritorio sin el addon no hay implementación por defecto.
		_peer = null
		_fallar(TEXTO_SIN_ADDON if not OS.has_feature("web") else "Tu navegador no permite WebRTC.")
		return false
	_peer.session_description_created.connect(_al_crear_descripcion)
	_peer.ice_candidate_created.connect(_al_crear_candidato)
	# Canal negociado: ambos lados lo crean con el mismo id ANTES de la oferta.
	_canal = _peer.create_data_channel(ETIQUETA_CANAL, {"negotiated": true, "id": ID_CANAL_NEGOCIADO})
	if _canal == null:
		_fallar("No se pudo crear el canal de datos.")
		return false
	print("[Red] Conexión creada con: ", nombre_implementacion())
	return true


func _liberar_conexion() -> void:
	if _canal != null:
		_canal.close()
	if _peer != null:
		_peer.close()
	_canal = null
	_peer = null
	_tipo_local = ""
	_sdp_local = ""
	_candidatos_locales.clear()
	_recolectando = false
	_tiempo_recoleccion = 0.0
	_frames_drenaje = 0
	_tiempo_conectando = 0.0
	_tiempo_desconectado = 0.0
	_tiempo_latido = 0.0
	_tiempo_sin_noticias = 0.0


func _agregar_candidatos_remotos(candidatos: Array) -> void:
	# Deben añadirse DESPUÉS de set_remote_description.
	for candidato: Dictionary in candidatos:
		_peer.add_ice_candidate(candidato["media"], candidato["indice"], candidato["nombre"])


func _al_crear_descripcion(tipo: String, sdp: String) -> void:
	_tipo_local = tipo
	_sdp_local = sdp
	var error := _peer.set_local_description(tipo, sdp)
	if error != OK:
		_fallar("No se pudo fijar la descripción local (error %d)." % error)
		return
	# set_local_description arranca la recolección de candidatos ICE.
	_recolectando = true
	_tiempo_recoleccion = 0.0
	_frames_drenaje = 0


func _al_crear_candidato(media: String, indice: int, nombre: String) -> void:
	_candidatos_locales.append({"media": media, "indice": indice, "nombre": nombre})


func _process(delta: float) -> void:
	if _peer == null:
		return
	var paso := minf(delta, DELTA_MAXIMO_S)
	# poll() es obligatorio: despacha señales y actualiza estados y paquetes.
	_peer.poll()
	if _peer == null:
		return
	if _recolectando:
		_revisar_recoleccion(paso)
		if _peer == null:
			return
	_revisar_conexion(paso)
	if _peer == null:
		return
	_leer_mensajes()
	_entregar_cola()
	_latir(paso)


## Espera a que la recolección termine (estado COMPLETE) y entonces emite el código.
## WebRTCPeerConnection no tiene una señal de «recolección terminada»: se consulta
## get_gathering_state() en cada frame, justo después de poll().
func _revisar_recoleccion(paso: float) -> void:
	_tiempo_recoleccion += paso
	var completa := _peer.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE
	if completa:
		_frames_drenaje += 1
		if _frames_drenaje <= FRAMES_DRENAJE_CANDIDATOS:
			return
	elif _tiempo_recoleccion < TIEMPO_MAXIMO_RECOLECCION_S:
		return
	elif _candidatos_locales.is_empty():
		_fallar("No se encontraron rutas de red (candidatos ICE). Revisa tu conexión a internet.")
		return
	else:
		push_warning("[Red] La recolección ICE no terminó; se usan %d candidatos." % _candidatos_locales.size())
	_recolectando = false
	var codigo := codificar_codigo(_tipo_local, _sdp_local, _candidatos_locales)
	_cambiar_estado(Estado.ESPERANDO_RIVAL)
	codigo_generado.emit(codigo)


func _revisar_conexion(paso: float) -> void:
	var estado_peer := _peer.get_connection_state()
	match estado_peer:
		# Ojo: STATE_CONNECTING NO indica que el rival ya pegó su código. Las
		# implementaciones entran en ese estado en cuanto empieza ICE, incluso antes
		# de tener la descripción remota, así que no se usa para cambiar de estado.
		WebRTCPeerConnection.STATE_CONNECTED:
			_tiempo_desconectado = 0.0
		WebRTCPeerConnection.STATE_DISCONNECTED:
			if estado == Estado.CONECTADO:
				_tiempo_desconectado += paso
				if _tiempo_desconectado > TIEMPO_GRACIA_DESCONEXION_S:
					_perder_conexion("Se perdió la conexión con el rival.")
					return
		WebRTCPeerConnection.STATE_FAILED:
			if estado == Estado.CONECTADO:
				_perder_conexion("Se perdió la conexión con el rival.")
				return
			if estado == Estado.CONECTANDO:
				_fallar(TEXTO_TURN)
				return
			# El invitado que espera a que el anfitrión pegue su respuesta puede ver
			# FAILED porque sus comprobaciones ICE no obtienen respuesta todavía. Sigue
			# esperando: cuando el anfitrión aplique la respuesta, ICE puede recuperarse
			# con las comprobaciones que le lleguen.
		WebRTCPeerConnection.STATE_CLOSED:
			if estado == Estado.CONECTADO:
				_perder_conexion("El rival cerró la conexión.")
				return

	if estado == Estado.CONECTANDO:
		_tiempo_conectando += paso
		if _tiempo_conectando > TIEMPO_MAXIMO_CONEXION_S:
			_fallar(TEXTO_TURN)
			return

	var estado_canal := _canal.get_ready_state()
	if estado != Estado.CONECTADO and estado_canal == WebRTCDataChannel.STATE_OPEN:
		_tiempo_sin_noticias = 0.0
		_cambiar_estado(Estado.CONECTADO)
		_enviar_crudo({Protocolo.CLAVE_TIPO: MENSAJE_HOLA, "v": VERSION_CODIGO})
		conectado.emit()
	elif estado == Estado.CONECTADO and estado_canal == WebRTCDataChannel.STATE_CLOSED:
		_perder_conexion("El rival cerró la conexión.")


func _leer_mensajes() -> void:
	if _canal == null or _canal.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return
	while _canal.get_available_packet_count() > 0:
		var texto := _canal.get_packet().get_string_from_utf8()
		var datos: Variant = JSON.parse_string(texto)
		if typeof(datos) != TYPE_DICTIONARY:
			push_warning("[Red] Mensaje ignorado (no es JSON válido).")
			continue
		var mensaje: Dictionary = datos
		_tiempo_sin_noticias = 0.0
		match Protocolo.tipo_de(mensaje):
			"":
				push_warning("[Red] Mensaje sin tipo ignorado.")
			MENSAJE_LATIDO:
				pass
			MENSAJE_HOLA:
				var version := Protocolo.leer_entero(mensaje, "v")
				if version != VERSION_CODIGO:
					_perder_conexion("El rival usa otra versión del juego (%d)." % version)
					return
			_:
				_cola.append(mensaje)


func _entregar_cola() -> void:
	# Se vuelve a comprobar el receptor en cada vuelta: un mensaje puede provocar
	# un cambio de escena que lo anule.
	while not _cola.is_empty() and _receptor.is_valid():
		var mensaje: Dictionary = _cola.pop_front()
		_receptor.call(mensaje)


func _latir(paso: float) -> void:
	if estado != Estado.CONECTADO:
		return
	_tiempo_latido += paso
	if _tiempo_latido >= INTERVALO_LATIDO_S:
		_tiempo_latido = 0.0
		_enviar_crudo({Protocolo.CLAVE_TIPO: MENSAJE_LATIDO})
	_tiempo_sin_noticias += paso
	if _tiempo_sin_noticias > TIEMPO_SIN_NOTICIAS_S:
		_perder_conexion("El rival no responde.")


func _enviar_crudo(mensaje: Dictionary) -> bool:
	if _canal == null or _canal.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return false
	return _canal.put_packet(JSON.stringify(mensaje).to_utf8_buffer()) == OK


func _cambiar_estado(nuevo: Estado) -> void:
	if estado == nuevo:
		return
	estado = nuevo
	estado_cambiado.emit(nuevo)


func _perder_conexion(motivo: String) -> void:
	_liberar_conexion()
	_cambiar_estado(Estado.DESCONECTADO)
	desconectado.emit(motivo)


func _fallar(mensaje: String) -> void:
	push_warning("[Red] " + mensaje)
	_liberar_conexion()
	_cambiar_estado(Estado.ERROR)
	desconectado.emit(mensaje)
