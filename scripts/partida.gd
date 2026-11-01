extends Node
## Pantalla de juego.
##
## Autoridad: el ANFITRIÓN (o este dispositivo en modo práctica) tiene la
## instancia de ReglasJuego que conoce el diente mordedor, valida TODAS las jugadas
## y difunde el resultado. El invitado solo envía peticiones (JUGADA) y anima lo
## que el anfitrión le responde. Ambos animan los resultados con el mismo código
## (_animar_resultado), procesados en cola uno detrás de otro.

const ESCENA_MENU := "res://escenas/menu.tscn"
const ESCENA_RESULTADO := "res://escenas/resultado.tscn"

const TICS_SUSPENSE := 3
const INTERVALO_TIC_S := 0.17
const PAUSA_TRAS_SEGURO_S := 0.45
const RETRASO_RESULTADO_S := 1.5
const RETRASO_BOT_MIN_S := 0.8
const RETRASO_BOT_MAX_S := 1.7
const DURACION_DUDA_BOT_S := 0.55
const DURACION_GLOBO_S := 1.3
const SUBIDA_GLOBO_PX := 90.0
const SEPARACION_GLOBO_PX := 70.0
const DURACION_ANUNCIO_S := 1.0
const DURACION_DESTELLO_S := 0.28
const OPACIDAD_DESTELLO := 0.65
const LONGITUD_RAYO := 100.0
const BYTES_SAL := 16
const COLOR_MI_TURNO := Color(0.6, 0.92, 0.3)
const COLOR_TURNO_RIVAL := Color(1.0, 0.55, 0.55)
const COLOR_NEUTRO := Color(1.0, 1.0, 1.0, 0.92)
## Argumento de línea de comandos (tras «--») para las pruebas de humo del CI:
## en modo práctica el bot juega también por el jugador local.
const ARGUMENTO_AUTOJUGAR := "--autojugar"

enum Modo { RED, PRACTICA }

@onready var escenario: Escenario = $Escenario
@onready var cocodrilo: Cocodrilo = $Escenario/Cocodrilo
@onready var turno_panel: PanelContainer = %Turno
@onready var turno_texto: Label = %TurnoTexto
@onready var marcador: Label = %Marcador
@onready var anuncio: Label = %Anuncio
@onready var capa_globos: Control = %Globos
@onready var destello: ColorRect = %Destello
@onready var boton_salir: Button = %BotonSalir
@onready var velo: ColorRect = %Velo
@onready var dialogo: PanelContainer = %Dialogo
@onready var dialogo_texto: Label = %DialogoTexto
@onready var boton_dialogo: Button = %BotonDialogo

var modo: Modo = Modo.RED
var soy_anfitrion := true
var mi_jugador := ReglasJuego.ANFITRION
## Autoritativa en el anfitrión/práctica; espejo sin mordedor en el invitado.
var reglas := ReglasJuego.new()

var _rng := RandomNumberGenerator.new()
var _sal := ""
var _compromiso := ""
var _ronda_iniciada := false
var _terminada := false
var _esperando_respuesta := false
var _animando := false
var _cola_resultados: Array[Dictionary] = []
var _diente_apuntado: Diente = null
var _diente_pulsado: Diente = null
var _diente_rival: Diente = null
var _estilo_turno: StyleBoxFlat
var _autojugar := false


func _ready() -> void:
	_rng.randomize()
	_autojugar = ARGUMENTO_AUTOJUGAR in OS.get_cmdline_user_args()
	var datos := Transicion.datos
	modo = Modo.PRACTICA if datos.get("modo", "") == "practica" else Modo.RED
	if modo == Modo.RED and not Red.esta_conectado():
		# Abrir la escena sin conexión (p. ej. desde el editor) = modo práctica.
		modo = Modo.PRACTICA
	soy_anfitrion = modo == Modo.PRACTICA or Red.es_anfitrion
	mi_jugador = ReglasJuego.ANFITRION if soy_anfitrion else ReglasJuego.INVITADO

	_estilo_turno = (turno_panel.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	turno_panel.add_theme_stylebox_override("panel", _estilo_turno)
	cocodrilo.impacto_mordida.connect(_al_impactar_mordida)
	AnimUI.preparar_boton(boton_salir)
	AnimUI.preparar_boton(boton_dialogo)
	boton_salir.pressed.connect(_salir)
	boton_dialogo.pressed.connect(_volver_al_menu)
	velo.visible = false
	dialogo.visible = false
	anuncio.visible = false
	destello.color.a = 0.0
	Audio.reproducir_musica("partida")
	Audio.establecer_tension(0.0)
	_actualizar_marcador()
	_mostrar_turno("Preparando...", COLOR_NEUTRO)

	if modo == Modo.RED:
		Red.establecer_receptor(_al_recibir_mensaje)
		Red.desconectado.connect(_al_desconectar)
		if not soy_anfitrion:
			# El anfitrión empieza la ronda cuando sabe que el invitado ya cargó la escena.
			Red.enviar(Protocolo.crear(Protocolo.LISTO))
	else:
		await get_tree().process_frame
		_iniciar_ronda_como_autoridad()


# --- Rondas ----------------------------------------------------------------------------

func _iniciar_ronda_como_autoridad() -> void:
	if _ronda_iniciada:
		return
	reglas.ronda = int(Red.sesion.get("ronda", 0))
	reglas.nueva_ronda(_rng)  # elige el mordedor en secreto
	Red.sesion["ronda"] = reglas.ronda
	_sal = Crypto.new().generate_random_bytes(BYTES_SAL).hex_encode()
	var compromiso := ReglasJuego.crear_compromiso(reglas.diente_mordedor, _sal)
	if modo == Modo.RED:
		Red.enviar(Protocolo.crear(Protocolo.INICIO,
			{"ronda": reglas.ronda, "turno": reglas.turno, "compromiso": compromiso}))
	_comenzar_ronda_local()


func _comenzar_ronda_local() -> void:
	_ronda_iniciada = true
	_terminada = false
	cocodrilo.reiniciar()
	cocodrilo.abrir_boca()
	Audio.establecer_tension(0.0)
	_mostrar_anuncio("Ronda %d" % reglas.ronda)
	_actualizar_turno()
	_programar_bot_si_toca()


func _terminar_ronda(perdedor: int, mensaje: Dictionary) -> void:
	_terminada = true
	var gane := perdedor != mi_jugador
	print("[Partida] Ronda %d terminada: pierde el jugador %d" % [reglas.ronda, perdedor])
	var verificado := true
	if not soy_anfitrion:
		# Comprobación del compromiso: el mordedor revelado debe coincidir con el
		# publicado al inicio y con el diente que mordió.
		var mordedor := Protocolo.leer_entero(mensaje, "mordedor")
		var sal := Protocolo.leer_texto(mensaje, "sal")
		verificado = ReglasJuego.verificar_compromiso(_compromiso, mordedor, sal) \
			and mordedor == Protocolo.leer_entero(mensaje, "diente")
	var clave := "victorias" if gane else "derrotas"
	Red.sesion[clave] = int(Red.sesion.get(clave, 0)) + 1
	_actualizar_marcador()
	_mostrar_turno("¡Ñam!", COLOR_TURNO_RIVAL if not gane else COLOR_MI_TURNO)
	await get_tree().create_timer(RETRASO_RESULTADO_S).timeout
	if is_inside_tree():
		Transicion.cambiar_escena(ESCENA_RESULTADO, {
			"gane": gane,
			"modo": "practica" if modo == Modo.PRACTICA else "red",
			"verificado": verificado,
			"es_anfitrion": soy_anfitrion,
		})


# --- Entrada: apuntar y presionar dientes ------------------------------------------------

func _unhandled_input(evento: InputEvent) -> void:
	# Con «emulate_mouse_from_touch» el dedo también llega como eventos de ratón.
	if evento is InputEventMouseMotion:
		_actualizar_apuntado(_diente_bajo(evento.position))
	elif evento is InputEventMouseButton and evento.button_index == MOUSE_BUTTON_LEFT:
		var diente := _diente_bajo(evento.position)
		if evento.pressed:
			_actualizar_apuntado(diente)
			_diente_pulsado = diente if _puedo_jugar(diente) else null
		else:
			if diente != null and diente == _diente_pulsado and _puedo_jugar(diente):
				_jugar(diente)
			_diente_pulsado = null
			if DisplayServer.is_touchscreen_available():
				# En pantallas táctiles no hay «hover»: al levantar el dedo se deja de apuntar.
				_actualizar_apuntado(null)


func _diente_bajo(posicion: Vector2) -> Diente:
	var camara := escenario.camara
	var origen := camara.project_ray_origin(posicion)
	var destino := origen + camara.project_ray_normal(posicion) * LONGITUD_RAYO
	var consulta := PhysicsRayQueryParameters3D.create(origen, destino)
	consulta.collide_with_areas = true
	consulta.collide_with_bodies = false
	var impacto := escenario.get_world_3d().direct_space_state.intersect_ray(consulta)
	if impacto.is_empty():
		return null
	return impacto["collider"] as Diente


func _puedo_jugar(diente: Diente) -> bool:
	return diente != null and not diente.usado and _ronda_iniciada and not _terminada \
		and not _esperando_respuesta and not _animando and reglas.en_curso and reglas.turno == mi_jugador


func _actualizar_apuntado(diente: Diente) -> void:
	var nuevo: Diente = diente if _puedo_jugar(diente) else null
	if nuevo == _diente_apuntado:
		return
	if _diente_apuntado != null:
		_diente_apuntado.apuntar(false)
	_diente_apuntado = nuevo
	if nuevo != null:
		nuevo.apuntar(true)
		Audio.reproducir_sfx("hover_diente", 1.0 + nuevo.indice * 0.03)
	if modo == Modo.RED:
		Red.enviar(Protocolo.crear(Protocolo.APUNTA, {"diente": nuevo.indice if nuevo else -1}))


func _jugar(diente: Diente) -> void:
	_actualizar_apuntado(null)
	Audio.reproducir_sfx("clic_diente", 1.0, 0.08)
	diente.presionar()
	if soy_anfitrion:
		var resultado := reglas.aplicar_jugada(mi_jugador, diente.indice)
		if resultado["valida"]:
			_difundir_resultado(resultado)
	else:
		# El invitado no decide nada: pide la jugada y espera la respuesta.
		_esperando_respuesta = true
		_mostrar_turno("...", COLOR_NEUTRO)
		Red.enviar(Protocolo.crear(Protocolo.JUGADA, {"diente": diente.indice}))


# --- Autoridad: difundir resultados --------------------------------------------------------

func _difundir_resultado(resultado: Dictionary) -> void:
	var mensaje := {
		"jugador": resultado["jugador"],
		"diente": resultado["diente"],
		"mordida": resultado["mordida"],
		"turno": resultado["turno"],
	}
	if resultado["mordida"]:
		# Al terminar se revela el mordedor y la sal para verificar el compromiso.
		mensaje["mordedor"] = reglas.diente_mordedor
		mensaje["sal"] = _sal
	if modo == Modo.RED:
		Red.enviar(Protocolo.crear(Protocolo.RESULTADO, mensaje))
	_encolar_resultado(mensaje)


func _encolar_resultado(mensaje: Dictionary) -> void:
	_cola_resultados.append(mensaje)
	if not _animando:
		_procesar_cola()


func _procesar_cola() -> void:
	_animando = true
	while not _cola_resultados.is_empty() and is_inside_tree():
		await _animar_resultado(_cola_resultados.pop_front())
	_animando = false
	if not _terminada:
		_actualizar_turno()
		_programar_bot_si_toca()


func _animar_resultado(mensaje: Dictionary) -> void:
	var jugador := Protocolo.leer_entero(mensaje, "jugador")
	var indice := Protocolo.leer_entero(mensaje, "diente")
	var mordida := Protocolo.leer_bool(mensaje, "mordida")
	var siguiente := Protocolo.leer_entero(mensaje, "turno")
	if not soy_anfitrion:
		reglas.aplicar_resultado_remoto(jugador, indice, mordida, siguiente)
		_esperando_respuesta = false
	var diente := cocodrilo.obtener_diente(indice)
	if diente == null:
		return
	if _diente_rival != null:
		_diente_rival.marcar_apuntado_rival(false)
		_diente_rival = null
	if jugador != mi_jugador:
		Audio.reproducir_sfx("clic_diente", 1.0, 0.08)
		diente.presionar()
	_mostrar_turno("¿Morderá...?", COLOR_NEUTRO)
	# Suspense: unos «tic» con el tono subiendo.
	for i in TICS_SUSPENSE:
		Audio.reproducir_sfx("tic", 1.0 + i * 0.12)
		await get_tree().create_timer(INTERVALO_TIC_S).timeout
	if mordida:
		diente.marcar_mordedor()
		Audio.reproducir_sfx("anticipacion")
		await cocodrilo.anticipar_mordida()
		Audio.reproducir_sfx("mordida")
		await cocodrilo.morder()
		await _terminar_ronda(jugador, mensaje)
	else:
		diente.marcar_seguro()
		cocodrilo.alivio()
		Audio.reproducir_sfx("salvado", 1.0, 0.04)
		_mostrar_globo("¡Uf, salvado!", diente)
		var tension := reglas.tension()
		cocodrilo.tension = tension
		Audio.establecer_tension(tension)
		await get_tree().create_timer(PAUSA_TRAS_SEGURO_S).timeout


func _al_impactar_mordida() -> void:
	escenario.impacto(cocodrilo.mandibula.global_position + Vector3(0, 0.3, 1.4))
	destello.color.a = OPACIDAD_DESTELLO
	create_tween().tween_property(destello, "color:a", 0.0, DURACION_DESTELLO_S) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# --- Red ---------------------------------------------------------------------------------

func _al_recibir_mensaje(mensaje: Dictionary) -> void:
	match Protocolo.tipo_de(mensaje):
		Protocolo.LISTO:
			if soy_anfitrion:
				_iniciar_ronda_como_autoridad()
		Protocolo.INICIO:
			if not soy_anfitrion:
				_recibir_inicio(mensaje)
		Protocolo.JUGADA:
			if soy_anfitrion:
				_recibir_jugada(mensaje)
		Protocolo.RESULTADO:
			if not soy_anfitrion:
				_recibir_resultado(mensaje)
		Protocolo.RECHAZO:
			if not soy_anfitrion:
				_esperando_respuesta = false
				_mostrar_anuncio(Protocolo.leer_texto(mensaje, "motivo"))
				_actualizar_turno()
		Protocolo.APUNTA:
			_recibir_apunta(mensaje)
		Protocolo.SALIR:
			_mostrar_dialogo("Tu rival salió de la partida.")


func _recibir_inicio(mensaje: Dictionary) -> void:
	var ronda := Protocolo.leer_entero(mensaje, "ronda")
	var turno := Protocolo.leer_entero(mensaje, "turno")
	if ronda < 1 or not ReglasJuego.es_jugador_valido(turno):
		push_warning("[Partida] INICIO inválido: %s" % mensaje)
		return
	_compromiso = Protocolo.leer_texto(mensaje, "compromiso")
	reglas.nueva_ronda_espejo(ronda, turno)
	Red.sesion["ronda"] = ronda
	_comenzar_ronda_local()


## El anfitrión valida la petición del invitado: que sea su turno, que el diente
## exista y que no se haya usado. Si no, responde RECHAZO y no cambia nada.
func _recibir_jugada(mensaje: Dictionary) -> void:
	var diente := Protocolo.leer_entero(mensaje, "diente")
	var error := reglas.validar_jugada(ReglasJuego.INVITADO, diente)
	if error != ReglasJuego.ErrorJugada.NINGUNO:
		Red.enviar(Protocolo.crear(Protocolo.RECHAZO,
			{"diente": diente, "motivo": ReglasJuego.describir_error(error)}))
		return
	_difundir_resultado(reglas.aplicar_jugada(ReglasJuego.INVITADO, diente))


func _recibir_resultado(mensaje: Dictionary) -> void:
	var jugador := Protocolo.leer_entero(mensaje, "jugador")
	var diente := Protocolo.leer_entero(mensaje, "diente")
	var turno := Protocolo.leer_entero(mensaje, "turno")
	if not ReglasJuego.es_jugador_valido(jugador) or not ReglasJuego.es_indice_valido(diente) \
			or not ReglasJuego.es_jugador_valido(turno):
		push_warning("[Partida] RESULTADO inválido: %s" % mensaje)
		return
	_encolar_resultado(mensaje)


func _recibir_apunta(mensaje: Dictionary) -> void:
	if _diente_rival != null:
		_diente_rival.marcar_apuntado_rival(false)
		_diente_rival = null
	var indice := Protocolo.leer_entero(mensaje, "diente")
	if ReglasJuego.es_indice_valido(indice) and reglas.turno != mi_jugador:
		_diente_rival = cocodrilo.obtener_diente(indice)
		if _diente_rival != null:
			_diente_rival.marcar_apuntado_rival(true)


func _al_desconectar(motivo: String) -> void:
	if not _terminada:
		_mostrar_dialogo(motivo)


# --- Bot del modo práctica ----------------------------------------------------------------

func _programar_bot_si_toca() -> void:
	if modo != Modo.PRACTICA or _terminada or _animando:
		return
	if reglas.turno == ReglasJuego.INVITADO or (_autojugar and reglas.turno == mi_jugador):
		_jugar_bot(reglas.turno)


## El bot NO conoce el mordedor: elige al azar entre los dientes libres.
func _jugar_bot(jugador: int) -> void:
	await get_tree().create_timer(_rng.randf_range(RETRASO_BOT_MIN_S, RETRASO_BOT_MAX_S)).timeout
	if not is_inside_tree() or _terminada or _animando or reglas.turno != jugador:
		return
	var libres: Array[int] = []
	for i in ReglasJuego.TOTAL_DIENTES:
		if not reglas.esta_usado(i):
			libres.append(i)
	if libres.is_empty():
		return
	var eleccion: int = libres[_rng.randi_range(0, libres.size() - 1)]
	var diente := cocodrilo.obtener_diente(eleccion)
	diente.marcar_apuntado_rival(true)
	await get_tree().create_timer(DURACION_DUDA_BOT_S).timeout
	if not is_inside_tree() or _terminada:
		return
	diente.marcar_apuntado_rival(false)
	if jugador == mi_jugador:
		diente.presionar()
	_difundir_resultado(reglas.aplicar_jugada(jugador, eleccion))


# --- Interfaz ------------------------------------------------------------------------------

func _actualizar_turno() -> void:
	if _terminada or not _ronda_iniciada:
		return
	if reglas.turno == mi_jugador:
		_mostrar_turno("¡Tu turno!", COLOR_MI_TURNO)
	else:
		_mostrar_turno("Turno del bot" if modo == Modo.PRACTICA else "Turno del rival", COLOR_TURNO_RIVAL)


func _mostrar_turno(texto: String, color: Color) -> void:
	if turno_texto.text == texto:
		return
	turno_texto.text = texto
	var tween := create_tween()
	tween.tween_property(_estilo_turno, "bg_color", color, 0.25).set_trans(Tween.TRANS_SINE)
	AnimUI.aparecer(turno_panel, 0.0, 0.4)


func _actualizar_marcador() -> void:
	var rival := "Bot" if modo == Modo.PRACTICA else "Rival"
	marcador.text = "Tú %d  ·  %d %s" % [int(Red.sesion.get("victorias", 0)), int(Red.sesion.get("derrotas", 0)),
		rival]


func _mostrar_anuncio(texto: String) -> void:
	anuncio.text = texto
	anuncio.visible = true
	anuncio.modulate.a = 1.0
	await get_tree().process_frame
	var tween := AnimUI.aparecer(anuncio, 0.0, 0.5)
	tween.tween_interval(DURACION_ANUNCIO_S)
	tween.tween_property(anuncio, "modulate:a", 0.0, 0.3)
	tween.tween_callback(anuncio.hide)


## Globo de texto que sale del diente, sube y se desvanece.
func _mostrar_globo(texto: String, diente: Diente) -> void:
	var globo := PanelContainer.new()
	globo.theme_type_variation = &"Globo"
	globo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var etiqueta := Label.new()
	etiqueta.text = texto
	etiqueta.add_theme_font_size_override("font_size", 34)
	etiqueta.add_theme_color_override("font_color", Color(0.18, 0.5, 0.08))
	globo.add_child(etiqueta)
	capa_globos.add_child(globo)
	await get_tree().process_frame
	var punto := escenario.camara.unproject_position(diente.punta_global())
	globo.position = punto - Vector2(globo.size.x * 0.5, globo.size.y + SEPARACION_GLOBO_PX)
	var tween := AnimUI.aparecer(globo, 0.0, 0.35)
	tween.set_parallel(true)
	tween.tween_property(globo, "position:y", globo.position.y - SUBIDA_GLOBO_PX, DURACION_GLOBO_S) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(globo, "modulate:a", 0.0, DURACION_GLOBO_S * 0.4).set_delay(DURACION_GLOBO_S * 0.6)
	tween.chain().tween_callback(globo.queue_free)


func _mostrar_dialogo(texto: String) -> void:
	if dialogo.visible:
		return
	_terminada = true
	dialogo_texto.text = texto
	velo.visible = true
	dialogo.visible = true
	AnimUI.aparecer(dialogo)


func _salir() -> void:
	if modo == Modo.RED:
		Red.enviar(Protocolo.crear(Protocolo.SALIR))
	_volver_al_menu()


func _volver_al_menu() -> void:
	Red.cerrar()
	Transicion.cambiar_escena(ESCENA_MENU)
