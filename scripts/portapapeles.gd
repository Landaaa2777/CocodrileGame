class_name Portapapeles
extends RefCounted
## Copiar y pegar con la misma interfaz en todas las plataformas.
##
## En Android y escritorio DisplayServer accede al portapapeles del sistema.
## En el navegador, DisplayServer.clipboard_get() solo conoce lo que se pegó con
## Ctrl+V dentro del lienzo, así que usamos navigator.clipboard.readText() vía
## JavaScriptBridge (asíncrono, requiere HTTPS y que el usuario acepte el permiso).

# Las funciones de JavaScript deben seguir referenciadas mientras la promesa está
# pendiente; si no, el recolector de basura las libera y nunca se llaman.
static var _js_al_leer: Variant = null
static var _js_al_fallar: Variant = null


static func copiar(texto: String) -> void:
	DisplayServer.clipboard_set(texto)


## Llama a al_recibir(texto: String) con el contenido del portapapeles.
static func pegar(al_recibir: Callable) -> void:
	if OS.has_feature("web") and _pegar_en_navegador(al_recibir):
		return
	al_recibir.call(DisplayServer.clipboard_get())


static func _pegar_en_navegador(al_recibir: Callable) -> bool:
	var navegador: Variant = JavaScriptBridge.get_interface("navigator")
	if navegador == null or navegador.clipboard == null:
		return false
	_js_al_leer = JavaScriptBridge.create_callback(func(argumentos: Array) -> void:
		al_recibir.call(str(argumentos[0]) if argumentos.size() > 0 else ""))
	_js_al_fallar = JavaScriptBridge.create_callback(func(_argumentos: Array) -> void:
		# Permiso denegado: devolvemos lo último que el lienzo recibió con Ctrl+V.
		al_recibir.call(DisplayServer.clipboard_get()))
	navegador.clipboard.readText().then(_js_al_leer, _js_al_fallar)
	return true
