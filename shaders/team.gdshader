shader_type canvas_item;
// Paints a player's color onto a unit: wherever the sprite holds one of the three placeholder colors
// (Art.TEAM_KEY: magenta, in light, mid and dark), it is swapped for the owner's light, mid or dark
// color. Everything else is drawn as it is.

uniform vec3 team_light : source_color = vec3(1.0, 0.0, 1.0);
uniform vec3 team_mid : source_color = vec3(0.78, 0.0, 0.78);
uniform vec3 team_dark : source_color = vec3(0.55, 0.0, 0.55);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a > 0.5) {
		if (distance(c.rgb, vec3(1.0, 0.0, 1.0)) < 0.07) {
			c.rgb = team_light;
		} else if (distance(c.rgb, vec3(0.784, 0.0, 0.784)) < 0.07) {
			c.rgb = team_mid;
		} else if (distance(c.rgb, vec3(0.549, 0.0, 0.549)) < 0.07) {
			c.rgb = team_dark;
		}
	}
	COLOR = c;
}
