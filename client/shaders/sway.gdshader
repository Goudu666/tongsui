shader_type canvas_item;
// 树随风晃：越往上晃得越多，柳条还会一绺一绺地飘（按高度错开相位）。
// 贴图四周留了边，所以晃起来不会被切掉。

uniform float amp = 6.0;          // 树梢最多晃多少（贴图像素）
uniform float speed = 1.1;
uniform float phase = 0.0;
uniform float strands = 0.0;      // 柳树 1：一绺一绺地飘
uniform vec2 tex_px = vec2(800.0, 880.0);

void fragment() {
	float h = 1.0 - UV.y;                 // 0 树根 ~ 1 树梢
	float k = h * h;
	float t = TIME * speed + phase;
	float dx = (sin(t) * 0.7 + sin(t * 2.3 + 1.7) * 0.3) * amp * k;
	dx += strands * sin(t * 1.7 + UV.x * 18.0 + UV.y * 9.0) * amp * 0.6 * smoothstep(0.1, 0.7, UV.y) * h;
	vec2 uv = UV - vec2(dx / tex_px.x, 0.0);
	COLOR = texture(TEXTURE, uv) * COLOR;
}
