shader_type canvas_item;
// "印出来"的转场：一张空白纸盖住画面，网点状的洞从左往右一排排张开（横屏：顺着长边走），
// 像刮板走过网版，底下的画面一点点印上来。progress：0 全盖住 ~ 1 全露出。

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float cell = 30.0;      // 网点间距（屏幕像素）
uniform float spread = 0.85;    // 刮板的"坡"有多长
uniform vec4 ink : source_color = vec4(0.957, 0.933, 0.882, 1.0);

void fragment() {
	float g = SCREEN_UV.x * 0.82 + SCREEN_UV.y * 0.18;
	float local = clamp(progress * (1.0 + spread) - g * spread, 0.0, 1.0);
	vec2 q = mat2(vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071)) * FRAGCOORD.xy / cell;
	float d = length(fract(q) - 0.5);
	float r = local * 0.76;
	float a = smoothstep(r - 0.035, r + 0.035, d);
	a = mix(a, 0.0, step(0.999, local));
	COLOR = vec4(ink.rgb, ink.a * a);
}
