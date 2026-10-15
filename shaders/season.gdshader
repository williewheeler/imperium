shader_type canvas_item;
// Dresses trees for the snowy and desert grounds: in the snow the upper crown is white and the lower
// foliage frosted; in the desert the green is parched toward dry olive and straw.

uniform int style = 1; // 1 snow, 2 desert
uniform float frost_bias = 0.0; // 1 buries the whole sprite in snow (hills), 0 only its upper part (trees)

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	bool leaf = c.g > c.r * 0.95 && c.g > c.b; // green foliage, not the brown trunk
	if (style == 1 && leaf) {
		float top = smoothstep(0.85, 0.2, UV.y);
		float frost = clamp(top * 1.15 - 0.05 + (lum - 0.35) * 0.6 + frost_bias, 0.0, 1.0);
		vec3 snow = mix(vec3(0.78, 0.86, 0.94), vec3(0.97, 0.99, 1.0), step(0.5, frost + fract(sin(dot(floor(UV * 64.0), vec2(12.9898, 78.233))) * 43758.5) * 0.25));
		c.rgb = mix(c.rgb * vec3(0.8, 0.95, 0.95), snow, step(0.38, frost));
	} else if (style == 2 && leaf) {
		c.rgb = vec3(lum * 1.35 + 0.18, lum * 1.12 + 0.12, lum * 0.55 + 0.03);
	}
	COLOR = c;
}
