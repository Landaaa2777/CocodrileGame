shader_type spatial;
// Contorno por «casco invertido» (inverted hull):
// se dibuja la malla otra vez, inflada a lo largo de las normales y mostrando
// solo las caras traseras (cull_front). Lo que asoma alrededor del objeto es el contorno.
// Se usa como next_pass del material toon.
//
// world_vertex_coords: VERTEX y NORMAL llegan en espacio de mundo, así las mallas
// escaladas de forma no uniforme (esferas aplastadas) tienen un contorno parejo.
// El grosor se multiplica por la distancia a la cámara para que se vea igual de
// grueso en pantalla esté cerca o lejos.

render_mode unshaded, cull_front, depth_draw_opaque, world_vertex_coords, shadows_disabled;

uniform vec4 color_contorno : source_color = vec4(0.1, 0.13, 0.08, 1.0);
uniform float grosor : hint_range(0.0, 0.02) = 0.0042;

void vertex() {
	vec3 posicion_camara = INV_VIEW_MATRIX[3].xyz;
	float distancia = length(posicion_camara - VERTEX);
	VERTEX += normalize(NORMAL) * grosor * distancia;
}

void fragment() {
	ALBEDO = color_contorno.rgb;
}
