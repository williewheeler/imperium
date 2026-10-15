shader_type canvas_item;
// The minimap's land, drawn on the parchment: wherever the ground has never been seen, nothing is drawn and
// the parchment shows through; what has been seen is inked in, a little dimmer where nobody is looking now.

uniform sampler2D fog : filter_nearest; // alpha: 1 never seen, about 0.55 seen before, 0 in sight

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = texture(fog, UV).a;
	vec3 ink = mix(c.rgb, vec3(0.86, 0.74, 0.5), 0.12); // a touch of the parchment's warmth in the colors
	COLOR = vec4(ink * (1.0 - a * 0.35), a > 0.99 ? 0.0 : 1.0);
}
