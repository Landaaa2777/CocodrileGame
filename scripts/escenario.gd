class_name Escenario
extends Node3D
## Escenario 3D compartido por menú, partida y resultado: luz, cielo, cámara,
## cocodrilo y partículas. También hace que los ojos sigan al cursor o al dedo.

## Plano imaginario delante del cocodrilo donde se proyecta el cursor para
## calcular hacia dónde miran los ojos.
const PLANO_MIRADA := Plane(Vector3(0, 0, 1), 2.6)
const INTENSIDAD_SACUDIDA_MORDIDA := 0.85

@export var seguir_cursor := true

@onready var cocodrilo: Cocodrilo = $Cocodrilo
@onready var camara: CamaraJuego = $Camara
@onready var confeti: CPUParticles3D = $Confeti
@onready var chispas: CPUParticles3D = $Chispas


func _input(evento: InputEvent) -> void:
	if not seguir_cursor:
		return
	var posicion: Vector2
	if evento is InputEventMouseMotion or evento is InputEventMouseButton:
		posicion = evento.position
	elif evento is InputEventScreenDrag or evento is InputEventScreenTouch:
		posicion = evento.position
	else:
		return
	var punto: Variant = punto_en_plano_mirada(posicion)
	if punto != null:
		cocodrilo.mirar_hacia(punto)


func punto_en_plano_mirada(posicion_pantalla: Vector2) -> Variant:
	var origen := camara.project_ray_origin(posicion_pantalla)
	var direccion := camara.project_ray_normal(posicion_pantalla)
	return PLANO_MIRADA.intersects_ray(origen, direccion)


func lanzar_confeti() -> void:
	confeti.restart()
	confeti.emitting = true


## Chispas y sacudida de cámara en el punto del impacto de la mordida.
func impacto(posicion: Vector3) -> void:
	chispas.global_position = posicion
	chispas.restart()
	chispas.emitting = true
	camara.sacudir(INTENSIDAD_SACUDIDA_MORDIDA)
