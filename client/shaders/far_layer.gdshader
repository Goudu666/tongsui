shader_type canvas_item;
render_mode unshaded;
// 远景、中景：模型桌后头的街区。离得越远越像天色（空气透视），
// 傍晚整条染上一层暖色，夜里压成蓝紫，lit_tex 里记着的窗一扇扇亮起来，隔一会儿有一扇慢慢灭、一扇慢慢亮。
// 移轴景深：镜头对焦在人走的那条街上，后面的街区柔柔地虚掉（blur，贴图像素半径），越远越虚——
// 中心一下 + 一圈八下的盘状取样，再借一点 mipmap 把取样之间的缝抹平。一共九下，手机上也扛得住。

uniform sampler2D lit_tex : filter_linear_mipmap, repeat_enable;
uniform float night = 0.0;
uniform float dusk = 0.0;
uniform float dawn = 0.0;
uniform float haze = 0.3;        // 0 不透视 ~ 1 全是天色
uniform vec3 haze_col : source_color = vec3(0.90, 0.92, 0.88);
uniform float seed = 0.0;
uniform vec2 tex_size = vec2(2048.0, 620.0);
uniform float blur = 0.0;        // 景深：虚多少（贴图像素半径，0 = 不虚）

const vec3 NIGHT = vec3(0.24, 0.27, 0.56);
const vec3 DUSK = vec3(0.98, 0.72, 0.56);
const vec3 LAMP = vec3(1.0, 0.84, 0.54);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// 一扇窗在第 n 个时段亮不亮
float win_on(float h, float n) {
	return step(0.22, fract(h * 7.3 + n * 0.618));
}

void fragment() {
	vec4 c;
	float l;
	if (blur > 0.05) {
		// 景深只借 mipmap：一下取样（三线性把相邻两级 mip 混开），和九下盘状取样看不出差别，手机上省八成的填充
		float lod = log2(1.0 + blur) * 0.9;
		c = texture(TEXTURE, UV, lod);
		l = texture(lit_tex, UV, lod).r;
	} else {
		c = texture(TEXTURE, UV);
		l = texture(lit_tex, UV).r;
	}
	vec3 col = mix(c.rgb, haze_col, haze);
	col *= mix(vec3(1.0), DUSK, dusk * 0.4 + dawn * 0.15);
	col *= mix(vec3(1.0), NIGHT * 1.15, night * 0.8);
	if (l > 0.01 && night > 0.01) {
		// 一扇窗一个格子：每格自己决定亮不亮、什么时候换；换的时候用两三秒慢慢淡过去，不是一下跳
		vec2 cellp = floor(UV * tex_size / vec2(10.0, 12.0));
		float h = hash(cellp + seed);
		float t = TIME * 0.05 + h * 9.0;
		float n = floor(t);
		float on = mix(win_on(h, n), win_on(h, n + 1.0), smoothstep(0.88, 1.0, fract(t)));
		// 窗光往外微微晕开（虚掉的远景里像一颗颗柔和的光斑）
		vec3 warm = mix(LAMP, vec3(1.0, 0.95, 0.82), smoothstep(0.6, 1.0, l));
		col = mix(col, warm, clamp(l * 1.1, 0.0, 1.0) * night * on * 0.95);
	}
	COLOR = vec4(col, c.a);
}
