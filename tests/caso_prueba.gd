extends RefCounted
## Base mínima para las pruebas: cada método «test_*» se ejecuta por separado
## y acumula los fallos en «fallos».

var fallos: Array[String] = []


func afirmar(condicion: bool, mensaje: String) -> void:
	if not condicion:
		fallos.append(mensaje)


func afirmar_igual(obtenido: Variant, esperado: Variant, mensaje: String) -> void:
	if typeof(obtenido) != typeof(esperado) or obtenido != esperado:
		fallos.append("%s (esperado: %s, obtenido: %s)" % [mensaje, str(esperado), str(obtenido)])
