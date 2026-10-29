// The gritty late-PS2 look, applied to the low-res 3D image:
// ordered (Bayer) dithering into a limited palette, film grain, a warm
// colour grade, a touch of colour fringing and a dark vignette.
shader_type canvas_item;

uniform float levels = 28.0;        // colour steps per channel
uniform float dither = 1.0;         // 0 = no dithering
uniform float grain = 0.05;
uniform float vignette = 0.6;
uniform float fringe = 0.0016;      // chromatic aberration at the edges
uniform vec3 grade = vec3(1.04, 0.97, 0.86);
uniform float contrast = 1.12;
uniform float lift = 0.012;         // raised blacks, like old CRT TVs

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 centre = uv - 0.5;
	float edge = dot(centre, centre);
	vec2 off = centre * fringe * edge * 8.0;
	vec3 col;
	col.r = texture(TEXTURE, uv + off).r;
	col.g = texture(TEXTURE, uv).g;
	col.b = texture(TEXTURE, uv - off).b;

	// grade: warm, slightly crushed, contrasty
	col *= grade;
	col = (col - 0.5) * contrast + 0.5;
	col = max(col, vec3(0.0)) + lift;

	// grain, a fresh pattern ~24 times a second, per low-res pixel
	vec2 pixel = floor(uv / TEXTURE_PIXEL_SIZE);
	float n = hash(pixel + floor(TIME * 24.0) * 17.0) - 0.5;
	col += n * grain;

	// vignette
	col *= 1.0 - vignette * smoothstep(0.08, 0.5, edge);

	// ordered dithering into a small palette
	int bx = int(mod(pixel.x, 4.0));
	int by = int(mod(pixel.y, 4.0));
	float threshold = (BAYER[by * 4 + bx] + 0.5) / 16.0 - 0.5;
	col = floor(col * levels + threshold * dither + 0.5) / levels;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
