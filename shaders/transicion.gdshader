shader_type canvas_item;
// Barrido diagonal de color con borde ondulado para cambiar de pantalla.
// fase = 0: la cortina CUBRE la pantalla según «progreso» (0 → 1).
// fase = 1: la cortina se RETIRA en la misma dirección (0 → 1).

uniform float progreso : hint_range(0.0, 1.0) = 0.0;
uniform float fase : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color_principal : source_color = vec4(0.55, 0.85, 0.2, 1.0);
uniform vec4 color_borde : source_color = vec4(1.0, 0.42, 0.42, 1.0);
uniform vec4 color_lunares : source_color = vec4(0.62, 0.9, 0.3, 1.0);
uniform float ancho_borde = 0.06;
uniform float inclinacion = 0.35;
uniform float frecuencia_onda = 14.0;
uniform float amplitud_onda = 0.018;
uniform float tamano_lunares = 46.0;

void fragment() {
	vec2 uv = UV;
	// Coordenada diagonal normalizada a [0, 1].
	float d = (uv.x + (1.0 - uv.y) * inclinacion) / (1.0 + inclinacion);
	d += sin(uv.y * frecuencia_onda + TIME * 5.0) * amplitud_onda;
	// Extiende el rango para que el borde salga por completo de la pantalla.
	float umbral = progreso * (1.0 + 2.0 * ancho_borde) - ancho_borde;
	float cubierto = fase < 0.5 ? step(d, umbral) : step(umbral, d);
	if (cubierto < 0.5) {
		discard;
	}
	float distancia_borde = abs(d - umbral);
	vec3 color = color_principal.rgb;
	// Lunares suaves para dar textura «de fiesta».
	vec2 celda = fract(FRAGCOORD.xy / tamano_lunares) - 0.5;
	color = mix(color, color_lunares.rgb, step(length(celda), 0.22));
	color = mix(color_borde.rgb, color, step(ancho_borde, distancia_borde));
	COLOR = vec4(color, 1.0);
}
