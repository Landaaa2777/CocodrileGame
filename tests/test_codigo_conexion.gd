extends "res://tests/caso_prueba.gd"
## Pruebas del código de conexión (JSON + base64) y de la conversión de números.

const RedScript := preload("res://autoload/red.gd")
const ProtocoloScript := preload("res://scripts/protocolo.gd")
const SDP_FALSO := "v=0\r\no=- 123 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n"


func test_codigo_ida_y_vuelta() -> void:
	var candidatos := [
		{"media": "0", "indice": 0, "nombre": "candidate:1 1 UDP 2122 192.168.1.5 50000 typ host"},
		{"media": "0", "indice": 0, "nombre": "candidate:2 1 UDP 1686 85.1.2.3 50001 typ srflx"},
	]
	var codigo := RedScript.codificar_codigo(RedScript.TIPO_OFERTA, SDP_FALSO, candidatos)
	afirmar(not codigo.is_empty(), "Se genera un código")
	var datos := RedScript.decodificar_codigo(codigo)
	afirmar_igual(datos.get("tipo"), RedScript.TIPO_OFERTA, "Tipo conservado")
	afirmar_igual(datos.get("sdp"), SDP_FALSO, "SDP conservado")
	var leidos: Array = datos.get("candidatos", [])
	afirmar_igual(leidos.size(), 2, "Candidatos conservados")
	# Tras pasar por JSON el índice llega como float y debe volver a ser int.
	afirmar_igual(typeof(leidos[0]["indice"]), TYPE_INT, "Índice convertido a int")


func test_codigo_tolera_espacios_y_saltos() -> void:
	var codigo := RedScript.codificar_codigo(RedScript.TIPO_RESPUESTA, SDP_FALSO, [])
	var ensuciado := "  \"" + codigo.substr(0, 10) + "\n" + codigo.substr(10) + "\"\r\n "
	var datos := RedScript.decodificar_codigo(ensuciado)
	afirmar_igual(datos.get("tipo"), RedScript.TIPO_RESPUESTA, "Se limpia el código pegado")


func test_codigos_invalidos() -> void:
	afirmar(RedScript.decodificar_codigo("").is_empty(), "Vacío")
	afirmar(RedScript.decodificar_codigo("hola mundo").is_empty(), "Texto cualquiera")
	var json_raro := Marshalls.utf8_to_base64(JSON.stringify({"tipo": "pirata", "sdp": "x"}))
	afirmar(RedScript.decodificar_codigo(json_raro).is_empty(), "Tipo desconocido")
	var sin_sdp := Marshalls.utf8_to_base64(JSON.stringify({"tipo": "offer", "sdp": ""}))
	afirmar(RedScript.decodificar_codigo(sin_sdp).is_empty(), "SDP vacío")


func test_a_entero_desde_json() -> void:
	var desde_json: Variant = JSON.parse_string("{\"diente\": 3}")
	afirmar_igual(typeof(desde_json["diente"]), TYPE_FLOAT, "JSON entrega float")
	afirmar_igual(ProtocoloScript.a_entero(desde_json["diente"]), 3, "Float entero a int")
	afirmar_igual(ProtocoloScript.a_entero(2.5), -1, "Float con decimales se rechaza")
	afirmar_igual(ProtocoloScript.a_entero("7"), 7, "Texto numérico")
	afirmar_igual(ProtocoloScript.a_entero(null, -9), -9, "Valor por defecto")
	afirmar_igual(ProtocoloScript.a_entero(INF), -1, "Infinito se rechaza")
