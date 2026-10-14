shader_type canvas_item;
#include "res://shaders/terrace.gdshaderinc"
// Draws the fog texture over the terraced ground: each pixel looks up the fog at the tile it shows.

uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec2 origin = vec2(0.0);

varying vec2 world;

void vertex() {
	world = VERTEX + origin;
}

void fragment() {
	int cliff;
	float wall_v;
	vec2 g = surface(floor(world), cliff, wall_v);
	if (g.x < 0.0 || g.y < 0.0 || g.x >= map_size.x || g.y >= map_size.y) {
		COLOR = vec4(0.0);
	} else {
		COLOR = texture(fog_tex, g / map_size);
	}
}
