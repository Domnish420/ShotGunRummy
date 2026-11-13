// Easter egg screen filters, laid over everything (the table and the words):
//   mode 1  POCKET MODE: four shades of handheld green, chunky dithering
//   mode 2  FILM NOIR: black and white, high contrast, a little grain
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform int mode = 0;
uniform float time_s = 0.0;

const vec3 GB[4] = vec3[4](
	vec3(0.06, 0.22, 0.06),
	vec3(0.19, 0.38, 0.19),
	vec3(0.55, 0.67, 0.06),
	vec3(0.61, 0.74, 0.06));

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	if (mode == 1) {
		// a 2x2 ordered dither between the four greens
		vec2 cell = floor(FRAGCOORD.xy / 2.0);
		float d = mod(cell.x + cell.y * 2.0, 4.0) / 4.0 - 0.375;
		float v = clamp(pow(l, 0.8) * 3.0 + d * 0.9, 0.0, 3.0);
		COLOR = vec4(GB[int(floor(v + 0.5))], 1.0);
	} else {
		float g = (hash(FRAGCOORD.xy + time_s) - 0.5) * 0.06;
		float v = smoothstep(0.04, 0.85, l) + g;
		COLOR = vec4(vec3(v), 1.0);
	}
}
