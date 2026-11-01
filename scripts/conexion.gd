extends Node
## Pantalla de conexión con señalización manual (copiar y pegar códigos).
##
##  ANFITRIÓN: 1) se genera su código → lo copia y lo envía al rival
##             2) pega la respuesta del rival → «Conectar»
##  INVITADO:  1) pega el código del anfitrión → «Generar respuesta»
##             2) copia su respuesta y se la envía al anfitrión
##
## El estado visible sigue a Red.estado: «Esperando al rival...», «Conectando...», «Conectado».

const ESCENA_MENU := "res://escenas/menu.tscn"
const ESCENA_PARTIDA := "res://escenas/partida.tscn"
const PAUSA_TRAS_CONECTAR_S := 0.9
const DURACION_AVISO_COPIADO_S := 1.4
const COLOR_ESTADO_ESPERA := Color(1.0, 1.0, 1.0, 0.92)
const COLOR_ESTADO_OK := Color(0.72, 0.95, 0.5)
const COLOR_ESTADO_ERROR := Color(1.0, 0.72, 0.72)
# Cámara: el cocodrilo asoma abajo, detrás de los paneles.
const CAMARA_OBJETIVO := Vector3(0.0, 3.4, 0.4)
const CAMARA_ANCHO := 5.4
const CAMARA_ALTO := 9.0

@onready var escenario: Escenario = $Escenario
@onready var titulo: Label = %Titulo
@onready var estado_panel: PanelContainer = %Estado
@onready var estado_texto: Label = %EstadoTexto
@onready var paso_1: PanelContainer = %Paso1
@onready var paso_1_titulo: Label = %Paso1Titulo
@onready var codigo_1: TextEdit = %Codigo1
@onready var boton_pegar_1: Button = %BotonPegar1
@onready var boton_copiar_1: Button = %BotonCopiar1
@onready var boton_accion_1: Button = %BotonAccion1
@onready var paso_2: PanelContainer = %Paso2
@onready var paso_2_titulo: Label = %Paso2Titulo
@onready var codigo_2: TextEdit = %Codigo2
@onready var boton_pegar_2: Button = %BotonPegar2
@onready var boton_copiar_2: Button = %BotonCopiar2
@onready var boton_accion_2: Button = %BotonAccion2
@onready var boton_volver: Button = %BotonVolver
@onready var boton_reintentar: Button = %BotonReintentar

var es_anfitrion := true
var _estilo_estado: StyleBoxFlat
var _saliendo := false


func _ready() -> void:
	es_anfitrion = bool(Transicion.datos.get("anfitrion", true))
	var camara := escenario.camara
	camara.objetivo = CAMARA_OBJETIVO
	camara.ancho_visible = CAMARA_ANCHO
	camara.alto_visible = CAMARA_ALTO
	camara.actualizar()
	# Copia propia del estilo para poder cambiar su color.
	_estilo_estado = (estado_panel.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
	estado_panel.add_theme_stylebox_override("panel", _estilo_estado)

	for boton: Button in [boton_pegar_1, boton_copiar_1, boton_accion_1, boton_pegar_2, boton_copiar_2,
			boton_accion_2, boton_volver, boton_reintentar]:
		AnimUI.preparar_boton(boton)
	boton_volver.pressed.connect(_volver)
	boton_reintentar.pressed.connect(func() -> void:
		Transicion.cambiar_escena(scene_file_path, {"anfitrion": es_anfitrion}))
	boton_reintentar.visible = false

	Red.estado_cambiado.connect(_al_cambiar_estado)
	Red.codigo_generado.connect(_al_generar_codigo)
	Red.conectado.connect(_al_conectar)
	Red.desconectado.connect(_al_fallar)
	Red.aviso.connect(_mostrar_aviso)

	if es_anfitrion:
		_preparar_anfitrion()
	else:
		_preparar_invitado()
	await get_tree().process_frame
	AnimUI.aparecer(titulo)
	AnimUI.aparecer(estado_panel, 0.08)
	AnimUI.aparecer(paso_1, 0.16)


# --- Preparación de cada rol ---------------------------------------------------------------

func _preparar_anfitrion() -> void:
	titulo.text = "Crear partida"
	paso_1_titulo.text = "1. Envía este código a tu rival"
	codigo_1.editable = false
	codigo_1.placeholder_text = "Generando código..."
	boton_pegar_1.visible = false
	boton_accion_1.visible = false
	boton_copiar_1.text = "Copiar código"
	boton_copiar_1.disabled = true
	boton_copiar_1.pressed.connect(_copiar.bind(codigo_1, boton_copiar_1))

	paso_2_titulo.text = "2. Pega aquí la respuesta de tu rival"
	codigo_2.editable = true
	codigo_2.placeholder_text = "Mantén pulsado y pega, o usa el botón «Pegar»"
	boton_copiar_2.visible = false
	boton_pegar_2.pressed.connect(_pegar_en.bind(codigo_2))
	boton_accion_2.text = "Conectar"
	boton_accion_2.pressed.connect(_conectar_como_anfitrion)
	paso_2.visible = false
	_fijar_estado("Generando código...", COLOR_ESTADO_ESPERA)
	Red.crear_partida()


func _preparar_invitado() -> void:
	titulo.text = "Unirse"
	paso_1_titulo.text = "1. Pega el código que te envió el anfitrión"
	codigo_1.editable = true
	codigo_1.placeholder_text = "Mantén pulsado y pega, o usa el botón «Pegar»"
	boton_copiar_1.visible = false
	boton_pegar_1.pressed.connect(_pegar_en.bind(codigo_1))
	boton_accion_1.text = "Generar respuesta"
	boton_accion_1.pressed.connect(_generar_respuesta)

	paso_2_titulo.text = "2. Envía esta respuesta al anfitrión"
	codigo_2.editable = false
	boton_pegar_2.visible = false
	boton_accion_2.visible = false
	boton_copiar_2.text = "Copiar respuesta"
	boton_copiar_2.pressed.connect(_copiar.bind(codigo_2, boton_copiar_2))
	paso_2.visible = false
	_fijar_estado("Pega el código del anfitrión", COLOR_ESTADO_ESPERA)


# --- Acciones -------------------------------------------------------------------------------

func _generar_respuesta() -> void:
	if codigo_1.text.strip_edges().is_empty():
		_mostrar_aviso("Primero pega el código del anfitrión.")
		return
	if Red.unirse(codigo_1.text):
		boton_accion_1.disabled = true
		boton_pegar_1.disabled = true
		codigo_1.editable = false


func _conectar_como_anfitrion() -> void:
	if codigo_2.text.strip_edges().is_empty():
		_mostrar_aviso("Primero pega la respuesta de tu rival.")
		return
	if Red.aceptar_respuesta(codigo_2.text):
		boton_accion_2.disabled = true
		boton_pegar_2.disabled = true
		codigo_2.editable = false


func _copiar(campo: TextEdit, boton: Button) -> void:
	Portapapeles.copiar(campo.text)
	var texto_original := boton.text
	boton.text = "¡Copiado!"
	AnimUI.latido(boton)
	await get_tree().create_timer(DURACION_AVISO_COPIADO_S).timeout
	if is_instance_valid(boton):
		boton.text = texto_original


func _pegar_en(campo: TextEdit) -> void:
	Portapapeles.pegar(func(texto: String) -> void:
		if is_instance_valid(campo):
			campo.text = RedP2P.limpiar_codigo(texto)
			AnimUI.latido(campo, 1.04))


func _volver() -> void:
	_saliendo = true
	Red.cerrar()
	Transicion.cambiar_escena(ESCENA_MENU)


# --- Señales de Red -------------------------------------------------------------------------

func _al_generar_codigo(codigo: String) -> void:
	if es_anfitrion:
		codigo_1.text = codigo
		boton_copiar_1.disabled = false
		AnimUI.latido(boton_copiar_1)
	else:
		codigo_2.text = codigo
	paso_2.visible = true
	AnimUI.aparecer(paso_2)


func _al_cambiar_estado(nuevo: RedP2P.Estado) -> void:
	match nuevo:
		RedP2P.Estado.GENERANDO_CODIGO:
			_fijar_estado("Generando código..." if es_anfitrion else "Generando respuesta...",
				COLOR_ESTADO_ESPERA)
		RedP2P.Estado.ESPERANDO_RIVAL:
			_fijar_estado("Esperando al rival...", COLOR_ESTADO_ESPERA)
		RedP2P.Estado.CONECTANDO:
			_fijar_estado("Conectando...", COLOR_ESTADO_ESPERA)
		RedP2P.Estado.CONECTADO:
			_fijar_estado("¡Conectado!", COLOR_ESTADO_OK)


func _al_conectar() -> void:
	Audio.reproducir_sfx("conectado")
	await get_tree().create_timer(PAUSA_TRAS_CONECTAR_S).timeout
	if not _saliendo and Red.esta_conectado():
		Transicion.cambiar_escena(ESCENA_PARTIDA, {"modo": "red"})


func _al_fallar(motivo: String) -> void:
	if _saliendo:
		return
	_fijar_estado(motivo, COLOR_ESTADO_ERROR)
	boton_reintentar.visible = true
	AnimUI.aparecer(boton_reintentar)


func _mostrar_aviso(mensaje: String) -> void:
	_fijar_estado(mensaje, COLOR_ESTADO_ERROR)


func _fijar_estado(texto: String, color: Color) -> void:
	estado_texto.text = texto
	_estilo_estado.bg_color = color
	AnimUI.latido(estado_panel, 1.06)
