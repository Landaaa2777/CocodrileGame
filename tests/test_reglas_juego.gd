extends "res://tests/caso_prueba.gd"
## Pruebas de la lógica de turnos y del diente mordedor.

const Reglas := preload("res://scripts/reglas_juego.gd")
const SEMILLAS_A_PROBAR := 500


func _rng(semilla: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	return rng


## El diente mordedor SIEMPRE debe ser uno de los dientes válidos.
func test_mordedor_siempre_entre_los_validos() -> void:
	var vistos := {}
	for semilla in SEMILLAS_A_PROBAR:
		var reglas := Reglas.new()
		reglas.nueva_ronda(_rng(semilla))
		afirmar(Reglas.es_indice_valido(reglas.diente_mordedor),
			"Mordedor fuera de rango con semilla %d: %d" % [semilla, reglas.diente_mordedor])
		vistos[reglas.diente_mordedor] = true
	# Con 500 semillas deberían haber salido todos los dientes alguna vez.
	afirmar_igual(vistos.size(), Reglas.TOTAL_DIENTES, "Todos los dientes pueden ser el mordedor")


func test_constantes_coherentes() -> void:
	afirmar(Reglas.TOTAL_DIENTES % 2 == 0, "Número par de dientes: empezar no da ventaja")


func test_turnos_alternan() -> void:
	var reglas := Reglas.new()
	reglas.nueva_ronda(_rng(1))
	afirmar_igual(reglas.turno, Reglas.INVITADO, "La ronda 1 la abre el invitado")
	var jugador := reglas.turno
	var jugadas := 0
	for diente in Reglas.TOTAL_DIENTES:
		if diente == reglas.diente_mordedor:
			continue
		var resultado := reglas.aplicar_jugada(jugador, diente)
		afirmar(resultado["valida"], "Jugada válida %d" % diente)
		afirmar_igual(resultado["mordida"], false, "Diente seguro %d no muerde" % diente)
		afirmar_igual(reglas.turno, Reglas.otro_jugador(jugador), "El turno pasa al otro jugador")
		jugador = reglas.turno
		jugadas += 1
	afirmar_igual(jugadas, Reglas.TOTAL_DIENTES - 1, "Se pueden jugar todos los seguros")
	afirmar_igual(reglas.dientes_restantes(), 1, "Solo queda el mordedor")
	afirmar(is_equal_approx(reglas.tension(), 1.0), "Tensión máxima con un diente restante")


func test_no_se_puede_jugar_fuera_de_turno() -> void:
	var reglas := Reglas.new()
	reglas.nueva_ronda(_rng(2))
	var fuera_de_turno := Reglas.otro_jugador(reglas.turno)
	var seguro := (reglas.diente_mordedor + 1) % Reglas.TOTAL_DIENTES
	afirmar_igual(reglas.validar_jugada(fuera_de_turno, seguro), Reglas.ErrorJugada.NO_ES_SU_TURNO,
		"Rechaza jugada fuera de turno")
	var resultado := reglas.aplicar_jugada(fuera_de_turno, seguro)
	afirmar_igual(resultado["valida"], false, "aplicar_jugada no aplica jugadas inválidas")
	afirmar_igual(reglas.esta_usado(seguro), false, "El diente sigue libre")


func test_no_se_repiten_dientes() -> void:
	var reglas := Reglas.new()
	reglas.nueva_ronda(_rng(3))
	var seguro := (reglas.diente_mordedor + 1) % Reglas.TOTAL_DIENTES
	var primero := reglas.turno
	reglas.aplicar_jugada(primero, seguro)
	afirmar_igual(reglas.validar_jugada(reglas.turno, seguro), Reglas.ErrorJugada.DIENTE_YA_USADO,
		"Rechaza diente ya usado")


func test_rangos_invalidos() -> void:
	var reglas := Reglas.new()
	afirmar_igual(reglas.validar_jugada(Reglas.INVITADO, 0), Reglas.ErrorJugada.RONDA_NO_INICIADA,
		"Sin ronda no se juega")
	reglas.nueva_ronda(_rng(4))
	afirmar_igual(reglas.validar_jugada(reglas.turno, -1), Reglas.ErrorJugada.DIENTE_FUERA_DE_RANGO,
		"Índice negativo")
	afirmar_igual(reglas.validar_jugada(reglas.turno, Reglas.TOTAL_DIENTES),
		Reglas.ErrorJugada.DIENTE_FUERA_DE_RANGO, "Índice demasiado grande")
	afirmar_igual(reglas.validar_jugada(7, 0), Reglas.ErrorJugada.JUGADOR_INVALIDO, "Jugador inexistente")


func test_mordida_termina_la_ronda() -> void:
	var reglas := Reglas.new()
	reglas.nueva_ronda(_rng(5))
	var jugador := reglas.turno
	var resultado := reglas.aplicar_jugada(jugador, reglas.diente_mordedor)
	afirmar(resultado["valida"], "Presionar el mordedor es una jugada válida")
	afirmar(resultado["mordida"], "El mordedor muerde")
	afirmar(resultado["terminada"], "La ronda termina")
	afirmar_igual(reglas.perdedor, jugador, "Pierde quien lo presionó")
	var otro := (reglas.diente_mordedor + 1) % Reglas.TOTAL_DIENTES
	afirmar_igual(reglas.validar_jugada(reglas.turno, otro), Reglas.ErrorJugada.RONDA_TERMINADA,
		"No se juega tras la mordida")


func test_quien_empieza_alterna_por_ronda() -> void:
	var reglas := Reglas.new()
	var rng := _rng(6)
	reglas.nueva_ronda(rng)
	afirmar_igual(reglas.turno, Reglas.INVITADO, "Ronda 1: invitado")
	reglas.nueva_ronda(rng)
	afirmar_igual(reglas.turno, Reglas.ANFITRION, "Ronda 2: anfitrión")
	reglas.nueva_ronda(rng)
	afirmar_igual(reglas.turno, Reglas.INVITADO, "Ronda 3: invitado")
	afirmar_igual(reglas.dientes_restantes(), Reglas.TOTAL_DIENTES, "Ronda nueva sin dientes usados")


func test_espejo_del_invitado() -> void:
	var autoridad := Reglas.new()
	autoridad.nueva_ronda(_rng(7))
	var espejo := Reglas.new()
	espejo.nueva_ronda_espejo(autoridad.ronda, autoridad.turno)
	afirmar_igual(espejo.diente_mordedor, Reglas.SIN_DIENTE, "El espejo no conoce el mordedor")
	var seguro := (autoridad.diente_mordedor + 3) % Reglas.TOTAL_DIENTES
	var resultado := autoridad.aplicar_jugada(autoridad.turno, seguro)
	espejo.aplicar_resultado_remoto(resultado["jugador"], resultado["diente"], resultado["mordida"],
		resultado["turno"])
	afirmar_igual(espejo.turno, autoridad.turno, "Turno sincronizado")
	afirmar(espejo.esta_usado(seguro), "Diente marcado en el espejo")


func test_compromiso_detecta_cambios() -> void:
	var sal := "sal-de-prueba"
	var compromiso := Reglas.crear_compromiso(4, sal)
	afirmar(Reglas.verificar_compromiso(compromiso, 4, sal), "El compromiso correcto verifica")
	afirmar(not Reglas.verificar_compromiso(compromiso, 5, sal), "Otro diente no verifica")
	afirmar(not Reglas.verificar_compromiso(compromiso, 4, "otra"), "Otra sal no verifica")
	afirmar(not Reglas.verificar_compromiso("", 4, sal), "Compromiso vacío no verifica")
