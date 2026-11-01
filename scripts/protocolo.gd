class_name Protocolo
extends RefCounted
## Mensajes de juego que viajan por el canal de datos WebRTC como JSON.
##
## Regla de oro: el ANFITRIÓN es la única autoridad. El invitado solo PIDE jugadas
## y el anfitrión responde con el resultado (también de sus propias jugadas).
##
##   invitado → anfitrión : LISTO, JUGADA, APUNTA, REVANCHA, SALIR
##   anfitrión → invitado : INICIO, RESULTADO, RECHAZO, APUNTA, REVANCHA_OK, SALIR

const CLAVE_TIPO := "t"

## El invitado avisa de que su escena de partida está cargada.
const LISTO := "listo"
## Empieza una ronda: {ronda, turno, compromiso}.
const INICIO := "inicio"
## El invitado pide presionar un diente: {diente}.
const JUGADA := "jugada"
## Resultado decidido por el anfitrión: {jugador, diente, mordida, turno, [mordedor, sal]}.
const RESULTADO := "resultado"
## Jugada rechazada por el anfitrión: {diente, motivo}.
const RECHAZO := "rechazo"
## Diente bajo el cursor del jugador (solo efecto visual para el rival): {diente}.
const APUNTA := "apunta"
## Petición de jugar otra vez.
const REVANCHA := "revancha"
## El anfitrión confirma que ambos quieren revancha.
const REVANCHA_OK := "revancha_ok"
## Un jugador vuelve al menú.
const SALIR := "salir"


static func crear(tipo: String, datos: Dictionary = {}) -> Dictionary:
	var mensaje := datos.duplicate()
	mensaje[CLAVE_TIPO] = tipo
	return mensaje


static func tipo_de(mensaje: Dictionary) -> String:
	return str(mensaje.get(CLAVE_TIPO, ""))


## JSON entrega TODOS los números como float (3 llega como 3.0).
## Esta función los convierte a int de forma segura y rechaza basura.
static func a_entero(valor: Variant, por_defecto: int = -1) -> int:
	match typeof(valor):
		TYPE_INT:
			return valor
		TYPE_FLOAT:
			var numero: float = valor
			if is_finite(numero) and is_equal_approx(numero, roundf(numero)):
				return int(roundf(numero))
		TYPE_STRING:
			var texto: String = valor
			if texto.is_valid_int():
				return texto.to_int()
	return por_defecto


static func leer_entero(mensaje: Dictionary, clave: String, por_defecto: int = -1) -> int:
	return a_entero(mensaje.get(clave), por_defecto)


static func leer_bool(mensaje: Dictionary, clave: String) -> bool:
	var valor: Variant = mensaje.get(clave, false)
	if typeof(valor) == TYPE_BOOL:
		return valor
	return a_entero(valor, 0) != 0


static func leer_texto(mensaje: Dictionary, clave: String) -> String:
	var valor: Variant = mensaje.get(clave, "")
	return valor if typeof(valor) == TYPE_STRING else ""
