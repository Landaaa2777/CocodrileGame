extends Node
## Autoload «Audio»: música (con fundidos y capa de tensión) y efectos de sonido.
##
## Buses (default_bus_layout.tres): Master ─┬─ Musica
##                                          └─ SFX
## El volumen de cada bus se guarda en user://ajustes.cfg.
##
## Web: los navegadores no dejan sonar audio hasta la primera interacción del
## usuario (política de autoplay). Hasta entonces la música queda «pendiente» y
## arranca desde el principio con el primer toque/clic/tecla.

signal audio_desbloqueado

const BUS_MUSICA := &"Musica"
const BUS_SFX := &"SFX"
const RUTA_AJUSTES := "user://ajustes.cfg"
const SECCION_AJUSTES := "audio"
const VOLUMEN_INICIAL := 0.8
const DURACION_FUNDIDO_MUSICA_S := 0.9
const VOLUMEN_SILENCIO_DB := -60.0
const CANALES_SFX := 10
## Capa de tensión de la partida: inaudible al empezar, a tope con el último diente.
const VOLUMEN_TENSION_MIN_DB := -32.0
const VOLUMEN_TENSION_MAX_DB := -4.0
const TONO_TENSION_MAX := 1.05
const DURACION_CAMBIO_TENSION_S := 1.2

const RUTA_AUDIO := "res://assets/audio/"
const PISTAS := {
	"menu": "musica_menu.wav",
	"partida": "musica_partida.wav",
}
const PISTA_TENSION := "musica_partida_tension.wav"
const EFECTOS := {
	"clic_diente": "sfx_clic_diente.wav",
	"hover_diente": "sfx_hover_diente.wav",
	"tic": "sfx_tic.wav",
	"anticipacion": "sfx_anticipacion.wav",
	"mordida": "sfx_mordida.wav",
	"victoria": "sfx_victoria.wav",
	"derrota": "sfx_derrota.wav",
	"salvado": "sfx_salvado.wav",
	"boton": "sfx_boton.wav",
	"transicion": "sfx_transicion.wav",
	"conectado": "sfx_conectado.wav",
}

var volumen_musica := VOLUMEN_INICIAL
var volumen_sfx := VOLUMEN_INICIAL
var desbloqueado := not OS.has_feature("web")

var _musica_a: AudioStreamPlayer
var _musica_b: AudioStreamPlayer
var _musica_activa: AudioStreamPlayer
var _capa_tension: AudioStreamPlayer
var _pista_actual := ""
var _pista_pendiente := ""
var _tension := 0.0
var _canales_sfx: Array[AudioStreamPlayer] = []
var _siguiente_canal := 0
var _streams := {}
var _tween_tension: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_musica_a = _crear_reproductor(BUS_MUSICA)
	_musica_b = _crear_reproductor(BUS_MUSICA)
	_capa_tension = _crear_reproductor(BUS_MUSICA)
	_musica_activa = _musica_a
	for i in CANALES_SFX:
		_canales_sfx.append(_crear_reproductor(BUS_SFX))
	_cargar_ajustes()


func _input(evento: InputEvent) -> void:
	if desbloqueado:
		return
	var es_interaccion := (evento is InputEventMouseButton and evento.pressed) \
		or (evento is InputEventScreenTouch and evento.pressed) \
		or (evento is InputEventKey and evento.pressed)
	if es_interaccion:
		desbloqueado = true
		audio_desbloqueado.emit()
		if not _pista_pendiente.is_empty():
			var pista := _pista_pendiente
			_pista_pendiente = ""
			_pista_actual = ""
			reproducir_musica(pista)


# --- Música ------------------------------------------------------------------------

## Cambia de pista con un fundido cruzado. «partida» arranca además la capa de tensión.
func reproducir_musica(nombre: String) -> void:
	if not PISTAS.has(nombre) or nombre == _pista_actual:
		return
	if not desbloqueado:
		_pista_pendiente = nombre
		return
	var stream := _obtener_stream(PISTAS[nombre], true)
	if stream == null:
		return
	_pista_actual = nombre
	var saliente := _musica_activa
	var entrante := _musica_b if _musica_activa == _musica_a else _musica_a
	_musica_activa = entrante
	entrante.stream = stream
	entrante.volume_db = VOLUMEN_SILENCIO_DB
	entrante.pitch_scale = 1.0
	entrante.play()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(entrante, "volume_db", 0.0, DURACION_FUNDIDO_MUSICA_S) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if saliente.playing:
		tween.tween_property(saliente, "volume_db", VOLUMEN_SILENCIO_DB, DURACION_FUNDIDO_MUSICA_S) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(saliente.stop)

	_tension = 0.0
	if nombre == "partida":
		var capa := _obtener_stream(PISTA_TENSION, true)
		if capa != null:
			# Ambas pistas duran lo mismo y tienen el mismo tempo: arrancan juntas.
			_capa_tension.stream = capa
			_capa_tension.volume_db = VOLUMEN_TENSION_MIN_DB
			_capa_tension.pitch_scale = 1.0
			_capa_tension.play(entrante.get_playback_position())
	elif _capa_tension.playing:
		var fundido := create_tween()
		fundido.tween_property(_capa_tension, "volume_db", VOLUMEN_SILENCIO_DB, DURACION_FUNDIDO_MUSICA_S)
		fundido.tween_callback(_capa_tension.stop)


func detener_musica() -> void:
	_pista_actual = ""
	_pista_pendiente = ""
	for reproductor in [_musica_a, _musica_b, _capa_tension]:
		var tween := create_tween()
		tween.tween_property(reproductor, "volume_db", VOLUMEN_SILENCIO_DB, DURACION_FUNDIDO_MUSICA_S)
		tween.tween_callback(reproductor.stop)


## 0.0 = calma, 1.0 = la mordida es inminente. Sube el volumen de la capa de
## percusión tensa y acelera un poco el tempo de toda la música.
func establecer_tension(valor: float) -> void:
	_tension = clampf(valor, 0.0, 1.0)
	if _tween_tension != null and _tween_tension.is_valid():
		_tween_tension.kill()
	var volumen := lerpf(VOLUMEN_TENSION_MIN_DB, VOLUMEN_TENSION_MAX_DB, sqrt(_tension))
	var tono := lerpf(1.0, TONO_TENSION_MAX, _tension)
	_tween_tension = create_tween().set_parallel(true)
	_tween_tension.tween_property(_capa_tension, "volume_db", volumen, DURACION_CAMBIO_TENSION_S) \
		.set_trans(Tween.TRANS_SINE)
	for reproductor in [_musica_activa, _capa_tension]:
		_tween_tension.tween_property(reproductor, "pitch_scale", tono, DURACION_CAMBIO_TENSION_S) \
			.set_trans(Tween.TRANS_SINE)


# --- Efectos -------------------------------------------------------------------------

## Reproduce un efecto. «variacion» desafina un poco al azar para que no suene repetitivo.
func reproducir_sfx(nombre: String, tono: float = 1.0, variacion: float = 0.0) -> void:
	if not desbloqueado or not EFECTOS.has(nombre):
		return
	var stream := _obtener_stream(EFECTOS[nombre], false)
	if stream == null:
		return
	var canal := _canales_sfx[_siguiente_canal]
	_siguiente_canal = (_siguiente_canal + 1) % _canales_sfx.size()
	canal.stream = stream
	canal.pitch_scale = maxf(0.05, tono + randf_range(-variacion, variacion))
	canal.play()


# --- Volumen y ajustes ---------------------------------------------------------------

func fijar_volumen_musica(lineal: float) -> void:
	volumen_musica = clampf(lineal, 0.0, 1.0)
	_aplicar_volumen(BUS_MUSICA, volumen_musica)
	_guardar_ajustes()


func fijar_volumen_sfx(lineal: float) -> void:
	volumen_sfx = clampf(lineal, 0.0, 1.0)
	_aplicar_volumen(BUS_SFX, volumen_sfx)
	_guardar_ajustes()


func _aplicar_volumen(bus: StringName, lineal: float) -> void:
	var indice := AudioServer.get_bus_index(bus)
	if indice < 0:
		push_warning("[Audio] No existe el bus %s" % bus)
		return
	AudioServer.set_bus_mute(indice, lineal <= 0.0)
	AudioServer.set_bus_volume_db(indice, linear_to_db(maxf(lineal, 0.0001)))


func _cargar_ajustes() -> void:
	var archivo := ConfigFile.new()
	if archivo.load(RUTA_AJUSTES) == OK:
		volumen_musica = clampf(float(archivo.get_value(SECCION_AJUSTES, "musica", VOLUMEN_INICIAL)), 0.0, 1.0)
		volumen_sfx = clampf(float(archivo.get_value(SECCION_AJUSTES, "sfx", VOLUMEN_INICIAL)), 0.0, 1.0)
	_aplicar_volumen(BUS_MUSICA, volumen_musica)
	_aplicar_volumen(BUS_SFX, volumen_sfx)


func _guardar_ajustes() -> void:
	var archivo := ConfigFile.new()
	archivo.set_value(SECCION_AJUSTES, "musica", volumen_musica)
	archivo.set_value(SECCION_AJUSTES, "sfx", volumen_sfx)
	archivo.save(RUTA_AJUSTES)


# --- Utilidades ----------------------------------------------------------------------

func _crear_reproductor(bus: StringName) -> AudioStreamPlayer:
	var reproductor := AudioStreamPlayer.new()
	reproductor.bus = bus
	add_child(reproductor)
	return reproductor


func _obtener_stream(archivo: String, en_bucle: bool) -> AudioStream:
	if _streams.has(archivo):
		return _streams[archivo]
	var ruta := RUTA_AUDIO + archivo
	if not ResourceLoader.exists(ruta):
		push_warning("[Audio] Falta %s (ejecuta tools/generar_audio.py)" % ruta)
		_streams[archivo] = null
		return null
	var stream: AudioStream = load(ruta)
	if en_bucle:
		_asegurar_bucle(stream)
	_streams[archivo] = stream
	return stream


## Los WAV generados llevan un bloque «smpl» con los puntos de bucle, que Godot
## detecta al importar. Si aun así llega sin bucle, lo activamos aquí.
func _asegurar_bucle(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
