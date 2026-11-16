// A soft cone of light under the lamp: brightest at the centre and the
// top, fading out at the edges and towards the table.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 colour = vec3(1.0, 0.85, 0.6);
uniform float strength = 0.16;
uniform float flicker = 1.0;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = pow(facing, 2.5);
	float down = 1.0 - UV.y * 0.75; // UV.y runs top (0) to bottom (1)
	ALBEDO = colour;
	ALPHA = strength * soft * down * flicker;
}
