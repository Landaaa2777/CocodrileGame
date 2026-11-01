class_name Cocodrilo
extends Node3D
## Cocodrilo reutilizable: animaciones de «vida» (respiración, parpadeo, cola,
## mirada), mordida con anticipación y poses finales de victoria y derrota.
##
## Las animaciones puntuales usan Tween con curvas de aceleración. Las continuas
## (respiración, cola, temblor) se calculan en _process con senos para que
## nunca haya saltos.
##
## Si sustituyes las primitivas por un .glb, conserva estos nombres de nodos:
##   Pose/Respiracion/{Cabeza/{Maxilar, Mandibula/Dientes, Ojos/OjoIzq|OjoDer}, Cola/PuntaCola}

## Se emite en el instante en que las mandíbulas chocan (para sacudir la cámara, etc.).
signal impacto_mordida

enum Expresion { NORMAL, TENSO, FELIZ, MAREADO, SORPRENDIDO }

# Boca (coinciden con tools/generar_cocodrilo.py)
const ANGULO_MAXILAR_ABIERTO := deg_to_rad(-27.0)
const ANGULO_MANDIBULA_ABIERTA := deg_to_rad(12.0)
const ANGULO_MAXILAR_CERRADO := deg_to_rad(2.0)
const ANGULO_MANDIBULA_CERRADA := deg_to_rad(-2.0)
const ANGULO_MAXILAR_FELIZ := deg_to_rad(-36.0)
const ANGULO_REBOTE_MORDIDA := deg_to_rad(-6.0)
const DURACION_ABRIR_BOCA := 0.7

# Mordida
const DURACION_ANTICIPACION := 0.55
const ANGULO_ANTICIPACION_MAXILAR := deg_to_rad(-6.0)   # se abre un poco más (toma impulso)
const FRACCION_SUBIDA_MANDIBULA := 0.3                  # la mandíbula sube un poco antes de cerrar
const DURACION_MORDIDA := 0.1                           # entre 0.08 y 0.12 s
const DURACION_REBOTE_MORDIDA := 0.14
const DURACION_SQUASH := 0.3
const ESCALA_SQUASH := Vector3(1.16, 0.82, 1.16)
const ESCALA_STRETCH := Vector3(0.94, 1.08, 0.94)
const ESCALA_TENSION_CABEZA := Vector3(1.05, 0.95, 1.03)
const TEMBLOR_ANTICIPACION := 0.025

# Vida
const PERIODO_RESPIRACION := 3.2
const PERIODO_RESPIRACION_TENSO := 1.4
const AMPLITUD_RESPIRACION := 0.022
const PERIODO_COLA := 2.6
const AMPLITUD_COLA := deg_to_rad(13.0)
const DESFASE_PUNTA_COLA := 1.1
const FACTOR_PUNTA_COLA := 1.5
const INTERVALO_PARPADEO_MIN := 2.0
const INTERVALO_PARPADEO_MAX := 5.0
const DURACION_PARPADEO := 0.16
const PROBABILIDAD_DOBLE_PARPADEO := 0.2

# Párpados (giro en X del pivote «Parpado»; 90° = ojo cerrado)
const PARPADO_ABIERTO := deg_to_rad(-62.0)
const PARPADO_MUY_ABIERTO := deg_to_rad(-80.0)
const PARPADO_ENTRECERRADO := deg_to_rad(8.0)
const PARPADO_FELIZ := deg_to_rad(-25.0)
const PARPADO_CERRADO := deg_to_rad(88.0)

# Mirada
const SUAVIZADO_MIRADA := 9.0
const DILATACION_NORMAL := 1.0
const DILATACION_FELIZ := 1.2
const DILATACION_SORPRESA := 0.7

# Poses finales
const DURACION_ENTRADA_POSE := 0.7
const ALTURA_SALTO_FELIZ := 0.35
const PERIODO_SALTO_FELIZ := 0.55
const INCLINACION_MAREO := deg_to_rad(12.0)
const PERIODO_MAREO := 1.6

@onready var pose: Node3D = $Pose
@onready var respiracion: Node3D = $Pose/Respiracion
@onready var cabeza: Node3D = $Pose/Respiracion/Cabeza
@onready var maxilar: Node3D = $Pose/Respiracion/Cabeza/Maxilar
@onready var mandibula: Node3D = $Pose/Respiracion/Cabeza/Mandibula
@onready var cola: Node3D = $Pose/Respiracion/Cola
@onready var punta_cola: Node3D = $Pose/Respiracion/Cola/PuntaCola
@onready var contenedor_dientes: Node3D = $Pose/Respiracion/Cabeza/Mandibula/Dientes
@onready var _ojos: Array[Node3D] = [
	$Pose/Respiracion/Cabeza/Ojos/OjoIzq as Node3D,
	$Pose/Respiracion/Cabeza/Ojos/OjoDer as Node3D,
]

var expresion: Expresion = Expresion.NORMAL
## 0..1: acelera la respiración y la cola conforme se acerca la mordida.
var tension := 0.0

var _tiempo := 0.0
var _fase_respiracion := 0.0
var _fase_cola := 0.0
var _globos: Array[MeshInstance3D] = []
var _materiales_ojo: Array[ShaderMaterial] = []
var _parpados: Array[Node3D] = []
var _marcas_x: Array[Node3D] = []
var _mirada_actual: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _objetivo_mirada := Vector3.ZERO
var _mirando := false
var _temblor := 0.0
var _posicion_cabeza := Vector3.ZERO
var _rotacion_base_cola := 0.0
var _rotacion_base_punta := 0.0
var _temporizador_parpadeo: Timer
var _tween_boca: Tween
var _tween_parpados: Tween
var _tween_pose: Tween
var _tween_bucle: Tween


func _ready() -> void:
	for ojo in _ojos:
		var globo: MeshInstance3D = ojo.get_node("Globo")
		# Cada ojo necesita su propio material para mover su pupila.
		var material: ShaderMaterial = (globo.material_override as ShaderMaterial).duplicate()
		globo.material_override = material
		_globos.append(globo)
		_materiales_ojo.append(material)
		_parpados.append(ojo.get_node("Parpado") as Node3D)
		_marcas_x.append(ojo.get_node("MarcaX") as Node3D)
	_posicion_cabeza = cabeza.position
	_rotacion_base_cola = cola.rotation.y
	_rotacion_base_punta = punta_cola.rotation.y
	_fase_respiracion = randf() * TAU
	_temporizador_parpadeo = Timer.new()
	_temporizador_parpadeo.one_shot = true
	_temporizador_parpadeo.timeout.connect(_al_tocar_parpadeo)
	add_child(_temporizador_parpadeo)
	_programar_parpadeo()
	_aplicar_parpados(PARPADO_ABIERTO)


func _process(delta: float) -> void:
	_tiempo += delta
	# Respiración: la escala Y oscila; X/Z compensan un poco para conservar el volumen.
	var periodo := lerpf(PERIODO_RESPIRACION, PERIODO_RESPIRACION_TENSO, tension)
	_fase_respiracion = fmod(_fase_respiracion + delta * TAU / periodo, TAU)
	var onda := sin(_fase_respiracion)
	respiracion.scale = Vector3(1.0 - AMPLITUD_RESPIRACION * 0.4 * onda, 1.0 + AMPLITUD_RESPIRACION * onda,
		1.0 - AMPLITUD_RESPIRACION * 0.4 * onda)
	# Cola: dos segmentos con desfase para que el movimiento parezca un látigo.
	_fase_cola = fmod(_fase_cola + delta * TAU / PERIODO_COLA * (1.0 + tension), TAU)
	cola.rotation.y = _rotacion_base_cola + sin(_fase_cola) * AMPLITUD_COLA
	punta_cola.rotation.y = _rotacion_base_punta \
		+ sin(_fase_cola - DESFASE_PUNTA_COLA) * AMPLITUD_COLA * FACTOR_PUNTA_COLA
	# Temblor de la cabeza (anticipación de la mordida).
	if _temblor > 0.0:
		cabeza.position = _posicion_cabeza + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _temblor
	_actualizar_mirada(delta)


# --- Mirada -----------------------------------------------------------------------

## Las pupilas siguen un punto del mundo (cursor o dedo proyectado en 3D).
func mirar_hacia(punto_global: Vector3) -> void:
	_objetivo_mirada = punto_global
	_mirando = true


func dejar_de_mirar() -> void:
	_mirando = false


func _actualizar_mirada(delta: float) -> void:
	var suavizado := 1.0 - exp(-SUAVIZADO_MIRADA * delta)
	for i in _globos.size():
		var objetivo := Vector2.ZERO
		if _mirando:
			# Dirección al objetivo en el espacio local del ojo: x/y desplazan la pupila.
			var local := _globos[i].global_transform.affine_inverse() * _objetivo_mirada
			if local.length_squared() > 0.0001:
				var direccion := local.normalized()
				objetivo = Vector2(direccion.x, direccion.y).limit_length(1.0)
		_mirada_actual[i] = _mirada_actual[i].lerp(objetivo, suavizado)
		_materiales_ojo[i].set_shader_parameter("mirada", _mirada_actual[i])


# --- Párpados y expresiones -----------------------------------------------------------

func fijar_expresion(nueva: Expresion) -> void:
	expresion = nueva
	var mareado := nueva == Expresion.MAREADO
	for i in _ojos.size():
		_marcas_x[i].visible = mareado
		_materiales_ojo[i].set_shader_parameter("mostrar_pupila", 0.0 if mareado else 1.0)
	var dilatacion := DILATACION_NORMAL
	match nueva:
		Expresion.FELIZ:
			dilatacion = DILATACION_FELIZ
		Expresion.SORPRENDIDO:
			dilatacion = DILATACION_SORPRESA
	for material in _materiales_ojo:
		material.set_shader_parameter("dilatacion", dilatacion)
	if mareado:
		for marca in _marcas_x:
			marca.scale = Vector3.ZERO
			create_tween().tween_property(marca, "scale", Vector3.ONE, 0.35) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_animar_parpados(_angulo_parpado_expresion(), 0.18)


func _angulo_parpado_expresion() -> float:
	match expresion:
		Expresion.TENSO:
			return PARPADO_ENTRECERRADO
		Expresion.FELIZ:
			return PARPADO_FELIZ
		Expresion.SORPRENDIDO:
			return PARPADO_MUY_ABIERTO
	return PARPADO_ABIERTO


func parpadear() -> void:
	if expresion == Expresion.MAREADO or expresion == Expresion.TENSO:
		return
	var abierto := _angulo_parpado_expresion()
	_matar(_tween_parpados)
	_tween_parpados = create_tween()
	_tween_parpados.tween_method(_aplicar_parpados, abierto, PARPADO_CERRADO, DURACION_PARPADEO * 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween_parpados.tween_method(_aplicar_parpados, PARPADO_CERRADO, abierto, DURACION_PARPADEO * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _animar_parpados(angulo: float, duracion: float) -> void:
	_matar(_tween_parpados)
	_tween_parpados = create_tween()
	_tween_parpados.tween_method(_aplicar_parpados, _parpados[0].rotation.x, angulo, duracion) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _aplicar_parpados(angulo: float) -> void:
	for parpado in _parpados:
		parpado.rotation.x = angulo


func _programar_parpadeo() -> void:
	_temporizador_parpadeo.start(randf_range(INTERVALO_PARPADEO_MIN, INTERVALO_PARPADEO_MAX))


func _al_tocar_parpadeo() -> void:
	parpadear()
	if randf() < PROBABILIDAD_DOBLE_PARPADEO:
		get_tree().create_timer(DURACION_PARPADEO * 1.6).timeout.connect(parpadear)
	_programar_parpadeo()


# --- Boca ---------------------------------------------------------------------------

func abrir_boca(instantaneo: bool = false) -> void:
	_matar(_tween_boca)
	if instantaneo:
		maxilar.rotation.x = ANGULO_MAXILAR_ABIERTO
		mandibula.rotation.x = ANGULO_MANDIBULA_ABIERTA
		return
	# Apertura elástica: se pasa un poco y vuelve, como un muelle.
	_tween_boca = create_tween().set_parallel(true)
	_tween_boca.tween_property(maxilar, "rotation:x", ANGULO_MAXILAR_ABIERTO, DURACION_ABRIR_BOCA) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_tween_boca.tween_property(mandibula, "rotation:x", ANGULO_MANDIBULA_ABIERTA, DURACION_ABRIR_BOCA) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Anticipación: la cabeza se tensa y tiembla, los ojos se entrecierran, el maxilar
## toma impulso hacia arriba y la mandíbula sube un poco. Se puede «await»-ear.
func anticipar_mordida() -> void:
	fijar_expresion(Expresion.TENSO)
	_temblor = TEMBLOR_ANTICIPACION
	_matar(_tween_boca)
	var subida := lerpf(ANGULO_MANDIBULA_ABIERTA, ANGULO_MANDIBULA_CERRADA, FRACCION_SUBIDA_MANDIBULA)
	_tween_boca = create_tween().set_parallel(true)
	_tween_boca.tween_property(maxilar, "rotation:x", ANGULO_MAXILAR_ABIERTO + ANGULO_ANTICIPACION_MAXILAR,
		DURACION_ANTICIPACION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween_boca.tween_property(mandibula, "rotation:x", subida, DURACION_ANTICIPACION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween_boca.tween_property(cabeza, "scale", ESCALA_TENSION_CABEZA, DURACION_ANTICIPACION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _tween_boca.finished


## Mordida: cierre muy rápido con aceleración (EASE_IN), impacto, pequeño rebote
## y squash & stretch de todo el cuerpo. Se puede «await»-ear.
func morder() -> void:
	_matar(_tween_boca)
	_tween_boca = create_tween().set_parallel(true)
	_tween_boca.tween_property(maxilar, "rotation:x", ANGULO_MAXILAR_CERRADO, DURACION_MORDIDA) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_tween_boca.tween_property(mandibula, "rotation:x", ANGULO_MANDIBULA_CERRADA, DURACION_MORDIDA) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	await _tween_boca.finished
	_temblor = 0.0
	cabeza.position = _posicion_cabeza
	impacto_mordida.emit()
	# Rebote: las mandíbulas se separan un pelín y vuelven a cerrarse.
	_tween_boca = create_tween()
	_tween_boca.tween_property(maxilar, "rotation:x", ANGULO_MAXILAR_CERRADO + ANGULO_REBOTE_MORDIDA,
		DURACION_REBOTE_MORDIDA * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween_boca.tween_property(maxilar, "rotation:x", ANGULO_MAXILAR_CERRADO, DURACION_REBOTE_MORDIDA * 0.6) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	# Squash & stretch (0.3 s): se aplasta con el golpe, se estira y vuelve.
	_matar(_tween_pose)
	_tween_pose = create_tween()
	_tween_pose.tween_property(pose, "scale", ESCALA_SQUASH, DURACION_SQUASH * 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween_pose.tween_property(pose, "scale", ESCALA_STRETCH, DURACION_SQUASH * 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween_pose.tween_property(pose, "scale", Vector3.ONE, DURACION_SQUASH * 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var cabeza_tween := create_tween()
	cabeza_tween.tween_property(cabeza, "scale", Vector3.ONE, DURACION_SQUASH).set_trans(Tween.TRANS_ELASTIC) \
		.set_ease(Tween.EASE_OUT)
	await _tween_pose.finished


## Pequeño sobresalto cuando un diente resulta seguro.
func alivio() -> void:
	_temblor = 0.0
	cabeza.position = _posicion_cabeza
	fijar_expresion(Expresion.SORPRENDIDO)
	abrir_boca()
	var tween := create_tween()
	tween.tween_property(cabeza, "scale", Vector3(0.97, 1.05, 0.97), 0.1).set_trans(Tween.TRANS_SINE)
	tween.tween_property(cabeza, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_callback(fijar_expresion.bind(Expresion.NORMAL))


# --- Poses finales ---------------------------------------------------------------------

## Victoria: entra rebotando, boca muy abierta, ojos felices y saltitos.
func pose_feliz() -> void:
	reiniciar()
	fijar_expresion(Expresion.FELIZ)
	pose.scale = Vector3(0.4, 0.4, 0.4)
	_matar(_tween_pose)
	_tween_pose = create_tween().set_parallel(true)
	_tween_pose.tween_property(pose, "scale", Vector3.ONE, DURACION_ENTRADA_POSE) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_tween_pose.tween_property(maxilar, "rotation:x", ANGULO_MAXILAR_FELIZ, DURACION_ENTRADA_POSE) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _tween_pose.finished
	_matar(_tween_bucle)
	_tween_bucle = create_tween().set_loops()
	_tween_bucle.tween_property(pose, "position:y", ALTURA_SALTO_FELIZ, PERIODO_SALTO_FELIZ * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween_bucle.tween_property(pose, "position:y", 0.0, PERIODO_SALTO_FELIZ * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween_bucle.tween_property(pose, "scale", ESCALA_SQUASH.lerp(Vector3.ONE, 0.5), 0.08)
	_tween_bucle.tween_property(pose, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK)


## Derrota: cae desde arriba, se aplasta al aterrizar, ojos en X y balanceo mareado.
func pose_derrota() -> void:
	reiniciar()
	fijar_expresion(Expresion.MAREADO)
	maxilar.rotation.x = ANGULO_MAXILAR_CERRADO
	mandibula.rotation.x = ANGULO_MANDIBULA_CERRADA
	pose.position.y = 3.0
	_matar(_tween_pose)
	_tween_pose = create_tween()
	_tween_pose.tween_property(pose, "position:y", 0.0, DURACION_ENTRADA_POSE * 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween_pose.tween_property(pose, "scale", ESCALA_SQUASH, 0.08)
	_tween_pose.tween_property(pose, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC) \
		.set_ease(Tween.EASE_OUT)
	await _tween_pose.finished
	var boca := create_tween()
	boca.tween_property(maxilar, "rotation:x", deg_to_rad(-12.0), 0.4).set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	_matar(_tween_bucle)
	_tween_bucle = create_tween().set_loops()
	_tween_bucle.tween_property(cabeza, "rotation:z", INCLINACION_MAREO, PERIODO_MAREO * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween_bucle.tween_property(cabeza, "rotation:z", -INCLINACION_MAREO, PERIODO_MAREO * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Vuelve al estado de juego: boca abierta, sin temblor, dientes nuevos.
func reiniciar() -> void:
	_matar(_tween_bucle)
	_matar(_tween_pose)
	_temblor = 0.0
	tension = 0.0
	cabeza.position = _posicion_cabeza
	cabeza.rotation = Vector3.ZERO
	cabeza.scale = Vector3.ONE
	pose.position = Vector3.ZERO
	pose.scale = Vector3.ONE
	fijar_expresion(Expresion.NORMAL)
	for diente in obtener_dientes():
		diente.reiniciar()


# --- Dientes -----------------------------------------------------------------------------

func obtener_dientes() -> Array[Diente]:
	var dientes: Array[Diente] = []
	for hijo in contenedor_dientes.get_children():
		if hijo is Diente:
			dientes.append(hijo)
	dientes.sort_custom(func(a: Diente, b: Diente) -> bool: return a.indice < b.indice)
	return dientes


func obtener_diente(indice: int) -> Diente:
	for diente in obtener_dientes():
		if diente.indice == indice:
			return diente
	return null


func _matar(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
