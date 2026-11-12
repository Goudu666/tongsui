shader_type canvas_item;
// 转场：一张纸盖住画面，从左往右一格一格地掀开（横屏：顺着长边走）。
// 像素版：格子是方块，每格什么时候掀开按 4×4 拜耳阈值排好次序，像老游戏机换画面。
// progress：0 全盖住 ~ 1 全露出。

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float cell = 30.0;      // 一格多大（屏幕像素）
uniform float spread = 0.85;    // 从左到右的「坡」有多长
uniform vec4 ink : source_color = vec4(0.957, 0.933, 0.882, 1.0);

float bayer(vec2 q) {
	int x = int(mod(q.x, 4.0));
	int y = int(mod(q.y, 4.0));
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}

void fragment() {
	vec2 q = floor(FRAGCOORD.xy / cell);
	vec2 c = (q + 0.5) * cell * SCREEN_PIXEL_SIZE;   // 这一格的中心（0~1）
	float g = c.x * 0.82 + c.y * 0.18;
	float local = clamp(progress * (1.0 + spread) - g * spread, 0.0, 1.0);
	float a = step(local, bayer(q));
	a = mix(a, 0.0, step(0.999, local));
	COLOR = vec4(ink.rgb, ink.a * a);
}
