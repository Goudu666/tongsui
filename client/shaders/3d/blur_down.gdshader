shader_type canvas_item;
// 移轴虚化的第一步：把实时 3D 的画面缩到四分之一、顺手糊一下（十六个双线性取样盖住 8×8 个原像素）
uniform sampler2D src : filter_linear;
uniform vec2 src_px = vec2(0.00052, 0.00093);

void fragment() {
	vec3 c = vec3(0.0);
	float w = 0.0;
	for (int y = -2; y <= 1; y++) {
		for (int x = -2; x <= 1; x++) {
			vec2 o = (vec2(float(x), float(y)) * 2.0 + 1.0) * src_px;
			float k = 1.0 - length(vec2(float(x) + 0.5, float(y) + 0.5)) * 0.18;
			c += texture(src, UV + o).rgb * k;
			w += k;
		}
	}
	COLOR = vec4(c / w, 1.0);
}
