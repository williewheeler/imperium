// Terraced ground, shared by the ground and fog shaders. The land stands on levels 0..max_level,
// each lifting everything by lift_px screen pixels, so a screen pixel has to be traced back to the
// terrace surface (or cliff face) that is drawn there.

uniform sampler2D levels : filter_nearest, repeat_disable; // terrace of each tile, one texel per tile
uniform vec2 map_size = vec2(80.0, 80.0);
uniform float lift_px = 5.0;
uniform float max_level = 5.0;

int level_at(vec2 g) {
	ivec2 t = ivec2(floor(g));
	if (t.x < 0 || t.y < 0 || t.x >= int(map_size.x) || t.y >= int(map_size.y)) {
		return 0;
	}
	return int(texelFetch(levels, t, 0).r * 255.0 + 0.5);
}

// The tile-space point drawn at world pixel `wp`. Walks along the line of sight from the highest
// terrace down to the first surface that covers the pixel. `cliff` is 0 for a level top, 1 for a
// wall facing down-left (lit), 2 for a wall facing down-right (shaded); `wall_v` is how far down
// the wall the pixel is (0 at the lip, 1 at the foot).
vec2 surface(vec2 wp, out int cliff, out float wall_v) {
	float diff = wp.x / 16.0;
	float top = wp.y / 8.0 + max_level * lift_px / 8.0;
	int steps = int(ceil(max_level * lift_px / 8.0 / 0.125)) + 1;
	vec2 g = vec2((top + diff) * 0.5, (top - diff) * 0.5);
	vec2 prev = g;
	cliff = 0;
	wall_v = 0.0;
	for (int i = 0; i <= steps; i++) {
		float sum = top - float(i) * 0.125;
		g = vec2((sum + diff) * 0.5, (sum - diff) * 0.5);
		int l = level_at(g);
		if (sum * 8.0 - float(l) * lift_px <= wp.y) {
			if (i > 0) {
				int lp = level_at(prev);
				if (l > lp) {
					ivec2 a = ivec2(floor(prev));
					ivec2 b = ivec2(floor(g));
					cliff = (a.y != b.y) ? 1 : 2;
					wall_v = clamp((wp.y - (sum * 8.0 - float(l) * lift_px)) / (float(l - lp) * lift_px), 0.0, 1.0);
				}
			}
			return g;
		}
		prev = g;
	}
	return g;
}
