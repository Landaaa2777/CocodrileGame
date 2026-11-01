shader_type spatial;
// Sombreado toon de «plástico satinado» para el cocodrilo y su boca.
//  * Luz difusa cuantizada en escalones (bandas) con bordes ligeramente suaves.
//  * Brillo especular nítido de dibujo animado + un brillo ancho y suave (satinado).
//  * Luz de borde (rim) en la parte superior de la silueta.
// El contorno negro lo dibuja otro material (contorno.gdshader) en next_pass.

render_mode cull_back, depth_draw_opaque;

uniform vec4 color_base : source_color = vec4(1.0);
uniform sampler2D textura_albedo : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform sampler2D textura_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool usar_normal = false;
uniform float fuerza_normal : hint_range(0.0, 4.0) = 1.0;
uniform vec2 escala_uv = vec2(1.0, 1.0);

uniform float bandas : hint_range(1.0, 6.0) = 3.0;
uniform float suavidad_banda : hint_range(0.0, 0.5) = 0.08;
// Brillo nítido (dibujo animado)
uniform float brillo_especular : hint_range(0.0, 3.0) = 0.8;
uniform float tamano_especular : hint_range(0.0, 1.0) = 0.3;
// Brillo ancho (satinado / húmedo)
uniform float brillo_satinado : hint_range(0.0, 1.0) = 0.15;
uniform float fuerza_borde : hint_range(0.0, 1.0) = 0.35;
uniform vec4 color_borde : source_color = vec4(1.0, 1.0, 0.9, 1.0);

// Estados de juego (dientes)
uniform float mezcla_gris : hint_range(0.0, 1.0) = 0.0;
uniform float realce : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color_realce : source_color = vec4(1.0, 0.92, 0.35, 1.0);
uniform vec4 color_emision : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec3 albedo = texture(textura_albedo, UV * escala_uv).rgb * color_base.rgb;
	// Diente ya usado: desaturado y algo más oscuro.
	float luminancia = dot(albedo, vec3(0.299, 0.587, 0.114));
	albedo = mix(albedo, vec3(luminancia * 0.62), mezcla_gris);
	ALBEDO = albedo;
	if (usar_normal) {
		NORMAL_MAP = texture(textura_normal, UV * escala_uv).rgb;
		NORMAL_MAP_DEPTH = fuerza_normal;
	}
	ROUGHNESS = 1.0;
	// Luz de borde solo en la mitad superior de la silueta (NORMAL está en espacio de vista).
	float fresnel = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float borde = smoothstep(0.55, 0.8, fresnel) * smoothstep(-0.1, 0.6, NORMAL.y);
	EMISSION = color_borde.rgb * borde * fuerza_borde * 0.5
		+ color_emision.rgb
		+ color_realce.rgb * realce * 0.45;
}

void light() {
	// ATTENUATION incluye la sombra proyectada.
	float luz = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float x = luz * bandas;
	float escalon = (floor(x) + smoothstep(0.5 - suavidad_banda, 0.5 + suavidad_banda, fract(x))) / bandas;
	DIFFUSE_LIGHT += escalon * LIGHT_COLOR / PI;

	vec3 medio = normalize(LIGHT + VIEW);
	float ndh = clamp(dot(NORMAL, medio), 0.0, 1.0);
	float exponente = mix(160.0, 12.0, tamano_especular);
	float nitido = smoothstep(0.42, 0.5, pow(ndh, exponente)) * brillo_especular;
	float satinado = pow(ndh, 10.0) * brillo_satinado;
	SPECULAR_LIGHT += (nitido + satinado) * ATTENUATION * LIGHT_COLOR / PI;
}
