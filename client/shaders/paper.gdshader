shader_type canvas_item;
// 米白纸张：细颗粒 + 极淡的纤维纹 + 四角轻微压暗。全屏一层，便宜。

uniform vec4 paper_color : source_color = vec4(0.957, 0.933, 0.882, 1.0);
uniform float grain = 0.035;
uniform float vignette = 0.10;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 px = FRAGCOORD.xy;
	float n = hash(floor(px)) - 0.5;
	float fiber = sin(px.y * 0.35 + sin(px.x * 0.02) * 6.0) * 0.5 + 0.5;
	vec2 d = UV - 0.5;
	float v = 1.0 - dot(d, d) * vignette * 2.0;
	vec3 c = paper_color.rgb * v + n * grain - fiber * 0.008;
	COLOR = vec4(c, 1.0);
}
