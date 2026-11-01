extends SceneTree
## Prueba de integración de la negociación WebRTC en un solo proceso:
## dos instancias de red.gd (anfitrión e invitado) intercambian sus códigos
## exactamente como lo harían dos jugadores copiando y pegando, se conectan y
## se envían un mensaje de juego.
##
##   godot --headless --path . --script res://tests/prueba_red_local.gd
##
## En escritorio/Android necesita el addon webrtc-native (addons/webrtc/).

const RedScript := preload("res://autoload/red.gd")
const ProtocoloScript := preload("res://scripts/protocolo.gd")
const TIEMPO_LIMITE_S := 60.0
const DIENTE_DE_PRUEBA := 7

var _anfitrion: Node
var _invitado: Node
var _terminado := false


func _initialize() -> void:
	_anfitrion = RedScript.new()
	_invitado = RedScript.new()
	_anfitrion.name = "Anfitrion"
	_invitado.name = "Invitado"
	root.add_child(_anfitrion)
	root.add_child(_invitado)

	_anfitrion.desconectado.connect(func(motivo: String) -> void: _fallar("anfitrión: " + motivo))
	_invitado.desconectado.connect(func(motivo: String) -> void: _fallar("invitado: " + motivo))
	_anfitrion.codigo_generado.connect(func(codigo: String) -> void:
		print("Código del anfitrión: %d caracteres" % codigo.length())
		_invitado.unirse(codigo))
	_invitado.codigo_generado.connect(func(codigo: String) -> void:
		print("Respuesta del invitado: %d caracteres" % codigo.length())
		_anfitrion.aceptar_respuesta(codigo))
	_anfitrion.conectado.connect(func() -> void:
		print("Anfitrión conectado; enviando jugada de prueba")
		_anfitrion.enviar(ProtocoloScript.crear(ProtocoloScript.JUGADA, {"diente": DIENTE_DE_PRUEBA})))
	_invitado.establecer_receptor(_al_recibir)
	create_timer(TIEMPO_LIMITE_S).timeout.connect(func() -> void:
		_fallar("tiempo agotado (estados %d / %d)" % [_anfitrion.estado, _invitado.estado]))

	if not _anfitrion.crear_partida():
		_fallar("no se pudo crear la partida (¿falta addons/webrtc?)")


func _al_recibir(mensaje: Dictionary) -> void:
	# El número llega como float por JSON: se convierte a int antes de comparar.
	var diente := ProtocoloScript.leer_entero(mensaje, "diente")
	if ProtocoloScript.tipo_de(mensaje) == ProtocoloScript.JUGADA and diente == DIENTE_DE_PRUEBA:
		_terminar(0, "OK: el invitado recibió la jugada (diente %d)" % diente)
	else:
		_fallar("mensaje inesperado: %s" % mensaje)


func _fallar(motivo: String) -> void:
	_terminar(1, "FALLO: " + motivo)


func _terminar(codigo: int, texto: String) -> void:
	if _terminado:
		return
	_terminado = true
	if codigo == 0:
		print(texto)
	else:
		printerr(texto)
	_anfitrion.cerrar()
	_invitado.cerrar()
	quit(codigo)
