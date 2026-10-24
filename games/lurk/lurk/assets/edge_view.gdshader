shader_type canvas_item;
// Vista de contornos sobre toda la pantalla: detecta los bordes de lo que hay dibujado (Sobel sobre
// el brillo) y los pinta de un color. Dos usos:
//   - Misil (El Redentor): toda la pantalla pasa a contornos rojos sobre un fondo casi negro.
//   - Radar: contornos verdes SOLO dentro de la onda del sonar (un anillo que se expande desde la nave)
//     y se apagan detrás de ella.
// mode 0 = pantalla completa, mode 1 = anillo.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec4 edge_color : source_color = vec4(1.0, 0.25, 0.3, 1.0);
uniform float amount = 0.0;          // 0..1
uniform int mode = 0;
uniform float keep = 0.12;           // modo 0: cuánto se conserva de la imagen original
uniform vec2 screen_size = vec2(1280.0, 720.0);    // píxeles lógicos del rectángulo a pantalla completa
uniform vec2 ring_center = vec2(0.0);    // modo 1: en los mismos píxeles
uniform float ring_radius = 0.0;
uniform float ring_width = 150.0;        // ancho de la estela detrás del frente de la onda

float luma(vec2 uv) {
	vec3 c = texture(screen_tex, uv).rgb;
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	float tl = luma(uv + px * vec2(-1, -1));
	float t = luma(uv + px * vec2(0, -1));
	float tr = luma(uv + px * vec2(1, -1));
	float l = luma(uv + px * vec2(-1, 0));
	float r = luma(uv + px * vec2(1, 0));
	float bl = luma(uv + px * vec2(-1, 1));
	float b = luma(uv + px * vec2(0, 1));
	float br = luma(uv + px * vec2(1, 1));
	float gx = -tl - 2.0 * l - bl + tr + 2.0 * r + br;
	float gy = -tl - 2.0 * t - tr + bl + 2.0 * b + br;
	float edge = smoothstep(0.04, 0.22, sqrt(gx * gx + gy * gy));
	vec3 base = texture(screen_tex, uv).rgb;
	if (mode == 0) {
		vec3 col = mix(base * keep, edge_color.rgb, edge);
		COLOR = vec4(mix(base, col, amount), 1.0);
	} else {
		float d = distance(UV * screen_size, ring_center);
		// Frente brillante y estela que se desvanece hacia dentro
		float band = smoothstep(ring_radius - ring_width, ring_radius - 6.0, d) * (1.0 - smoothstep(ring_radius - 6.0, ring_radius + 4.0, d));
		COLOR = vec4(edge_color.rgb, edge * band * amount);
	}
}
