shader_type canvas_item;
// 菜单（ui/system_menu.gd）后面压暗的那一层：一层墨，上面一层很淡的叠印色网点。
// 网点在这里算，不在 GDScript 里一颗颗画（那样每帧几千次绘制调用）。cell 跟着真实分辨率走（同 fx.gd _start）。

uniform float cell = 22.0;  // 网点间距（屏幕像素）
uniform vec4 ink : source_color = vec4(0.169, 0.165, 0.2, 0.8);
uniform vec4 dot_color : source_color = vec4(0.29, 0.208, 0.275, 0.55);

void fragment() {
	vec2 q = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * FRAGCOORD.xy / cell;
	float d = length(fract(q) - 0.5);
	float r = 0.1;
	float a2 = dot_color.a * (1.0 - smoothstep(r - 0.04, r + 0.04, d));
	float a1 = ink.a;
	float a = a2 + a1 * (1.0 - a2);
	vec3 rgb = (dot_color.rgb * a2 + ink.rgb * a1 * (1.0 - a2)) / max(a, 0.0001);
	COLOR = vec4(rgb, a);
}
