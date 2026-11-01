class_name Diente
extends Area3D
## Un diente presionable. El Area3D recibe el raycast del dedo/ratón (lo lanza
## partida.gd); las animaciones se aplican al nodo «Pivote», que está en la base
## del diente, para que el squash & stretch se vea anclado a la encía.

## Índice del diente (0 = izquierda ... 11 = derecha). Lo usa la red.
@export var indice := 0

const ESCALA_REPOSO := Vector3.ONE
const ESCALA_APUNTADO := Vector3(1.18, 1.18, 1.18)
const DURACION_APUNTADO := 0.22
const REALCE_APUNTADO := 0.55
const REALCE_RIVAL := 0.4
const COLOR_REALCE_PROPIO := Color(1.0, 0.92, 0.35)
const COLOR_REALCE_RIVAL := Color(1.0, 0.45, 0.55)
const HUNDIMIENTO_PRESION := 0.06
const ANGULO_SACUDIDA := deg_to_rad(10.0)
const SACUDIDAS := 4
const DURACION_SACUDIDA := 0.24
const ALTURA_SALTO_SEGURO := 0.18
const DURACION_SALTO_SEGURO := 0.45
const DURACION_A_GRIS := 0.35
const COLOR_MORDEDOR := Color(0.9, 0.1, 0.1)

var usado := false
var apuntado := false

@onready var pivote: Node3D = $Pivote
@onready var malla: MeshInstance3D = $Pivote/Malla

var _material: ShaderMaterial
var _realce := 0.0
var _tween_escala: Tween
var _tween_movimiento: Tween
var _tween_realce: Tween


func _ready() -> void:
	# Material propio: cada diente se pone gris o brilla por separado.
	_material = (malla.material_override as ShaderMaterial).duplicate()
	malla.material_override = _material
	_fijar_realce(0.0)
	_fijar_gris(0.0)
	_fijar_emision(Color.BLACK)


## Cursor/dedo encima: crece un poco y rebota (squash & stretch).
func apuntar(activo: bool) -> void:
	if apuntado == activo:
		return
	apuntado = activo
	if usado:
		return
	_matar(_tween_escala)
	_tween_escala = create_tween()
	if activo:
		_tween_escala.tween_property(pivote, "scale", Vector3(0.88, 1.32, 0.88), DURACION_APUNTADO * 0.35) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_tween_escala.tween_property(pivote, "scale", Vector3(1.26, 1.06, 1.26), DURACION_APUNTADO * 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_tween_escala.tween_property(pivote, "scale", ESCALA_APUNTADO, DURACION_APUNTADO * 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_tween_escala.tween_property(pivote, "scale", ESCALA_REPOSO, DURACION_APUNTADO) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_animar_realce(REALCE_APUNTADO if activo else 0.0, COLOR_REALCE_PROPIO)


## El rival tiene el cursor encima (solo un brillo suave de otro color).
func marcar_apuntado_rival(activo: bool) -> void:
	if usado or apuntado:
		return
	_animar_realce(REALCE_RIVAL if activo else 0.0, COLOR_REALCE_RIVAL)


## Al presionar: se hunde y da una sacudida breve.
func presionar() -> void:
	_matar(_tween_movimiento)
	_tween_movimiento = create_tween()
	_tween_movimiento.tween_property(pivote, "position:y", -HUNDIMIENTO_PRESION, 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var paso := DURACION_SACUDIDA / SACUDIDAS
	for i in SACUDIDAS:
		var amortiguado := ANGULO_SACUDIDA * (1.0 - float(i) / SACUDIDAS)
		var signo := 1.0 if i % 2 == 0 else -1.0
		_tween_movimiento.tween_property(pivote, "rotation:z", amortiguado * signo, paso) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween_movimiento.tween_property(pivote, "rotation:z", 0.0, paso).set_trans(Tween.TRANS_SINE)


## Diente seguro: se vuelve gris, da un saltito y aterriza con rebote.
func marcar_seguro() -> void:
	usado = true
	apuntado = false
	_animar_realce(0.0, COLOR_REALCE_PROPIO)
	var gris := create_tween()
	gris.tween_method(_fijar_gris, 0.0, 1.0, DURACION_A_GRIS).set_trans(Tween.TRANS_SINE)
	_matar(_tween_movimiento)
	_matar(_tween_escala)
	pivote.rotation = Vector3.ZERO
	_tween_movimiento = create_tween()
	_tween_movimiento.tween_property(pivote, "position:y", ALTURA_SALTO_SEGURO, DURACION_SALTO_SEGURO * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween_movimiento.tween_property(pivote, "position:y", -HUNDIMIENTO_PRESION * 0.5,
		DURACION_SALTO_SEGURO * 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_tween_escala = create_tween()
	_tween_escala.tween_property(pivote, "scale", Vector3(0.9, 1.15, 0.9), DURACION_SALTO_SEGURO * 0.4)
	_tween_escala.tween_property(pivote, "scale", Vector3(1.15, 0.8, 1.15), DURACION_SALTO_SEGURO * 0.25)
	_tween_escala.tween_property(pivote, "scale", Vector3(0.92, 0.92, 0.92), DURACION_SALTO_SEGURO * 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Diente mordedor: destella en rojo.
func marcar_mordedor() -> void:
	usado = true
	apuntado = false
	_matar(_tween_realce)
	_tween_realce = create_tween().set_loops(3)
	_tween_realce.tween_method(_fijar_emision, Color.BLACK, COLOR_MORDEDOR, 0.12)
	_tween_realce.tween_method(_fijar_emision, COLOR_MORDEDOR, Color.BLACK, 0.18)


func reiniciar() -> void:
	usado = false
	apuntado = false
	_matar(_tween_escala)
	_matar(_tween_movimiento)
	_matar(_tween_realce)
	pivote.position = Vector3.ZERO
	pivote.rotation = Vector3.ZERO
	pivote.scale = ESCALA_REPOSO
	_fijar_gris(0.0)
	_fijar_emision(Color.BLACK)
	_fijar_realce(0.0)


## Punto (en mundo) donde mostrar el globo de texto.
func punta_global() -> Vector3:
	return malla.global_position + malla.global_transform.basis.y.normalized() * 0.2


func _animar_realce(valor: float, color: Color) -> void:
	_matar(_tween_realce)
	_material.set_shader_parameter("color_realce", color)
	_tween_realce = create_tween()
	_tween_realce.tween_method(_fijar_realce, _realce, valor, 0.15)


func _fijar_realce(valor: float) -> void:
	_realce = valor
	_material.set_shader_parameter("realce", valor)


func _fijar_gris(valor: float) -> void:
	_material.set_shader_parameter("mezcla_gris", valor)


func _fijar_emision(color: Color) -> void:
	_material.set_shader_parameter("color_emision", color)


func _matar(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
