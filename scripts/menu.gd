extends Node
## Menú principal: logotipo animado, cocodrilo en reposo y botones.

const ESCENA_CONEXION := "res://escenas/conexion.tscn"
const ESCENA_PARTIDA := "res://escenas/partida.tscn"
const TEXTO_LINEA_1 := "Cocodrilo"
const TEXTO_LINEA_2 := "Dentista"
const COLOR_LINEA_2 := Color(1.0, 0.42, 0.42)
const COLOR_CONTORNO_LINEA_2 := Color(0.45, 0.06, 0.12)
const TAMANO_LETRA_LINEA_2 := 76
const RETRASO_ENTRE_LETRAS := 0.045
const RETRASO_BOTONES := 0.6
const ONDA_VELOCIDAD := 2.4
const ONDA_DESFASE := 0.55
const ONDA_ANGULO := 0.07
# Cámara del menú: cocodrilo entre el logotipo y los botones.
const CAMARA_OBJETIVO := Vector3(0.0, 1.05, 0.4)
const CAMARA_DISTANCIA := 7.6
const CAMARA_ELEVACION := 20.0
const CAMARA_RUMBO := 20.0
const CAMARA_ANCHO := 4.6
const CAMARA_ALTO := 6.2

@onready var escenario: Escenario = $Escenario
@onready var linea_1: HBoxContainer = %LineaCocodrilo
@onready var linea_2: HBoxContainer = %LineaDentista
@onready var botones: VBoxContainer = %Botones
@onready var boton_crear: Button = %BotonCrear
@onready var boton_unirse: Button = %BotonUnirse
@onready var boton_practicar: Button = %BotonPracticar
@onready var boton_opciones: Button = %BotonOpciones
@onready var aviso_sonido: Label = %AvisoSonido
@onready var velo: ColorRect = %Velo
@onready var panel_opciones: PanelContainer = %PanelOpciones
@onready var slider_musica: HSlider = %SliderMusica
@onready var slider_efectos: HSlider = %SliderEfectos
@onready var boton_cerrar_opciones: Button = %BotonCerrarOpciones
@onready var etiqueta_version: Label = %Version

var _letras: Array[Label] = []
var _tiempo := 0.0


func _ready() -> void:
	# Volver al menú siempre deja la red limpia.
	Red.cerrar()
	Audio.reproducir_musica("menu")
	var camara := escenario.camara
	camara.objetivo = CAMARA_OBJETIVO
	camara.distancia = CAMARA_DISTANCIA
	camara.elevacion_grados = CAMARA_ELEVACION
	camara.rumbo_grados = CAMARA_RUMBO
	camara.ancho_visible = CAMARA_ANCHO
	camara.alto_visible = CAMARA_ALTO
	camara.actualizar()

	_crear_logotipo()
	for boton: Button in [boton_crear, boton_unirse, boton_practicar, boton_opciones, boton_cerrar_opciones]:
		AnimUI.preparar_boton(boton)
	boton_crear.pressed.connect(_ir_a_conexion.bind(true))
	boton_unirse.pressed.connect(_ir_a_conexion.bind(false))
	boton_practicar.pressed.connect(func() -> void:
		Transicion.cambiar_escena(ESCENA_PARTIDA, {"modo": "practica"}))
	boton_opciones.pressed.connect(_abrir_opciones)
	boton_cerrar_opciones.pressed.connect(_cerrar_opciones)
	slider_musica.value = Audio.volumen_musica
	slider_efectos.value = Audio.volumen_sfx
	slider_musica.value_changed.connect(Audio.fijar_volumen_musica)
	slider_efectos.value_changed.connect(func(valor: float) -> void:
		Audio.fijar_volumen_sfx(valor)
		Audio.reproducir_sfx("clic_diente"))
	etiqueta_version.text = "v" + str(ProjectSettings.get_setting("application/config/version", "1.0"))

	# En el navegador el audio espera a la primera interacción.
	aviso_sonido.visible = not Audio.desbloqueado
	Audio.audio_desbloqueado.connect(func() -> void: AnimUI.desaparecer(aviso_sonido))

	await get_tree().process_frame
	_animar_entrada()


func _process(delta: float) -> void:
	# Onda continua del logotipo (rotación; la escala la usa la animación de entrada).
	_tiempo += delta
	for i in _letras.size():
		_letras[i].rotation = sin(_tiempo * ONDA_VELOCIDAD - i * ONDA_DESFASE) * ONDA_ANGULO


func _crear_logotipo() -> void:
	for caracter in TEXTO_LINEA_1:
		_letras.append(_crear_letra(caracter, linea_1))
	for caracter in TEXTO_LINEA_2:
		var letra := _crear_letra(caracter, linea_2)
		letra.add_theme_color_override("font_color", COLOR_LINEA_2)
		letra.add_theme_color_override("font_outline_color", COLOR_CONTORNO_LINEA_2)
		letra.add_theme_font_size_override("font_size", TAMANO_LETRA_LINEA_2)
		_letras.append(letra)


func _crear_letra(caracter: String, contenedor: HBoxContainer) -> Label:
	var letra := Label.new()
	letra.text = caracter
	letra.theme_type_variation = &"LetraLogo"
	letra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	letra.scale = Vector2.ZERO
	contenedor.add_child(letra)
	return letra


func _animar_entrada() -> void:
	for i in _letras.size():
		AnimUI.aparecer(_letras[i], i * RETRASO_ENTRE_LETRAS, 0.55)
	var retraso := RETRASO_BOTONES
	for boton: Control in [boton_crear, boton_unirse, boton_practicar.get_parent()]:
		AnimUI.aparecer(boton, retraso)
		retraso += 0.1


func _ir_a_conexion(como_anfitrion: bool) -> void:
	Transicion.cambiar_escena(ESCENA_CONEXION, {"anfitrion": como_anfitrion})


func _abrir_opciones() -> void:
	velo.visible = true
	velo.modulate.a = 0.0
	velo.create_tween().tween_property(velo, "modulate:a", 1.0, 0.2)
	panel_opciones.visible = true
	AnimUI.aparecer(panel_opciones)


func _cerrar_opciones() -> void:
	var tween := AnimUI.desaparecer(panel_opciones)
	velo.create_tween().tween_property(velo, "modulate:a", 0.0, 0.2)
	await tween.finished
	panel_opciones.visible = false
	velo.visible = false
