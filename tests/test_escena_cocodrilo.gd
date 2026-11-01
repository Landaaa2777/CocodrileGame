extends "res://tests/caso_prueba.gd"
## Comprueba que la escena del cocodrilo tiene los nodos que usan los scripts
## y exactamente TOTAL_DIENTES dientes con índices 0..TOTAL_DIENTES-1.

const Reglas := preload("res://scripts/reglas_juego.gd")
const ESCENA := preload("res://escenas/cocodrilo.tscn")
const NODOS_OBLIGATORIOS := [
	"Pose", "Pose/Respiracion", "Pose/Respiracion/Cabeza", "Pose/Respiracion/Cabeza/Maxilar",
	"Pose/Respiracion/Cabeza/Mandibula", "Pose/Respiracion/Cabeza/Mandibula/Dientes",
	"Pose/Respiracion/Cabeza/Ojos/OjoIzq/Globo", "Pose/Respiracion/Cabeza/Ojos/OjoDer/Parpado",
	"Pose/Respiracion/Cabeza/Ojos/OjoIzq/MarcaX", "Pose/Respiracion/Cola/PuntaCola",
]


func test_nodos_y_dientes() -> void:
	var cocodrilo: Node = ESCENA.instantiate()
	for ruta: String in NODOS_OBLIGATORIOS:
		afirmar(cocodrilo.has_node(ruta), "Falta el nodo " + ruta)
	var indices := {}
	for diente in cocodrilo.get_node("Pose/Respiracion/Cabeza/Mandibula/Dientes").get_children():
		afirmar(diente.has_node("Pivote/Malla"), "Diente sin Pivote/Malla: " + diente.name)
		indices[diente.get("indice")] = true
	afirmar_igual(indices.size(), Reglas.TOTAL_DIENTES, "Número de dientes jugables")
	for i in Reglas.TOTAL_DIENTES:
		afirmar(indices.has(i), "Falta el diente con índice %d" % i)
	cocodrilo.free()
