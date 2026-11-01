shader_type sky;
// Fondo de fiesta: degradado azul cielo → rosa pastel con rayos que giran
// lentamente detrás del cocodrilo y lunares suaves.

uniform vec4 color_arriba : source_color = vec4(0.47, 0.76, 1.0, 1.0);
uniform vec4 color_abajo : source_color = vec4(1.0, 0.76, 0.86, 1.0);
uniform vec4 color_rayos : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec3 centro_rayos = vec3(0.0, -0.05, -1.0);
uniform float numero_rayos = 14.0;
uniform float velocidad_giro = 0.012;
uniform float fuerza_rayos : hint_range(0.0, 1.0) = 0.13;
uniform float fuerza_lunares : hint_range(0.0, 1.0) = 0.08;

void sky() {
	vec3 d = normalize(EYEDIR);
	// La cámara mira hacia abajo: el degradado se reparte por debajo del horizonte.
	float t = smoothstep(-0.75, 0.12, d.y);
	vec3 color = mix(color_abajo.rgb, color_arriba.rgb, t);

	vec3 c = normalize(centro_rayos);
	vec3 eje_x = normalize(cross(vec3(0.0, 1.0, 0.0), c));
	vec3 eje_y = cross(c, eje_x);
	float angulo = atan(dot(d, eje_y), dot(d, eje_x));
	float franja = fract(angulo / TAU * numero_rayos + TIME * velocidad_giro);
	float rayo = smoothstep(0.46, 0.5, franja) * (1.0 - smoothstep(0.96, 1.0, franja));
	float cerca = smoothstep(-0.2, 0.9, dot(d, c));
	color = mix(color, color_rayos.rgb, rayo * fuerza_rayos * cerca);

	// Lunares que flotan muy despacio.
	vec2 plano = vec2(dot(d, eje_x), dot(d, eje_y)) / max(dot(d, c), 0.2);
	vec2 celda = fract(plano * 3.5 + vec2(TIME * 0.02, TIME * 0.01)) - 0.5;
	float lunar = 1.0 - smoothstep(0.12, 0.14, length(celda));
	color = mix(color, color_rayos.rgb, lunar * fuerza_lunares);
	COLOR = color;
}
