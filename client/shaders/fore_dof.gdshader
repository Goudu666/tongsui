shader_type canvas_item;
// 前景（贴着镜头的栏杆、灌木）：离镜头太近，对不上焦——虚一点、暗一点，像从镜头边上探进来的剪影。
// 贴图有 mip，用偏移取低一级再错开几下，便宜的散景。

uniform float blur = 3.2;            // mip 偏移
uniform float spread = 4.5;          // 再错开几个像素（贴图像素）
uniform vec2 tex_px = vec2(2048.0, 240.0);
uniform vec3 shade : source_color = vec3(0.16, 0.20, 0.24);
uniform float darken = 0.62;         // 往剪影色压多少
uniform float night = 0.0;

void fragment() {
	// 像素画：不虚，前景用大一号的点（6 世界像素）+ 压成剪影，靠这个显得近
	vec4 c = texture(TEXTURE, UV);
	vec3 col = mix(c.rgb, shade * (c.rgb + 0.25), darken);
	col = mix(col, col * vec3(0.30, 0.36, 0.62), night * 0.85);
	COLOR = vec4(col, c.a * 0.94) * COLOR;
}
