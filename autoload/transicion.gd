extends CanvasLayer
## Autoload «Transicion»: cambia de escena con un barrido de color y pasa datos
## entre pantallas (por ejemplo, el resultado de la ronda).
##
## Mientras dura el cambio, la red deja de entregar mensajes (se encolan en Red)
## para que la escena saliente no «se coma» mensajes destinados a la entrante.

signal escena_cambiada

const CAPA_TRANSICION := 100
const DURACION_CUBRIR_S := 0.38
const DURACION_DESCUBRIR_S := 0.42
const SHADER_TRANSICION := preload("res://shaders/transicion.gdshader")

## Datos para la escena entrante. Se leen en su _ready().
var datos: Dictionary = {}
var ocupado := false

var _cortina: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	layer = CAPA_TRANSICION
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material = ShaderMaterial.new()
	_material.shader = SHADER_TRANSICION
	_cortina = ColorRect.new()
	_cortina.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cortina.material = _material
	_cortina.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cortina)
	# Al arrancar el juego la pantalla aparece con el mismo barrido.
	_fijar_fase(1.0)
	_fijar_progreso(0.0)
	_descubrir()


func cambiar_escena(ruta: String, nuevos_datos: Dictionary = {}) -> void:
	if ocupado:
		return
	ocupado = true
	datos = nuevos_datos
	Red.establecer_receptor(Callable())
	_cortina.mouse_filter = Control.MOUSE_FILTER_STOP
	Audio.reproducir_sfx("transicion", 1.0, 0.05)
	_fijar_fase(0.0)
	var cubrir := create_tween()
	cubrir.tween_method(_fijar_progreso, 0.0, 1.0, DURACION_CUBRIR_S) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await cubrir.finished
	var error := get_tree().change_scene_to_file(ruta)
	if error != OK:
		push_error("[Transicion] No se pudo abrir %s (error %d)" % [ruta, error])
	# El cambio de escena se aplica al final del frame: esperamos a que la nueva
	# escena esté en el árbol y haya hecho su primer _ready().
	await get_tree().process_frame
	await get_tree().process_frame
	escena_cambiada.emit()
	_fijar_fase(1.0)
	await _descubrir()
	ocupado = false


func _descubrir() -> void:
	_cortina.mouse_filter = Control.MOUSE_FILTER_STOP
	var descubrir := create_tween()
	descubrir.tween_method(_fijar_progreso, 0.0, 1.0, DURACION_DESCUBRIR_S) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await descubrir.finished
	_cortina.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _fijar_progreso(valor: float) -> void:
	_material.set_shader_parameter("progreso", valor)


func _fijar_fase(valor: float) -> void:
	_material.set_shader_parameter("fase", valor)
