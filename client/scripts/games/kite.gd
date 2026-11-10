extends Control
## 放风筝：搭伴时可以点进去玩的小游戏（规则在 server/src/games.ts）。
## 两个人各只管一头：攥线的手指上下滑，管高低；牵着线跑的手指左右滑，管左右。
## 屏幕上一横一竖两条线，一条是你的、一条是 TA 的，交叉点就是风筝要去的地方；把它送进天上那团「风口」。
## 这里只管画和报手指位置；风筝在哪儿由服务器（或试玩时的 kite_sim.gd）说了算，本地只做插值。

signal input(body: Dictionary)

const P := preload("res://scripts/ui/palette.gd")
const SEND_INTERVAL := 0.1
const STREAKS := 34

var my_role := "qing"
var names := {"qing": "青", "mei": "梅"}

var _t := -3.0            ## 服务器的局内时间（前三秒为负，是开场）
var _d := {}              ## 服务器最新的状态
var _cur := {}            ## 画面上用的（朝 _d 平滑过去）
var _clock := 0.0         ## 本地动画时钟
var _finger := -1.0       ## 我这一头手指给的目标（0~1）；-1 = 还没碰过
var _sent := -1.0
var _send_timer := 0.0
var _streaks: Array = []
var _trail: Array = []    ## 风筝飘带的历史位置


func setup(role: String, p_names: Dictionary) -> void:
	my_role = role
	names = p_names
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in STREAKS:
		_streaks.append({"x": rng.randf(), "h": rng.randf_range(0.12, 1.0), "len": rng.randf_range(0.03, 0.09), "v": rng.randf_range(0.10, 0.22)})


## 服务器（或试玩）发来的一帧
func apply(view: Dictionary) -> void:
	_t = float(view.get("t", _t))
	var d: Variant = view.get("d")
	if d is Dictionary:
		_d = d
		if _cur.is_empty():
			_cur = _d.duplicate()


func holder() -> String:
	return str(_d.get("holder", "qing"))


func i_hold() -> bool:
	return holder() == my_role


func _other() -> String:
	return "mei" if my_role == "qing" else "qing"


# ======================================================================
# 场地：x 0~1 沿河岸，h 0~1 高度 → 屏幕
# ======================================================================

## 河岸线。横屏只有 1080 高：岸下面至少留 250，攥线的人才站得下
func _bank_y() -> float:
	return minf(size.y * 0.86, size.y - 250.0)


func _field() -> Rect2:
	var top := maxf(size.y * 0.15, 220.0)
	return Rect2(70.0, top, size.x - 140.0, _bank_y() - 150.0 - top)


func _to_px(x: float, h: float) -> Vector2:
	var f := _field()
	return Vector2(f.position.x + x * f.size.x, f.end.y - h * f.size.y)


# ======================================================================
# 输入：整块屏幕都是摇杆，只取自己管的那个方向
# ======================================================================

func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.INF
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	var st := event as InputEventScreenTouch
	var sd := event as InputEventScreenDrag
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		pos = mb.position
	elif mm != null and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		pos = mm.position
	elif st != null and st.pressed:
		pos = st.position
	elif sd != null:
		pos = sd.position
	if pos == Vector2.INF or _d.is_empty():
		return
	var f := _field()
	if i_hold():
		_finger = clampf((f.end.y - pos.y) / f.size.y, 0.0, 1.0)
	else:
		_finger = clampf((pos.x - f.position.x) / f.size.x, 0.0, 1.0)
	accept_event()


func _process(delta: float) -> void:
	_clock += delta
	if _d.is_empty():
		queue_redraw()
		return
	# 朝服务器的状态平滑过去（10Hz → 60 帧）
	var k := 1.0 - exp(-14.0 * delta)
	for key in ["kx", "kh", "rx", "line", "wx", "wh", "wr", "prog"]:
		_cur[key] = lerpf(float(_cur.get(key, _d.get(key, 0.0))), float(_d.get(key, 0.0)), k)
	for s in _streaks:
		s.x = fposmod(float(s.x) + float(s.v) * delta, 1.2)
	var kp := _to_px(float(_cur.kx), float(_cur.kh))
	_trail.push_front(kp)
	if _trail.size() > 26:
		_trail.pop_back()
	# 报手指位置：攥线的报线长（高度换算回去），跑的报站位
	_send_timer += delta
	if _finger >= 0.0 and _t >= 0.0 and _send_timer >= SEND_INTERVAL and absf(_finger - _sent) > 0.004:
		_send_timer = 0.0
		_sent = _finger
		if i_hold():
			input.emit({"k": "line", "v": snappedf(clampf((_finger - 0.06) / 0.9, 0.0, 1.0), 0.001)})
		else:
			input.emit({"k": "run", "v": snappedf(_finger, 0.001)})
	queue_redraw()


# ======================================================================
# 画
# ======================================================================

func _draw() -> void:
	var f := P.font()
	var w := size.x
	var bank := _bank_y()
	draw_rect(Rect2(Vector2.ZERO, size), P.PAPER)
	_draw_far_shore(bank - 150.0)
	_draw_river(Rect2(0, bank - 150.0, w, 150.0))
	draw_rect(Rect2(0, bank, w, size.y - bank), P.PAPER_DARK)
	draw_line(Vector2(0, bank), Vector2(w, bank), P.INK, 3.0)
	if _d.is_empty():
		return
	var inside := bool(_d.get("inside", false))
	var snag := bool(_d.get("snag", false))
	var kp := _to_px(float(_cur.kx), float(_cur.kh))
	if snag:
		kp += Vector2(sin(_clock * 40.0) * 5.0, cos(_clock * 33.0) * 3.0)
	_draw_bridge()
	_draw_wind(inside)
	_draw_guides()

	# 两个人和那根线：攥线的站在原地，线先到牵线的人手里，再上天
	var hold_role := holder()
	var run_role := "mei" if hold_role == "qing" else "qing"
	var hold_at := Vector2(w * 0.5, bank + 176.0)
	var run_at := Vector2(_to_px(float(_cur.rx), 0.0).x, bank + 52.0)
	var hand := run_at + Vector2(0, -74)
	draw_line(hold_at + Vector2(0, -60), hand, P.INK, 2.0)
	var sag := Vector2(0, 40.0 + 60.0 * (1.0 - float(_cur.line)))
	var prev := hand
	for i in range(1, 17):
		var u := i / 16.0
		var pt := hand.lerp(kp, u) + sag * sin(u * PI)
		draw_line(prev, pt, P.INK, 2.0)
		prev = pt
	_draw_kid(hold_at, hold_role, true)
	_draw_kid(run_at, run_role, false)
	_draw_kite(kp, inside, snag)
	_draw_hud(f, inside, snag)
	if _t < 0.0:
		_draw_intro(f)


func _draw_far_shore(y: float) -> void:
	# 对岸：一排矮房子和几栋高一点的楼，淡淡一条
	var x := -20.0
	var i := 0
	while x < size.x + 40.0:
		var bw := 46.0 + fmod(i * 37.0, 60.0)
		var bh := 22.0 + fmod(i * 53.0, 54.0) + (70.0 if i % 5 == 3 else 0.0)
		draw_rect(Rect2(x, y - bh, bw, bh), Color(P.INK_SOFT, 0.16))
		draw_rect(Rect2(x, y - bh, bw, bh), Color(P.INK_SOFT, 0.45), false, 1.5)
		x += bw + 6.0
		i += 1
	draw_line(Vector2(0, y), Vector2(size.x, y), Color(P.INK, 0.6), 2.0)


func _draw_river(r: Rect2) -> void:
	draw_rect(r, Color(P.QING, 0.13))
	for i in 14:
		var y := r.position.y + 16.0 + (i % 5) * 28.0
		var x := fposmod(i * 173.0 + _clock * (14.0 + (i % 3) * 6.0), r.size.x + 120.0) - 60.0
		draw_arc(Vector2(x, y), 22.0, PI * 1.15, PI * 1.85, 8, Color(P.QING, 0.55), 2.5)


func _draw_bridge() -> void:
	# 铁桥在左下角：风筝飞得太低会挂上去（kx < 0.3 且 kh < 0.16）
	var a := _to_px(-0.1, 0.0)
	var b := _to_px(0.3, 0.0)
	var top := _to_px(0.0, 0.15).y
	var deck := a.y + 30.0
	draw_line(Vector2(a.x, deck), Vector2(b.x, deck), P.INK, 4.0)
	draw_line(Vector2(a.x, top), Vector2(b.x - 40.0, top), P.INK, 4.0)
	draw_line(Vector2(b.x - 40.0, top), Vector2(b.x, deck), P.INK, 4.0)
	var x := a.x
	var up := true
	while x < b.x - 40.0:
		var nx := minf(x + 62.0, b.x - 40.0)
		if up:
			draw_line(Vector2(x, deck), Vector2(nx, top), Color(P.INK, 0.8), 2.5)
		else:
			draw_line(Vector2(x, top), Vector2(nx, deck), Color(P.INK, 0.8), 2.5)
		draw_line(Vector2(nx, top), Vector2(nx, deck), Color(P.INK, 0.5), 2.0)
		up = not up
		x = nx


func _draw_wind(inside: bool) -> void:
	var c := _to_px(float(_cur.wx), float(_cur.wh))
	var fr := _field()
	var ry := float(_cur.wr) * fr.size.y
	var rx := float(_cur.wr) / 0.6 * fr.size.x
	# 风：横着刮的短线，刮进风口里的那几根变成两色
	for s in _streaks:
		var p := _to_px(float(s.x) - 0.1, float(s.h))
		var q := p + Vector2(float(s.len) * fr.size.x, 0)
		var m := (p + q) * 0.5
		var e := Vector2((m.x - c.x) / rx, (m.y - c.y) / ry).length()
		if e < 1.0:
			var col := P.QING if int(float(s.h) * 100.0) % 2 == 0 else P.MEI
			draw_line(p, q, Color(col, 0.75), 3.0)
		else:
			draw_line(p, q, Color(P.INK_SOFT, 0.32), 2.0)
	# 风口：几段转着的弧。风筝在里面时颜色实起来
	var alpha := 0.85 if inside else 0.4
	draw_set_transform(c, 0.0, Vector2(rx / ry, 1.0))
	for ring in 3:
		var rr := ry * (1.0 - ring * 0.24)
		var spin := _clock * (0.9 - ring * 0.25) * (1.0 if ring % 2 == 0 else -1.0)
		for seg in 5:
			var a0 := spin + seg * TAU / 5.0
			draw_arc(Vector2.ZERO, rr, a0, a0 + TAU / 5.0 * 0.58, 14, Color(P.OVERLAP, alpha * (1.0 - ring * 0.25)), 3.5 - ring * 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_guides() -> void:
	# 一横一竖：攥线的管横线（高低），跑的管竖线（左右）。自己那条跟手，TA 那条看服务器
	var fr := _field()
	var hold_role := holder()
	var run_role := "mei" if hold_role == "qing" else "qing"
	var h := 0.06 + 0.9 * float(_cur.line)
	var x := float(_cur.rx)
	if _finger >= 0.0:
		if i_hold():
			h = _finger
		else:
			x = _finger
	var py := _to_px(0.0, h).y
	var px := _to_px(x, 0.0).x
	_dashed(Vector2(fr.position.x - 40.0, py), Vector2(fr.end.x + 40.0, py), Color(P.role_color(hold_role), 0.55), 3.0 if i_hold() else 2.0)
	_dashed(Vector2(px, fr.position.y - 30.0), Vector2(px, fr.end.y + 20.0), Color(P.role_color(run_role), 0.55), 2.0 if i_hold() else 3.0)
	draw_circle(Vector2(px, py), 9.0, Color(P.OVERLAP, 0.7))


func _dashed(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var total := a.distance_to(b)
	var dir := (b - a) / maxf(total, 1.0)
	var at := 0.0
	while at < total:
		draw_line(a + dir * at, a + dir * minf(at + 22.0, total), color, width)
		at += 36.0


func _draw_kid(at: Vector2, role: String, reel: bool) -> void:
	var c := P.role_color(role)
	var body := Rect2(at + Vector2(-20, -56), Vector2(40, 44))
	draw_rect(Rect2(body.position + Vector2(3, 2), body.size), Color(c, 0.9))
	draw_rect(body, P.INK, false, 3.0)
	draw_circle(at + Vector2(3, -78), 20.0, Color(c, 0.9))
	draw_arc(at + Vector2(0, -80), 20.0, 0, TAU, 28, P.INK, 3.0)
	if reel:  # 线拐子
		draw_rect(Rect2(at + Vector2(-34, -66), Vector2(12, 26)), P.PAPER)
		draw_rect(Rect2(at + Vector2(-34, -66), Vector2(12, 26)), P.INK, false, 2.5)
	var f := P.font()
	var label := "你" if role == my_role else str(names.get(role, P.ROLE_NAME[role]))
	var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string(f, at + Vector2(-tw / 2.0, 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, c)


func _draw_kite(at: Vector2, inside: bool, snag: bool) -> void:
	# 燕子形的风筝：左半青、右半梅，套印略微错位；两条飘带跟在后面
	var lean := 0.0
	if _trail.size() > 4:
		lean = clampf((at.x - (_trail[4] as Vector2).x) * 0.008, -0.25, 0.25)
	if not inside and not snag:
		lean += sin(_clock * 7.0) * 0.08  # 不在风口里：打晃
	for side in [-1.0, 1.0]:
		var tip := at + Vector2(side * 16.0, 40.0).rotated(lean)
		var pts := PackedVector2Array([tip])
		for i in range(1, 9):
			var idx := mini(i * 3, _trail.size() - 1)
			var base: Vector2 = at.lerp(_trail[idx], 0.45) if _trail.size() > 0 else at
			pts.append(base + Vector2(side * 16.0 + sin(_clock * 6.0 + i * 0.9 + side) * 7.0, 40.0 + i * 13.0))
		draw_polyline(pts, Color(P.QING if side < 0.0 else P.MEI, 0.8), 3.0)
	draw_set_transform(at, lean, Vector2.ONE)
	for side in [-1.0, 1.0]:
		var col := P.QING if side < 0.0 else P.MEI
		var wing := PackedVector2Array([
			Vector2(0, -16), Vector2(side * 66, -34), Vector2(side * 52, -4), Vector2(side * 18, 8),
			Vector2(side * 24, 44), Vector2(side * 6, 30), Vector2(0, 34),
		])
		var shifted := PackedVector2Array()
		for p in wing:
			shifted.append(p + Vector2(3, 2))
		draw_colored_polygon(shifted, Color(col, 0.88))
		var outline := wing.duplicate()
		outline.append(wing[0])
		draw_polyline(outline, P.INK, 3.0)
	draw_circle(Vector2(2, -24), 12.0, Color(P.OVERLAP, 0.9))
	draw_arc(Vector2(0, -25), 12.0, 0, TAU, 20, P.INK, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_hud(f: Font, inside: bool, snag: bool) -> void:
	var w := size.x
	var top := maxf(size.y * 0.045, 70.0)
	# 线放出去多少：一根横着的线，放到头就是满分
	var a := Vector2(90.0, top + 64.0)
	var b := Vector2(w - 90.0, top + 64.0)
	draw_string(f, Vector2(90.0, top + 30.0), "放风筝", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, P.INK)
	var left := maxf(0.0, float(_d.get("dur", 30.0)) - maxf(_t, 0.0))
	var clock_text := "%d 秒" % int(ceil(left))
	var cw := f.get_string_size(clock_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	draw_string(f, Vector2(w - 90.0 - cw, top + 30.0), clock_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, P.INK_SOFT)
	draw_line(a, b, Color(P.INK_SOFT, 0.5), 3.0)
	var prog := clampf(float(_cur.get("prog", 0.0)), 0.0, 1.0)
	draw_line(a, a.lerp(b, prog), P.OVERLAP, 7.0)
	draw_circle(a.lerp(b, prog), 11.0, P.OVERLAP)
	draw_string(f, Vector2(90.0, top + 108.0), "线放出去 %d%%" % int(round(prog * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, P.INK_SOFT)
	# 同一行靠右：我管哪一头；出状况时换成提示
	var tip := "上下滑：你管高低" if i_hold() else "左右滑：你管左右"
	var tip_col := P.role_color(my_role)
	if snag:
		tip = "挂桥上了，等它挣下来"
		tip_col = P.INK
	elif not inside and _t > 2.0:
		tip += "　把风筝送进风口"
	var tw := f.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	draw_string(f, Vector2(w - 90.0 - tw, top + 108.0), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, tip_col)


func _draw_intro(f: Font) -> void:
	# 开场三秒：看清自己管哪一头
	draw_rect(Rect2(Vector2.ZERO, size), Color(P.PAPER, 0.82))
	var cy := size.y * 0.4
	var mine := "你攥线：上下滑，管高低" if i_hold() else "你牵着线跑：左右滑，管左右"
	var theirs := "%s%s" % [str(names.get(_other(), "TA")), "牵着线跑，管左右" if i_hold() else "攥线，管高低"]
	_centered(f, mine, cy, 52, P.role_color(my_role))
	_centered(f, theirs, cy + 84.0, 38, P.role_color(_other()))
	_centered(f, "两条线交叉的地方，就是风筝要去的地方", cy + 170.0, 30, P.INK_SOFT)
	_centered(f, str(int(ceil(-_t))), cy + 330.0, 120, P.OVERLAP)


func _centered(f: Font, text: String, y: float, font_size: int, color: Color) -> void:
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(f, Vector2((size.x - tw) / 2.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
