class_name CamaraJuego
extends Camera3D
## Cámara de frente y ligeramente elevada, como quien mira la caja del juguete.
##
## * Encuadre adaptable: calcula el FOV para que siempre quepan «ancho_visible» y
##   «alto_visible» (unidades del mundo) alrededor del objetivo, tanto en vertical
##   (móvil) como en horizontal (navegador de escritorio).
## * Screen shake por «trauma»: sacudir() suma trauma, que decae con el tiempo; el
##   desplazamiento es trauma² para que los golpes fuertes destaquen.

@export var objetivo := Vector3(0.0, 0.95, 0.75)
@export var distancia := 7.2
@export_range(0.0, 89.0) var elevacion_grados := 24.0
@export_range(-45.0, 45.0) var rumbo_grados := 12.0
@export var ancho_visible := 3.4
@export var alto_visible := 3.6

const DECAIMIENTO_TRAUMA := 1.8
const DESPLAZAMIENTO_MAXIMO := 0.32
const GIRO_MAXIMO := deg_to_rad(3.5)
const FRECUENCIA_TEMBLOR := 28.0

var trauma := 0.0
var _rotacion_base := Vector3.ZERO
var _tiempo := 0.0


func _ready() -> void:
	get_viewport().size_changed.connect(ajustar_encuadre)
	actualizar()


## Vuelve a colocar la cámara y recalcular el FOV tras cambiar los parámetros.
func actualizar() -> void:
	colocar()
	ajustar_encuadre()


func colocar() -> void:
	var elevacion := deg_to_rad(elevacion_grados)
	var rumbo := deg_to_rad(rumbo_grados)
	var direccion := Vector3(sin(rumbo) * cos(elevacion), sin(elevacion), cos(rumbo) * cos(elevacion))
	position = objetivo + direccion * distancia
	look_at_from_position(position, objetivo, Vector3.UP)
	_rotacion_base = rotation


func ajustar_encuadre() -> void:
	var tamano := get_viewport().get_visible_rect().size
	if tamano.y <= 0.0:
		return
	var aspecto := tamano.x / tamano.y
	# FOV vertical necesario para que quepa el alto y para que quepa el ancho.
	var fov_por_alto := 2.0 * atan(alto_visible * 0.5 / distancia)
	var fov_por_ancho := 2.0 * atan(ancho_visible * 0.5 / distancia / aspecto)
	keep_aspect = Camera3D.KEEP_HEIGHT
	fov = rad_to_deg(maxf(fov_por_alto, fov_por_ancho))


func sacudir(intensidad: float) -> void:
	trauma = minf(1.0, trauma + intensidad)


func _process(delta: float) -> void:
	if trauma <= 0.0:
		return
	_tiempo += delta
	trauma = maxf(0.0, trauma - DECAIMIENTO_TRAUMA * delta)
	var fuerza := trauma * trauma
	h_offset = DESPLAZAMIENTO_MAXIMO * fuerza * sin(_tiempo * FRECUENCIA_TEMBLOR * 1.3)
	v_offset = DESPLAZAMIENTO_MAXIMO * fuerza * sin(_tiempo * FRECUENCIA_TEMBLOR + 1.7)
	rotation = _rotacion_base + Vector3(0, 0, GIRO_MAXIMO * fuerza * sin(_tiempo * FRECUENCIA_TEMBLOR * 0.8))
	if trauma <= 0.0:
		h_offset = 0.0
		v_offset = 0.0
		rotation = _rotacion_base
