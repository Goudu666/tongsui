shader_type canvas_item;
// 菜单（ui/system_menu.gd）后面压暗的那一层：一层墨，上面一层很淡的方点（像素画）。
// 网点在这里算，不在 GDScript 里一颗颗画（那样每帧几千次绘制调用）。cell 跟着真实分辨率走（同 fx.gd _start）。

uniform float cell = 22.0;  // 网点间距（屏幕像素）
uniform vec4 ink : source_color = vec4(0.169, 0.165, 0.2, 0.8);
uniform vec4 dot_color : source_color = vec4(0.29, 0.208, 0.275, 0.55);

void fragment() {
	// 像素版：方点，隔行错开半格（像素画里的棋盘抖动放大了），边是硬的
	vec2 q = FRAGCOORD.xy / cell;
	q.x += 0.5 * mod(floor(q.y), 2.0);
	vec2 f = abs(fract(q) - 0.5);
	float d = max(f.x, f.y);
	float a2 = dot_color.a * step(d, 0.12);
	float a1 = ink.a;
	float a = a2 + a1 * (1.0 - a2);
	vec3 rgb = (dot_color.rgb * a2 + ink.rgb * a1 * (1.0 - a2)) / max(a, 0.0001);
	COLOR = vec4(rgb, a);
}
