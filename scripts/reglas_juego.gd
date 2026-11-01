class_name ReglasJuego
extends RefCounted
## Lógica pura de una partida de «Cocodrilo Dentista».
##
## No depende de nodos ni de la red, así que se puede probar de forma aislada
## (ver tests/test_reglas_juego.gd).
##
## Solo el ANFITRIÓN tiene la instancia «autoritativa», la que conoce el diente
## mordedor. El invitado mantiene un espejo sin ese dato (diente_mordedor = SIN_DIENTE)
## que actualiza con los resultados que le envía el anfitrión.

const TOTAL_DIENTES := 12
const DIENTES_SUPERIORES := 6
const DIENTES_INFERIORES := TOTAL_DIENTES - DIENTES_SUPERIORES

const ANFITRION := 0
const INVITADO := 1
const SIN_JUGADOR := -1
const SIN_DIENTE := -1

## Motivos por los que el anfitrión rechaza una jugada.
enum ErrorJugada {
	NINGUNO,
	RONDA_NO_INICIADA,
	RONDA_TERMINADA,
	JUGADOR_INVALIDO,
	NO_ES_SU_TURNO,
	DIENTE_FUERA_DE_RANGO,
	DIENTE_YA_USADO,
}

var ronda := 0
var turno := SIN_JUGADOR
var diente_mordedor := SIN_DIENTE
var perdedor := SIN_JUGADOR
var en_curso := false
var dientes_usados: Array[bool] = []


## Prepara una ronda nueva y elige EN SECRETO el diente mordedor.
## Se pasa el generador para que las pruebas puedan usar una semilla fija.
func nueva_ronda(rng: RandomNumberGenerator) -> void:
	_preparar_ronda(ronda + 1)
	diente_mordedor = rng.randi_range(0, TOTAL_DIENTES - 1)


## Versión para el espejo del invitado: misma ronda y turno, sin mordedor.
func nueva_ronda_espejo(numero_ronda: int, turno_inicial: int) -> void:
	_preparar_ronda(numero_ronda)
	diente_mordedor = SIN_DIENTE
	turno = turno_inicial


func _preparar_ronda(numero_ronda: int) -> void:
	ronda = numero_ronda
	dientes_usados.clear()
	dientes_usados.resize(TOTAL_DIENTES)
	dientes_usados.fill(false)
	turno = jugador_inicial(ronda)
	perdedor = SIN_JUGADOR
	en_curso = true


## Quién abre cada ronda: la primera la abre el invitado y luego se alterna.
## Con un número par de dientes y el mordedor al azar, empezar no da ventaja:
## cada jugador presiona exactamente la mitad de las posiciones posibles.
static func jugador_inicial(numero_ronda: int) -> int:
	return INVITADO if numero_ronda % 2 == 1 else ANFITRION


static func otro_jugador(jugador: int) -> int:
	return INVITADO if jugador == ANFITRION else ANFITRION


static func es_jugador_valido(jugador: int) -> bool:
	return jugador == ANFITRION or jugador == INVITADO


static func es_indice_valido(diente: int) -> bool:
	return diente >= 0 and diente < TOTAL_DIENTES


## Reglas de validación (las aplica el anfitrión a CADA jugada, también a las suyas):
##  1. Debe haber una ronda iniciada y sin terminar.
##  2. El jugador debe existir y ser al que le toca.
##  3. El diente debe estar dentro del rango y no haberse presionado antes.
func validar_jugada(jugador: int, diente: int) -> ErrorJugada:
	if ronda == 0:
		return ErrorJugada.RONDA_NO_INICIADA
	if not en_curso:
		return ErrorJugada.RONDA_TERMINADA
	if not es_jugador_valido(jugador):
		return ErrorJugada.JUGADOR_INVALIDO
	if jugador != turno:
		return ErrorJugada.NO_ES_SU_TURNO
	if not es_indice_valido(diente):
		return ErrorJugada.DIENTE_FUERA_DE_RANGO
	if dientes_usados[diente]:
		return ErrorJugada.DIENTE_YA_USADO
	return ErrorJugada.NINGUNO


## Aplica una jugada (solo en la instancia autoritativa del anfitrión).
## Devuelve un diccionario con el resultado, listo para enviarse por la red.
func aplicar_jugada(jugador: int, diente: int) -> Dictionary:
	var error := validar_jugada(jugador, diente)
	if error != ErrorJugada.NINGUNO:
		return {"valida": false, "error": error}
	dientes_usados[diente] = true
	var mordida := diente == diente_mordedor
	if mordida:
		en_curso = false
		perdedor = jugador
	else:
		turno = otro_jugador(jugador)
	return {
		"valida": true,
		"error": ErrorJugada.NINGUNO,
		"jugador": jugador,
		"diente": diente,
		"mordida": mordida,
		"turno": turno,
		"terminada": not en_curso,
	}


## Aplica en el espejo del invitado un resultado ya decidido por el anfitrión.
func aplicar_resultado_remoto(jugador: int, diente: int, mordida: bool, siguiente_turno: int) -> void:
	if not es_indice_valido(diente):
		return
	dientes_usados[diente] = true
	if mordida:
		en_curso = false
		perdedor = jugador
	else:
		turno = siguiente_turno


func esta_usado(diente: int) -> bool:
	return es_indice_valido(diente) and dientes_usados.size() == TOTAL_DIENTES and dientes_usados[diente]


func dientes_restantes() -> int:
	return dientes_usados.count(false)


## 0.0 al empezar la ronda, 1.0 cuando solo queda el último diente.
## Se usa para subir la intensidad de la música conforme se acerca la mordida.
func tension() -> float:
	var usados := TOTAL_DIENTES - dientes_restantes()
	return clampf(float(usados) / float(TOTAL_DIENTES - 1), 0.0, 1.0)


# --- Compromiso criptográfico (commit-reveal) -----------------------------------
# Al empezar la ronda el anfitrión publica sha256("diente:sal"). Al terminar revela
# diente y sal, y el invitado comprueba que el mordedor no cambió a mitad de ronda.
# NO impide que el anfitrión conozca el diente: solo detecta que lo cambie.

static func crear_compromiso(diente: int, sal: String) -> String:
	return ("%d:%s" % [diente, sal]).sha256_text()


static func verificar_compromiso(compromiso: String, diente: int, sal: String) -> bool:
	return not compromiso.is_empty() and crear_compromiso(diente, sal) == compromiso


static func describir_error(error: ErrorJugada) -> String:
	match error:
		ErrorJugada.RONDA_NO_INICIADA:
			return "La ronda aún no ha empezado."
		ErrorJugada.RONDA_TERMINADA:
			return "La ronda ya terminó."
		ErrorJugada.JUGADOR_INVALIDO:
			return "Jugador desconocido."
		ErrorJugada.NO_ES_SU_TURNO:
			return "No es tu turno."
		ErrorJugada.DIENTE_FUERA_DE_RANGO:
			return "Ese diente no existe."
		ErrorJugada.DIENTE_YA_USADO:
			return "Ese diente ya se presionó."
	return ""
