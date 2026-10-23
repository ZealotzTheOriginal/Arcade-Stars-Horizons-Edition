shader_type canvas_item;
render_mode blend_disabled;
// Marco de la ventana del launcher: recorta las esquinas con un radio (fuera queda totalmente
// transparente gracias a la transparencia por píxel) y dibuja un borde suave de 1 px por dentro.
// Va encima de todo y reescribe lo que hay debajo (blend_disabled) a partir de la textura de pantalla.
//
// IMPORTANTE: Windows compone la ventana con ALFA PREMULTIPLICADO (el color ya va multiplicado por
// su alfa). Al recortar hay que multiplicar también el color por la máscara; si solo se pone el alfa
// a 0, el color se SUMA al escritorio y lo de fuera de la esquina (fondo, botón rojo...) sigue viéndose.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec2 window_px = vec2(1280.0, 720.0);
uniform float radius_px = 10.0;
uniform vec4 border_color : source_color = vec4(0.65, 0.78, 1.0, 0.20);
uniform float border_px = 1.0;
uniform float border_strength = 1.0;    // 0..1, para hacer aparecer el borde con el fundido del hub

// Distancia con signo a un rectángulo redondeado centrado (negativa dentro).
float sd_round_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec4 src = texture(screen_tex, SCREEN_UV);                   // premultiplicado
	vec2 p = UV * window_px - window_px * 0.5;
	float d = sd_round_box(p, window_px * 0.5, radius_px);
	float inside = clamp(0.5 - d, 0.0, 1.0);                       // antialiasing de 1 px en el contorno
	float band = clamp(d + border_px + 0.5, 0.0, 1.0);             // franja del borde, pegada al contorno
	// Borde mezclado en espacio premultiplicado (su color se escala por la opacidad de lo que hay debajo).
	vec3 col = mix(src.rgb, border_color.rgb * src.a, band * border_color.a * border_strength);
	COLOR = vec4(col, src.a) * inside;
}
