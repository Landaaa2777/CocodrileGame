extends SceneTree
## Ejecuta todas las pruebas sin abrir ventana:
##   godot --headless --path . --script res://tests/ejecutar_pruebas.gd
## Sale con código 1 si alguna prueba falla (útil en CI).

const ARCHIVOS_DE_PRUEBA := [
	"res://tests/test_reglas_juego.gd",
	"res://tests/test_codigo_conexion.gd",
]


func _initialize() -> void:
	var total := 0
	var fallidas := 0
	for ruta: String in ARCHIVOS_DE_PRUEBA:
		var script: GDScript = load(ruta)
		if script == null:
			printerr("No se pudo cargar ", ruta)
			fallidas += 1
			continue
		print("\n", ruta.get_file())
		for metodo: Dictionary in script.get_script_method_list():
			var nombre: String = metodo["name"]
			if not nombre.begins_with("test_"):
				continue
			total += 1
			var caso: RefCounted = script.new()
			caso.call(nombre)
			var fallos: Array[String] = caso.get("fallos")
			if fallos.is_empty():
				print("  OK    ", nombre)
			else:
				fallidas += 1
				for fallo in fallos:
					printerr("  FALLO ", nombre, ": ", fallo)
	print("\n%d pruebas, %d fallidas" % [total, fallidas])
	quit(1 if fallidas > 0 else 0)
