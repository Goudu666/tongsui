shader_type canvas_item;
// 转场：一张纸盖住画面，中间开一个边缘很软的圆洞，慢慢张大，像镜头的光圈打开、底下的模型一点点露出来。
// 洞的中心略偏下（人站的那一条），边缘柔化、带一点点不规则，洞边那一圈纸微微发暗，像纸被掀起来的影子。
// progress：0 全盖住 ~ 1 全露出。cell 是 fx.gd 按真实分辨率算好的长度单位（屏幕像素），用来定边缘多软。

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float cell = 30.0;      // 长度单位（屏幕像素）：边缘软多宽跟着它走，手机电脑看着一样
uniform float spread = 0.85;    // （旧接口，不用）
uniform vec4 ink : source_color = vec4(0.957, 0.933, 0.882, 1.0);

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;  // 宽 / 高
	vec2 c = vec2(0.5, 0.56);
	vec2 p = (SCREEN_UV - c) * vec2(aspect, 1.0);
	float d = length(p);
	// 边缘一点点不规则（按角度起伏，整数倍频率，绕一圈接得上），不像电脑画的正圆
	float ang = atan(p.y, p.x + 0.00001);
	d *= 1.0 + (sin(ang * 3.0 + 1.3) * 0.6 + sin(ang * 5.0 + 4.1) * 0.4) * 0.025;
	float feather = cell * SCREEN_PIXEL_SIZE.y * 3.2;          // 软边宽（以屏高为 1）
	float r_max = length(vec2(aspect * 0.5, 0.56)) * 1.04;     // 到最远那个角
	float e = progress;   // fx.gd 的补间已经是缓入缓出
	float r = mix(-feather, r_max + feather, e);
	float a = smoothstep(r - feather, r + feather, d);
	// 洞边那一圈纸微微发暗（掀起来的影子）
	float rim = smoothstep(r - feather, r + feather * 0.6, d) * (1.0 - smoothstep(r + feather * 0.6, r + feather * 3.0, d));
	vec3 rgb = ink.rgb * (1.0 - rim * 0.10);
	a *= 1.0 - step(0.999, progress);
	COLOR = vec4(rgb, ink.a * a);
}
