shader_type canvas_item;
// 菜单（ui/system_menu.gd）后面压暗的那一层：像把模型桌上的灯调暗——
// 一层平滑的墨，四边更深（软暗角），中间偏左（菜单的那一半）透一点暖暖的叠印色，像桌上还亮着一盏小灯。
// 全是平滑渐变，没有网点；不读屏幕，便宜。cell 跟着真实分辨率走（同 fx.gd _start），这里拿来定暗角多软。

uniform float cell = 22.0;  // 长度单位（屏幕像素）
uniform vec4 ink : source_color = vec4(0.169, 0.165, 0.2, 0.8);
uniform vec4 dot_color : source_color = vec4(0.29, 0.208, 0.275, 0.55);   // 中间那一团暖光的颜色

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;  // 宽 / 高
	vec2 p = (SCREEN_UV - vec2(0.42, 0.5)) * vec2(aspect, 1.0);
	float d = length(p);
	float soft = 0.55 + cell * SCREEN_PIXEL_SIZE.y * 2.0;      // 暗角从多远开始往外深（分辨率无关）
	float vig = smoothstep(0.25, soft + 0.55, d);
	// 墨：中间稍薄、四边稍厚
	float a1 = clamp(ink.a * mix(0.88, 1.12, vig), 0.0, 1.0);
	// 暖光：中间一团，往外平滑淡掉
	float glow = (1.0 - smoothstep(0.0, 0.75, d)) * dot_color.a * 0.55;
	vec3 rgb = mix(ink.rgb, dot_color.rgb, glow);
	rgb *= 1.0 - vig * 0.25;
	COLOR = vec4(rgb, a1);
}
