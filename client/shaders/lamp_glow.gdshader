shader_type canvas_item;
render_mode blend_add, unshaded;
// 灯晕：夜色（night_plate，正片叠底）只能把画压暗、在灯下少压一点，提不亮。
// 这一层用同一张烘好的灯光图往上「加」一点暖光，像模型里的小灯泡透过一层薄雾：
//   · 灯芯：灯泡那一小团，偏白、最亮
//   · 晕：往外一大圈平滑散开的橙黄（灯光图再错开取四下，便宜的泛光），没有一圈圈的台阶
// 傍晚灯刚亮时淡，深夜最足；雨雪天空气里水汽多，晕更大、更亮。

uniform sampler2D light_map : filter_linear, repeat_disable;
uniform float night = 0.0;
uniform float wet = 0.0;
uniform vec3 lamp : source_color = vec3(1.0, 0.72, 0.38);
uniform vec2 map_size = vec2(2400.0, 1600.0);   // 灯光图盖住的世界大小（错开取样按世界像素算）
uniform float bloom_px = 42.0;                   // 晕往外散多远（世界像素）

void fragment() {
	float l = texture(light_map, UV).r;
	// 晕：中心 + 四个斜角，五下平均，边缘比原图更软、更开
	vec2 o = bloom_px / map_size;
	float b = l * 0.36;
	b += texture(light_map, UV + vec2(o.x, o.y)).r * 0.16;
	b += texture(light_map, UV + vec2(-o.x, o.y)).r * 0.16;
	b += texture(light_map, UV + vec2(o.x, -o.y)).r * 0.16;
	b += texture(light_map, UV + vec2(-o.x, -o.y)).r * 0.16;
	float s = smoothstep(0.0, 1.0, l);
	float core = s * s * s;
	float haze = pow(b, 1.6) * (0.40 + wet * 0.45);
	vec3 core_col = mix(lamp, vec3(1.0, 0.95, 0.85), 0.5);
	vec3 rgb = (core_col * core * 0.30 + lamp * haze * 0.20) * night;
	COLOR = vec4(rgb, 1.0);
}
