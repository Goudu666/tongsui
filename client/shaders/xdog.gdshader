shader_type canvas_item;
// 「显影」：照片 → 手绘墨线 + 双色孔版套印
//
// XDoG（eXtended Difference of Gaussians, Winnemöller et al. 2012）：
//   D = G_σ(I) − τ·G_kσ(I)
//   E = 1                       , D ≥ ε
//       1 + tanh(φ·(D − ε))     , D < ε
// 再按亮度分三层：暗部 → 墨，中间调 → 专色（青或梅），高光 → 纸。
// 两个专色层各自偏移几像素，模拟孔版印刷的套色错位。
//
// 用法：TextureRect 显示照片，material 用这个 shader。M4 会把结果烘焙成回忆卡图片。

uniform float sigma : hint_range(0.5, 4.0) = 1.2;
uniform float k = 1.6;
uniform float tau : hint_range(0.9, 1.0) = 0.985;
uniform float epsilon : hint_range(-0.1, 0.2) = 0.02;
uniform float phi : hint_range(1.0, 200.0) = 60.0;
uniform vec4 ink : source_color = vec4(0.169, 0.165, 0.2, 1.0);
uniform vec4 spot : source_color = vec4(0.18, 0.545, 0.478, 1.0); // 青；梅用 (0.851, 0.282, 0.373)
uniform vec4 paper : source_color = vec4(0.957, 0.933, 0.882, 1.0);
uniform vec2 misregister = vec2(2.0, -1.5); // 套色错位（像素）
uniform float tone_low : hint_range(0.0, 1.0) = 0.28;
uniform float tone_high : hint_range(0.0, 1.0) = 0.62;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// 可分离高斯在 shader 里需要两个 pass；为了单 pass 可用，这里用 9×9 网格的二维近似，够手机实时预览。
float gauss(sampler2D tex, vec2 uv, vec2 px, float s) {
	float sum = 0.0;
	float wsum = 0.0;
	for (int x = -4; x <= 4; x++) {
		for (int y = -4; y <= 4; y++) {
			vec2 o = vec2(float(x), float(y)) * s * 0.75;
			float w = exp(-dot(o, o) / (2.0 * s * s));
			sum += luma(texture(tex, uv + o * px).rgb) * w;
			wsum += w;
		}
	}
	return sum / wsum;
}

float xdog(sampler2D tex, vec2 uv, vec2 px) {
	float g1 = gauss(tex, uv, px, sigma);
	float g2 = gauss(tex, uv, px, sigma * k);
	float d = g1 - tau * g2;
	return d >= epsilon ? 1.0 : 1.0 + tanh(phi * (d - epsilon));
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float line = clamp(xdog(TEXTURE, UV, px), 0.0, 1.0);

	// 专色层：用错位后的亮度决定是否上色
	float l_spot = luma(texture(TEXTURE, UV + misregister * px).rgb);
	float spot_mask = smoothstep(tone_high, tone_low, l_spot);

	vec3 c = paper.rgb;
	c = mix(c, c * spot.rgb, spot_mask * 0.9);      // 正片叠底上专色
	c = mix(ink.rgb, c, line);                       // 墨线压在最上面
	COLOR = vec4(c, texture(TEXTURE, UV).a);
}
