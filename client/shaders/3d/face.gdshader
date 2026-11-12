shader_type spatial;
// 主角的头：皮肤 + 手绘的脸（眼睛、眉毛、嘴、腮红画在球面上，像涂装过的手办）。
// 物体空间里头心在原点、脸朝 +Z；按球面经纬算位置，放多大都不糊。
// blink 眨眼（0 睁 1 闭）、smile 嘴角（-1 撇 1 笑）、open 张嘴、look 眼珠往哪瞟
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 skin : source_color = vec3(0.98, 0.84, 0.74);
uniform vec3 blush_col : source_color = vec3(0.96, 0.55, 0.52);
uniform vec3 iris : source_color = vec3(0.17, 0.11, 0.09);
uniform vec3 brow_col : source_color = vec3(0.15, 0.11, 0.1);
uniform vec3 lip : source_color = vec3(0.62, 0.25, 0.25);
uniform float eye_gap = 0.34;     // 两眼隔多宽（弧度）
uniform float eye_h = -0.06;      // 眼睛高低（纬度，弧度）
uniform float eye_w = 0.085;
uniform float eye_tall = 0.12;
uniform float lash = 0.0;         // 1 = 上睫毛加粗（梅）
uniform float blink = 0.0;
uniform float smile = 0.6;
uniform float open = 0.0;
uniform vec2 look = vec2(0.0);
uniform float blush = 0.55;
uniform float age = 0.0;          // 0 小孩 … 1 老人：眼睛小一点、加两道细纹
uniform float wet = 0.0;

varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

float ell(vec2 p, vec2 c, vec2 r) {
	vec2 d = (p - c) / r;
	return length(d);
}

void fragment() {
	vec3 n = normalize(obj);
	float u = atan(n.x, n.z);      // 横：0 是正脸
	float v = asin(clamp(n.y, -1.0, 1.0)); // 竖
	vec2 p = vec2(u, v);
	float aa = fwidth(u) * 1.2 + 0.002;
	vec3 col = skin;
	// 脸颊下方略暖、额头略亮：手办涂装的渐变
	col *= mix(1.0, 0.94, smoothstep(0.1, -0.6, v));
	// 腮红
	float bl = 0.0;
	for (int s = -1; s <= 1; s += 2) {
		float d = ell(p, vec2(float(s) * (eye_gap + 0.13), eye_h - 0.17), vec2(0.13, 0.07));
		bl = max(bl, 1.0 - smoothstep(0.2, 1.0, d));
	}
	col = mix(col, blush_col, bl * blush * 0.55);
	float ew = eye_w * (1.0 - age * 0.18);
	float et = eye_tall * (1.0 - age * 0.25);
	float open_eye = 1.0 - blink;
	for (int s = -1; s <= 1; s += 2) {
		vec2 c = vec2(float(s) * eye_gap, eye_h);
		// 眼睛：竖着的椭圆，眨眼时压扁（往下合）
		float th = max(et * open_eye, 0.004);
		vec2 cc = c + vec2(0.0, -et * (1.0 - open_eye) * 0.4);
		float d = ell(p, cc + look * vec2(0.02, 0.015), vec2(ew, th));
		float e = 1.0 - smoothstep(1.0 - aa / ew * 2.0, 1.0, d);
		vec3 ec = iris;
		// 眼珠下半透一点暖色（玻璃眼的感觉）
		ec = mix(ec, ec * 2.4 + vec3(0.06, 0.03, 0.0), smoothstep(0.0, -1.0, (p.y - cc.y) / th) * 0.5);
		col = mix(col, ec, e);
		// 高光：两个小白点
		float h1 = ell(p, cc + vec2(-0.025 * float(s) * 0.0 - 0.022, th * 0.42), vec2(ew * 0.34, th * 0.24));
		float h2 = ell(p, cc + vec2(0.024, -th * 0.4), vec2(ew * 0.16, th * 0.1));
		float hl = (1.0 - smoothstep(0.7, 1.0, h1)) + (1.0 - smoothstep(0.6, 1.0, h2)) * 0.8;
		col = mix(col, vec3(1.0), clamp(hl, 0.0, 1.0) * e * step(0.25, open_eye));
		// 闭眼：一道弯弯的线
		float lid = abs(p.y - (c.y - et * 0.35 + 0.35 * pow((p.x - c.x) / ew, 2.0) * 0.03)) ;
		float closed = (1.0 - smoothstep(0.006, 0.006 + aa, lid)) * step(abs(p.x - c.x), ew * 1.1) * step(0.7, blink);
		col = mix(col, iris, closed);
		// 上睫毛：眼睛上沿一道（梅更粗、眼尾翘一点）
		float top = cc.y + th * 0.92;
		float lx = (p.x - c.x) / (ew * 1.25);
		float curve = top + (1.0 - lx * lx) * 0.012 + max(0.0, lx * float(s)) * lash * 0.02;
		float lashd = abs(p.y - curve);
		float lw = 0.006 + lash * 0.006;
		float lm = (1.0 - smoothstep(lw, lw + aa, lashd)) * step(abs(lx), 1.0) * step(0.25, open_eye);
		col = mix(col, iris * 0.6, lm);
		// 眉毛：短短一道，略弯
		float bx = (p.x - (c.x + float(s) * 0.01)) / 0.085;
		// 里头那端略高（温和），不往下压（压下来像生气）
		float by = c.y + et + 0.11 + (1.0 - bx * bx) * 0.014 - (p.x - c.x) * float(s) * 0.12;
		float bd = abs(p.y - by);
		float bw = 0.0065 * (1.0 - bx * bx * 0.5);
		float bm = (1.0 - smoothstep(bw, bw + aa, bd)) * step(abs(bx), 1.0);
		col = mix(col, brow_col, bm * 0.7);
		// 老了：眼尾两道细纹
		if (age > 0.5) {
			vec2 q = p - (c + vec2(float(s) * (ew + 0.03), 0.0));
			float wr = abs(q.y - q.x * float(s) * 0.4) ;
			float wm = (1.0 - smoothstep(0.003, 0.003 + aa, wr)) * step(abs(q.x), 0.03) * (age - 0.5) * 1.4;
			col = mix(col, col * 0.75, wm);
		}
	}
	// 嘴：一道弧（smile 正就往上弯）；张嘴是个小椭圆
	vec2 m = vec2(0.0, eye_h - 0.27);
	float mx = p.x / 0.07;
	float my = m.y + smile * 0.022 * (mx * mx - 0.4);
	float md = abs(p.y - my);
	float mm = (1.0 - smoothstep(0.008, 0.008 + aa, md)) * step(abs(mx), 1.0);
	float om = 1.0 - smoothstep(0.9, 1.0, ell(p, m + vec2(0.0, -0.01), vec2(0.045, 0.04 * open + 0.001)));
	col = mix(col, lip, max(mm * (1.0 - open), om * step(0.05, open)));
	// 鼻子：一点点暖色的影
	float nd = ell(p, vec2(0.0, eye_h - 0.14), vec2(0.022, 0.016));
	col = mix(col, col * 0.86, (1.0 - smoothstep(0.4, 1.0, nd)) * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.55 - wet * 0.2;
	SPECULAR = 0.35;
}
