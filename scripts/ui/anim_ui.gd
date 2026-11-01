class_name AnimUI
extends RefCounted
## Animaciones de interfaz reutilizables. Todas usan Tween con curvas suaves.

const DURACION_APARECER := 0.45
const DURACION_DESAPARECER := 0.22
const ESCALA_BOTON_PULSADO := Vector2(0.92, 0.92)
const DURACION_PULSO := 0.12


## Entrada «escala desde 0 con rebote». Funciona dentro de contenedores porque
## los contenedores colocan y dimensionan, pero no tocan la escala.
static func aparecer(control: Control, retraso: float = 0.0, duracion: float = DURACION_APARECER) -> Tween:
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ZERO
	var tween := control.create_tween()
	if retraso > 0.0:
		tween.tween_interval(retraso)
	tween.tween_property(control, "scale", Vector2.ONE, duracion) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween


static func desaparecer(control: Control, duracion: float = DURACION_DESAPARECER) -> Tween:
	control.pivot_offset = control.size * 0.5
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2.ZERO, duracion) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	return tween


## Pequeño «latido» para llamar la atención (p. ej. al cambiar el texto de estado).
static func latido(control: Control, intensidad: float = 1.15) -> Tween:
	control.pivot_offset = control.size * 0.5
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE * intensidad, 0.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return tween


## Botón «blandito»: se encoge al pulsarlo, rebota al soltarlo y suena.
static func preparar_boton(boton: BaseButton) -> void:
	boton.button_down.connect(func() -> void:
		boton.pivot_offset = boton.size * 0.5
		boton.create_tween().tween_property(boton, "scale", ESCALA_BOTON_PULSADO, DURACION_PULSO) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))
	boton.button_up.connect(func() -> void:
		boton.create_tween().tween_property(boton, "scale", Vector2.ONE, 0.4) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	boton.pressed.connect(func() -> void: Audio.reproducir_sfx("boton", 1.0, 0.06))
