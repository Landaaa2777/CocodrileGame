extends SceneTree
## Renderiza capturas de las pantallas principales con el renderizador real.
## Necesita ventana y OpenGL (en CI: xvfb-run + Mesa):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 405x720 \
##       --script res://tests/capturar_pantallas.gd
## Las imágenes quedan en build/capturas/.

const CARPETA := "res://build/capturas/"
const CAPTURAS := [
	{"nombre": "1_menu", "escena": "res://escenas/menu.tscn", "datos": {}, "espera": 2.6},
	{"nombre": "2_conexion", "escena": "res://escenas/conexion.tscn", "datos": {"anfitrion": true}, "espera": 2.0},
	{"nombre": "3_partida", "escena": "res://escenas/partida.tscn", "datos": {"modo": "practica"}, "espera": 3.4},
	{"nombre": "4_victoria", "escena": "res://escenas/resultado.tscn",
		"datos": {"gane": true, "modo": "practica"}, "espera": 2.2},
	{"nombre": "5_derrota", "escena": "res://escenas/resultado.tscn",
		"datos": {"gane": false, "modo": "practica"}, "espera": 2.2},
]


func _initialize() -> void:
	_capturar.call_deferred()


func _capturar() -> void:
	var carpeta := ProjectSettings.globalize_path(CARPETA)
	DirAccess.make_dir_recursive_absolute(carpeta)
	var transicion: Node = root.get_node_or_null("Transicion")
	for captura: Dictionary in CAPTURAS:
		if transicion != null:
			transicion.set("datos", captura["datos"])
		change_scene_to_file(captura["escena"])
		await create_timer(captura["espera"]).timeout
		await process_frame
		var imagen := root.get_texture().get_image()
		imagen.save_png(carpeta + captura["nombre"] + ".png")
		print("Captura %s: %s" % [captura["nombre"], imagen.get_size()])
	quit()
