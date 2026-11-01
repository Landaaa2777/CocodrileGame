extends Node
## Pantalla de resultado: «¡Ganaste!» o «Perdiste», pose del cocodrilo y revancha.
##
## Revancha en red: cada jugador pulsa «Jugar otra vez» (mensaje REVANCHA). Cuando
## el anfitrión sabe que ambos quieren jugar, envía REVANCHA_OK y los dos pasan a
## la partida, donde el saludo LISTO/INICIO arranca la ronda siguiente.

const ESCENA_MENU := "res://escenas/menu.tscn"
const ESCENA_PARTIDA := "res://escenas/partida.tscn"
const COLOR_VICTORIA := Color(0.55, 0.9, 0.25)
const COLOR_DERROTA := Color(1.0, 0.45, 0.45)
const RETRASO_SONIDO_S := 0.25
const RETRASO_MUSICA_S := 2.2
const RETRASO_AUTOJUGAR_S := 1.0

@onready var escenario: Escenario = $Escenario
@onready var titulo: Label = %Titulo
@onready var subtitulo: Label = %Subtitulo
@onready var marcador: Label = %Marcador
@onready var verificacion: Label = %Verificacion
@onready var estado: Label = %Estado
@onready var boton_otra_vez: Button = %BotonOtraVez
@onready var boton_menu: Button = %BotonMenu

var gane := false
var en_red := false
var soy_anfitrion := true
var _yo_quiero_revancha := false
var _rival_quiere_revancha := false
var _cambiando := false


func _ready() -> void:
	var datos := Transicion.datos
	gane = bool(datos.get("gane", false))
	en_red = datos.get("modo", "practica") == "red" and Red.esta_conectado()
	soy_anfitrion = bool(datos.get("es_anfitrion", true))

	titulo.text = "¡Ganaste!" if gane else "Perdiste"
	titulo.add_theme_color_override("font_color", COLOR_VICTORIA if gane else COLOR_DERROTA)
	if gane:
		subtitulo.text = "¡El cocodrilo mordió a tu rival!"
	else:
		subtitulo.text = "¡Ñam! Te mordió el cocodrilo"
	var rival := "Rival" if datos.get("modo", "") == "red" else "Bot"
	marcador.text = "Tú %d  ·  %d %s" % [int(Red.sesion.get("victorias", 0)), int(Red.sesion.get("derrotas", 0)),
		rival]
	verificacion.visible = en_red and not soy_anfitrion
	if verificacion.visible:
		if bool(datos.get("verificado", true)):
			verificacion.text = "✔ El anfitrión no cambió el diente mordedor"
		else:
			verificacion.text = "⚠ ¡El diente mordedor cambió durante la ronda!"
	estado.text = ""

	for boton: Button in [boton_otra_vez, boton_menu]:
		AnimUI.preparar_boton(boton)
	boton_otra_vez.pressed.connect(_pedir_revancha)
	boton_menu.pressed.connect(_ir_al_menu)

	if en_red:
		Red.establecer_receptor(_al_recibir_mensaje)
		Red.desconectado.connect(_al_desconectar)
	elif datos.get("modo", "") == "red":
		# Llegamos aquí en red pero la conexión ya se cayó.
		boton_otra_vez.disabled = true
		estado.text = "La conexión con el rival se cerró."

	Audio.detener_musica()
	escenario.camara.rumbo_grados = 0.0
	escenario.camara.actualizar()
	if gane:
		escenario.cocodrilo.pose_feliz()
		escenario.lanzar_confeti()
	else:
		escenario.cocodrilo.pose_derrota()
	await get_tree().process_frame
	_animar_entrada()
	await get_tree().create_timer(RETRASO_SONIDO_S).timeout
	Audio.reproducir_sfx("victoria" if gane else "derrota")
	await get_tree().create_timer(RETRASO_MUSICA_S).timeout
	if is_inside_tree() and not _cambiando:
		Audio.reproducir_musica("menu")
	# Pruebas de humo del CI: en práctica, encadena rondas sin intervención.
	if not en_red and "--autojugar" in OS.get_cmdline_user_args():
		await get_tree().create_timer(RETRASO_AUTOJUGAR_S).timeout
		if is_inside_tree():
			_pedir_revancha()


func _animar_entrada() -> void:
	var retraso := 0.0
	for control: Control in [titulo, subtitulo, marcador, verificacion, boton_otra_vez, boton_menu]:
		if control.visible:
			AnimUI.aparecer(control, retraso, 0.5)
			retraso += 0.12


func _pedir_revancha() -> void:
	if not en_red:
		_cambiar_a(ESCENA_PARTIDA, {"modo": "practica"})
		return
	_yo_quiero_revancha = true
	boton_otra_vez.disabled = true
	Red.enviar(Protocolo.crear(Protocolo.REVANCHA))
	_fijar_estado("Esperando al rival...")
	_comprobar_revancha()


func _comprobar_revancha() -> void:
	if soy_anfitrion and _yo_quiero_revancha and _rival_quiere_revancha:
		Red.enviar(Protocolo.crear(Protocolo.REVANCHA_OK))
		_cambiar_a(ESCENA_PARTIDA, {"modo": "red"})


func _al_recibir_mensaje(mensaje: Dictionary) -> void:
	match Protocolo.tipo_de(mensaje):
		Protocolo.REVANCHA:
			_rival_quiere_revancha = true
			if not _yo_quiero_revancha:
				_fijar_estado("¡Tu rival quiere la revancha!")
			_comprobar_revancha()
		Protocolo.REVANCHA_OK:
			if not soy_anfitrion:
				_cambiar_a(ESCENA_PARTIDA, {"modo": "red"})
		Protocolo.SALIR:
			boton_otra_vez.disabled = true
			_fijar_estado("Tu rival volvió al menú.")


func _al_desconectar(motivo: String) -> void:
	if _cambiando:
		return
	boton_otra_vez.disabled = true
	_fijar_estado(motivo)


func _fijar_estado(texto: String) -> void:
	estado.text = texto
	AnimUI.latido(estado)


func _ir_al_menu() -> void:
	if en_red:
		Red.enviar(Protocolo.crear(Protocolo.SALIR))
	Red.cerrar()
	_cambiar_a(ESCENA_MENU, {})


func _cambiar_a(ruta: String, datos: Dictionary) -> void:
	if _cambiando:
		return
	_cambiando = true
	Transicion.cambiar_escena(ruta, datos)
