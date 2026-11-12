shader_type canvas_item;
// 前景（贴着镜头的栏杆、灌木）：移轴镜头里离镜头最近的那一截，对不上焦——虚得最厉害，略暗一点，
// 像从镜头边上探进来的一角模型。焦点在人走的那条街上，前景、远景两头虚，中间清楚，整张画才像桌上的微缩模型。
// 取样：中心一下 + 内外两圈各六下（一共十三下），再借 mipmap 把取样之间的缝抹平，散景圆而软。

uniform float blur = 2.4;            // mip 偏移（贴图有 mip）
uniform float spread = 7.0;          // 盘状取样的外圈半径（贴图像素）
uniform vec2 tex_px = vec2(2048.0, 240.0);
uniform vec3 shade : source_color = vec3(0.16, 0.20, 0.24);
uniform float darken = 0.32;         // 往暗色压多少（不压成剪影：微缩模型的前景还是有颜色的，只是虚）
uniform float night = 0.0;

void fragment() {
	vec2 o = spread / tex_px;
	vec4 c = texture(TEXTURE, UV, blur) * 0.16;
	// 内圈：半径 0.5，六个方向；外圈：半径 1，转半格的六个方向
	for (int i = 0; i < 6; i++) {
		float a = float(i) * 1.0471976;
		c += texture(TEXTURE, UV + vec2(cos(a), sin(a)) * o * 0.5, blur) * 0.08;
		c += texture(TEXTURE, UV + vec2(cos(a + 0.5235988), sin(a + 0.5235988)) * o, blur) * 0.06;
	}
	vec3 col = mix(c.rgb, shade * (c.rgb + 0.25), darken);
	col = mix(col, col * vec3(0.34, 0.38, 0.66), night * 0.85);
	COLOR = vec4(col, c.a * 0.96) * COLOR;
}
