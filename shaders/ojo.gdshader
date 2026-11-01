shader_type spatial;
// Ojo de dibujo animado: esfera blanca, pupila negra que sigue al cursor
// y reflejo especular FIJO (no se mueve con la pupila).
//
// La pupila se proyecta de forma plana sobre la cara frontal (+Z local) de la
// esfera. «mirada» (de -1 a 1 en X e Y) desplaza la pupila; la calcula cocodrilo.gd.

render_mode cull_back;

uniform sampler2D textura_pupila : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 mirada = vec2(0.0, 0.0);
uniform float alcance_mirada : hint_range(0.0, 0.8) = 0.42;
uniform float tamano_pupila : hint_range(0.1, 1.0) = 0.46;
uniform float dilatacion : hint_range(0.5, 1.6) = 1.0;
uniform float mostrar_pupila : hint_range(0.0, 1.0) = 1.0;
uniform vec4 color_esclera : source_color = vec4(1.0, 1.0, 0.97, 1.0);
uniform vec4 color_sombra : source_color = vec4(0.72, 0.78, 0.95, 1.0);
uniform vec2 posicion_brillo = vec2(-0.3, 0.36);
uniform float tamano_brillo : hint_range(0.0, 0.5) = 0.15;

varying vec3 posicion_local;

void vertex() {
	posicion_local = VERTEX;
}

void fragment() {
	vec3 p = normalize(posicion_local);
	float frente = smoothstep(0.05, 0.3, p.z);
	vec2 centro = mirada * alcance_mirada;
	vec2 uv = (p.xy - centro) / (tamano_pupila * dilatacion) * 0.5 + 0.5;
	vec4 pupila = texture(textura_pupila, uv);
	float cobertura = pupila.a * frente * mostrar_pupila;
	vec3 color = mix(color_esclera.rgb, pupila.rgb, cobertura);
	// Sombra suave arriba, donde el párpado tapa la luz.
	color = mix(color, color * color_sombra.rgb, smoothstep(0.35, 0.95, p.y) * 0.6);
	// Reflejo fijo: un óvalo grande y un punto pequeño.
	float brillo = 1.0 - smoothstep(tamano_brillo * 0.75, tamano_brillo, distance(p.xy, posicion_brillo));
	brillo = max(brillo, 1.0 - smoothstep(tamano_brillo * 0.3, tamano_brillo * 0.42,
		distance(p.xy, posicion_brillo + vec2(0.2, -0.14))));
	brillo *= frente;
	ALBEDO = mix(color, vec3(1.0), brillo);
	EMISSION = vec3(brillo * 0.6);
	ROUGHNESS = 1.0;
}

void light() {
	float luz = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float escalon = mix(0.55, 1.0, smoothstep(0.1, 0.2, luz));
	DIFFUSE_LIGHT += escalon * LIGHT_COLOR / PI;
}
