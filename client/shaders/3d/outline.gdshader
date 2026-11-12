shader_type spatial;
// 描边：同一个网格往外鼓一点、只画背面，露出来的那圈就是线（日漫的勾线）。
// 线色是那块颜色压暗、偏一点暖，不是死黑；width 0 就不画。
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec3 col : source_color = vec3(0.2, 0.15, 0.15);
uniform float width = 0.005;

void vertex() {
	VERTEX += normalize(NORMAL) * width;
}

void fragment() {
	ALBEDO = col;
}
