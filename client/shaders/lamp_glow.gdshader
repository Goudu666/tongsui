shader_type canvas_item;
render_mode blend_add, unshaded;
// 灯晕：夜版（night_plate，正片叠底）只能把画压暗、在灯下少压一点，提不亮。
// 这一层用同一张烘好的灯光图往上「加」一点暖光：灯泡那一小团最亮，往外一圈雾蒙蒙地散开。
// 傍晚灯刚亮时淡，深夜最足；雨雪天空气里水汽多，晕更大。

uniform sampler2D light_map : filter_linear, repeat_disable;
uniform float night = 0.0;
uniform float wet = 0.0;
uniform vec3 lamp : source_color = vec3(1.0, 0.72, 0.38);
uniform vec2 map_size = vec2(2400.0, 1600.0);  // 像素版：按 3 世界像素一个点取样、分档
const float PX = 3.0;

void fragment() {
	vec2 pw = (floor(UV * map_size / PX) + 0.5) * PX;
	float l = texture(light_map, pw / map_size).r;
	l = floor(l * 7.0 + 0.5) / 7.0;   // 光一圈一圈的，一档一档往外淡
	float core = pow(l, 3.0);
	float haze = pow(l, 1.4) * (0.35 + wet * 0.35);
	float a = (core * 0.30 + haze * 0.16) * night;
	COLOR = vec4(lamp * a, 1.0);
}
