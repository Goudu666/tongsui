shader_type canvas_item;
render_mode unshaded;
// 远景、中景（tools/art/layers.py）：离得越远越像天色（空气透视），
// 傍晚整条印上一层暖色，夜里压成靛蓝，lit_tex 里记着的窗一扇扇亮起来，隔一会儿有一扇灭、一扇亮。

uniform sampler2D lit_tex : filter_linear, repeat_enable;
uniform float night = 0.0;
uniform float dusk = 0.0;
uniform float dawn = 0.0;
uniform float haze = 0.3;        // 0 不透视 ~ 1 全是天色
uniform vec3 haze_col : source_color = vec3(0.90, 0.92, 0.88);
uniform float seed = 0.0;
uniform vec2 tex_size = vec2(2048.0, 620.0);
uniform float blur = 0.0;        // 景深：远的虚一点（mip 偏移）

const vec3 NIGHT = vec3(0.17, 0.24, 0.50);
const vec3 DUSK = vec3(0.98, 0.70, 0.52);
const vec3 LAMP = vec3(1.0, 0.86, 0.50);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV, blur);
	vec3 col = mix(c.rgb, haze_col, haze);
	col *= mix(vec3(1.0), DUSK, dusk * 0.4 + dawn * 0.15);
	col *= mix(vec3(1.0), NIGHT * 1.15, night * 0.8);
	float l = texture(lit_tex, UV).r;
	if (l > 0.01 && night > 0.01) {
		// 一扇窗一个格子：每格自己决定亮不亮、什么时候换
		vec2 cellp = floor(UV * tex_size / vec2(10.0, 12.0));
		float h = hash(cellp + seed);
		float on = step(0.22, fract(h * 7.3 + floor(TIME * 0.05 + h * 9.0) * 0.618));
		col = mix(col, LAMP, l * night * on * 0.95);
	}
	COLOR = vec4(col, c.a);
}
