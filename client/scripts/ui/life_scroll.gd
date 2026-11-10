extends Control
## 人生长卷：一张横着展开的纸，两条线从三岁画到最后。
##
## 它只画一件事：两个人各有各的关口，哪几关走到了一起，哪几关分开了。
##   - 关口是站。两个人走了同一条路，两个圆叠在一起，两条线并成一条叠印的深色；各走各的，两条线分开走到下一站。
##   - 线之间的细针脚是搭伴的日子：离得再远，那天也是缝在一起的。
##   - 线中间的小点是共同回忆，名字写在下面；褪了色的只剩一个空圈。
##   - 一个人先走了，线停在那一年；剩下的那条线回到纸的正中间，一个人走完。
## 数据全部来自结局时服务器给的 life（log / memories / persons / ending）和内容表，不另存东西。
## 横屏优先：高度固定 HEIGHT，宽度按站数算（约五千像素），外面套一层横向滚动（见 view()）。

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")
const LifeTime := preload("res://scripts/ui/life_time.gd")

const HEIGHT := 880.0
const LEFT := 420.0        ## 卷首（标题）占的宽度，第一站之前
const STEP := 340.0        ## 相邻两站之间的距离
const TAIL := 900.0        ## 卷尾（结局、题词）占的宽度
const MID := 440.0         ## 两条线中间那条看不见的轴
const SEP_START := 30.0    ## 还没过第一关：两扇对着的门
const SEP_SAME := 7.0      ## 同路：两条线挨着，中间叠印
const SEP_APART := 78.0    ## 各走各的
const LINE := 9.0
const STAGE_NAME := {"childhood": "童年", "teen": "少年", "young": "青年", "middle": "中年", "old": "老年"}
const ROLES := ["qing", "mei"]

var model: Dictionary = {}
var names: Dictionary = {}
var _anchors: Array = []   ## [{ turn, x }]，turn 递增：卷首、每一站、卷尾


## 把 life 整理成长卷要画的东西（纯数据，单测用）。
## 返回 { last, close, stations, stitches, memories, deaths, pair, lives, counts }
static func build(life: Dictionary, content: Dictionary) -> Dictionary:
	var events := {}
	for ev in content.get("events", []):
		events[str(ev.id)] = ev
	var gate_memory := {}  # 关口 id → 这一关留下的回忆
	var memories: Array = []
	for m in life.get("memories", []):
		var is_gate := str(m.get("eventId", "")).begins_with("m_") and events.has(str(m.eventId)) and str(events[str(m.eventId)].get("kind", "")) == "milestone"
		if is_gate:
			gate_memory[str(m.eventId)] = m
		else:
			memories.append({"turn": int(m.get("turn", 0)), "age": int(m.get("age", 0)), "title": str(m.get("title", "")), "vivid": int(m.get("vivid", 1)) > 0})
	var stations: Array = []
	var stitches: Array = []
	var deaths := {}
	var counts := {"days": 0, "together": 0, "same": 0, "apart": 0, "memories": life.get("memories", []).size()}
	var last := 0
	for e in life.get("log", []):
		var turn := int(e.get("turn", 0))
		match str(e.get("kind", "")):
			"day":
				counts.days += 1
				last = maxi(last, turn)
			"together":
				counts.together += 1
				# 一天里的先后：早上六点半到晚上十点，摊在这个日子的宽度里
				stitches.append(turn + clampf((float(e.get("minute", 390)) - 390.0) / 930.0, 0.0, 0.95))
			"death":
				for r in ROLES:
					var p: Dictionary = life.get("persons", {}).get(r, {})
					if not deaths.has(r) and not bool(p.get("alive", true)) and str(e.get("text", "")).find("%d 岁" % int(p.get("diedAtAge", -1))) >= 0 and str(e.get("text", "")).begins_with(str(p.get("name", "？？"))):
						deaths[r] = {"turn": turn, "age": int(p.diedAtAge)}
				last = maxi(last, turn)
			"milestone":
				var id := ""
				for r in ROLES:
					if e.get("events", {}).get(r) != null:
						id = str(e.events[r])
				var ev: Dictionary = events.get(id, {})
				var results: Dictionary = e.get("results", {}) if e.get("results") is Dictionary else {}
				var roads := {}
				for r in ROLES:
					if not results.has(r):
						continue
					var res: Dictionary = results[r]
					roads[r] = {
						"option": str(res.get("option", "")),
						"text": _short(_option_text(ev, str(res.get("option", "")))),
						"score": res.get("score") if bool(res.get("scored", true)) else null,
						"unit": str(res.get("unit", "分")),
						"grade": res.get("grade"),
						"shadow": (e.get("shadow", []) as Array).has(r),
					}
				var both := roads.size() == 2
				var same: bool = both and str(roads.qing.option) == str(roads.mei.option)
				if both:
					counts["same" if same else "apart"] += 1
				var mem: Dictionary = gate_memory.get(id, {})
				stations.append({
					"turn": turn, "age": int(e.get("age", ev.get("age", 0))), "title": str(ev.get("title", "")),
					"both": both, "same": same, "roads": roads,
					"memory": str(mem.get("title", "")) if same else "", "vivid": int(mem.get("vivid", 1)) > 0,
				})
	# 服务器的 death 记录不带是谁：对不上文字的，按 persons 里的岁数补
	for r in ROLES:
		var p: Dictionary = life.get("persons", {}).get(r, {})
		if not deaths.has(r) and not bool(p.get("alive", true)) and p.get("diedAtAge") != null:
			deaths[r] = {"turn": _turn_of_age(int(p.diedAtAge), last), "age": int(p.diedAtAge)}
	var pair := {}
	var lives := {}
	var ending: Dictionary = life.get("ending", {}) if life.get("ending") is Dictionary else {}
	var table: Dictionary = content.get("endings", {}) if content.get("endings") is Dictionary else {}
	for it in table.get("pair", []):
		if str(it.id) == str(ending.get("pair", "")):
			pair = {"title": str(it.title), "text": str(it.text)}
	for r in ROLES:
		for it in table.get("lives", []):
			if ending.get("lives") is Dictionary and str(it.id) == str(ending.lives.get(r, "")):
				var nm := str(life.get("persons", {}).get(r, {}).get("name", P.ROLE_NAME[r]))
				lives[r] = {"title": str(it.title), "text": str(it.text).replace("{name}", nm)}
	var close := float(life.get("bond", {}).get("close", 0.0)) if life.get("bond") is Dictionary else 0.0
	return {"last": last, "close": close, "stations": stations, "stitches": stitches, "memories": memories, "deaths": deaths, "pair": pair, "lives": lives, "counts": counts}


static func _option_text(ev: Dictionary, option: String) -> String:
	for o in ev.get("options", []):
		if str(o.id) == option:
			return str(o.text)
	return ""


## 路的名字只留头一句（「当学习委员，收作业本」→「当学习委员」），站和站之间放得下
static func _short(text: String) -> String:
	for cut in ["，", "。", "："]:
		var i := text.find(cut)
		if i > 0:
			text = text.substr(0, i)
	return text if text.length() <= 10 else text.substr(0, 9) + "…"


## 这个岁数落在第几个日子（走的那一年多半在两个日子中间，取最后一个不超过它的）
static func _turn_of_age(age: int, last: int) -> int:
	var t := 0
	for i in last + 2:
		if int(LifeTime.at(i).age) <= age:
			t = i
	return t


func setup(life: Dictionary, content: Dictionary, p_names: Dictionary) -> void:
	model = build(life, content)
	names = p_names
	_anchors = [{"turn": 0.0, "x": LEFT}]
	var x := LEFT
	for st in model.stations:
		x += STEP
		_anchors.append({"turn": float(st.turn), "x": x})
	# 卷尾：最后一个人走的那一年，或者最后一个日子
	var end_turn := float(model.last) + 1.0
	_anchors.append({"turn": maxf(end_turn, float(_anchors[-1].turn) + 1.0), "x": x + STEP})
	custom_minimum_size = Vector2(x + STEP + TAIL, HEIGHT)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


## 套一层横向滚动：手指拖着看；刚打开时自己慢慢展开一段，碰一下就停
static func view(life: Dictionary, content: Dictionary, p_names: Dictionary, height := HEIGHT) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.custom_minimum_size = Vector2(0, height)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll: Control = load("res://scripts/ui/life_scroll.gd").new()
	scroll.setup(life, content, p_names)
	sc.add_child(scroll)
	sc.set_meta("scroll", scroll)
	sc.ready.connect(func():
		var far := maxf(0.0, scroll.custom_minimum_size.x - sc.size.x)
		var tw := sc.create_tween()
		tw.tween_interval(0.8)
		tw.tween_property(sc, "scroll_horizontal", int(far), maxf(6.0, far / 260.0)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		sc.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventScreenTouch or ev is InputEventMouseButton or ev is InputEventScreenDrag:
				tw.kill()))
	return sc


## 把整张长卷存成一张图（不只是屏幕上露出来的那一段）。要在场景树里调用
func save_png(path: String) -> Error:
	var vp := SubViewport.new()
	vp.size = Vector2i(custom_minimum_size)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var copy: Control = load("res://scripts/ui/life_scroll.gd").new()
	copy.model = model
	copy.names = names
	copy._anchors = _anchors
	copy.custom_minimum_size = custom_minimum_size
	copy.size = custom_minimum_size
	vp.add_child(copy)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var err := vp.get_texture().get_image().save_png(path)
	vp.queue_free()
	return err


# ----------------------------------------------------------------------
# 坐标
# ----------------------------------------------------------------------

func x_of(turn: float) -> float:
	if _anchors.is_empty():
		return LEFT
	for i in range(1, _anchors.size()):
		var a: Dictionary = _anchors[i - 1]
		var b: Dictionary = _anchors[i]
		if turn <= float(b.turn) or i == _anchors.size() - 1:
			return lerpf(float(a.x), float(b.x), clampf((turn - float(a.turn)) / maxf(0.001, float(b.turn) - float(a.turn)), 0.0, 1.0))
	return float(_anchors[-1].x)


## 这一站以后两条线隔多远
func _sep_after(i: int) -> float:
	if i < 0:
		return SEP_START
	var st: Dictionary = model.stations[i]
	if not bool(st.both):
		return maxf(_sep_after(i - 1), SEP_APART * 0.7)
	return SEP_SAME if bool(st.same) else SEP_APART


## 在 x 这个位置两条线隔多远：进站前的半段路上慢慢靠拢或分开，到站时已经是这一站的结果
func sep_at(x: float) -> float:
	var n: int = model.stations.size()
	for i in n:
		var sx: float = float(_anchors[i + 1].x)
		if x <= sx:
			var from := _sep_after(i - 1)
			var t := smoothstep(sx - STEP * 0.5, sx, x)
			return lerpf(from, _sep_after(i), t)
	return _sep_after(n - 1)


func _lane(role: String, x: float) -> float:
	var d := sep_at(x)
	# 对门走了以后，剩下的人慢慢回到纸的正中间
	var other := "mei" if role == "qing" else "qing"
	if model.deaths.has(other):
		var gone := x_of(float(model.deaths[other].turn) + 0.5)
		d *= 1.0 - smoothstep(gone, gone + STEP * 0.6, x)
	return MID + (-d if role == "qing" else d)


func _end_x(role: String) -> float:
	if model.deaths.has(role):
		return x_of(float(model.deaths[role].turn) + 0.5)
	return float(_anchors[-1].x)


# ----------------------------------------------------------------------
# 画
# ----------------------------------------------------------------------

func _draw() -> void:
	if model.is_empty():
		return
	var f := P.font()
	var w := size.x
	draw_rect(Rect2(0, 0, w, HEIGHT), P.PAPER)
	_draw_stages(f)
	# 纸的上下两道边：墨线，下面错开一点的色线
	for y in [14.0, HEIGHT - 14.0]:
		draw_line(Vector2(0, y + 4), Vector2(w, y + 4), Color(P.MEI, 0.55), 3.0)
		draw_line(Vector2(0, y), Vector2(w, y), P.INK, 3.0)
	_draw_head(f)
	_draw_stitches()
	_draw_lines()
	_draw_memories(f)
	for i in model.stations.size():
		_draw_station(f, i)
	_draw_ends(f)
	_draw_tail(f)


func _text(f: Font, pos: Vector2, text: String, font_size: int, color: Color, align := 0) -> float:
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := pos.x - (tw * 0.5 if align == 0 else (tw if align > 0 else 0.0))
	draw_string(f, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	return tw


## 阶段的底：隔一段垫一层深一点的纸，角上写着这是哪一段
func _draw_stages(f: Font) -> void:
	var start := 0
	for i in LifeTime.STAGES.size():
		var st: Dictionary = LifeTime.STAGES[i]
		var turns := int(round(float(st.years) * float(st.tpy)))
		var x0 := x_of(float(start))
		var x1 := x_of(float(start + turns)) if i < LifeTime.STAGES.size() - 1 else float(_anchors[-1].x)
		if start > int(model.last) + 1:
			break
		if i % 2 == 1:
			draw_rect(Rect2(x0, 18, x1 - x0, HEIGHT - 36), Color(P.PAPER_DARK, 0.75))
		draw_string(f, Vector2(x0 + 22, HEIGHT - 40), str(STAGE_NAME.get(str(st.stage), "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(P.INK_SOFT, 0.8))
		start += turns


## 卷首：两个圆、两个人的名字、从哪开始
func _draw_head(f: Font) -> void:
	Kit.draw_pair(self, Vector2(150, 250), 62.0, 46.0, 1.0, 3.0)
	draw_string(f, Vector2(70, 420), "人生长卷", HORIZONTAL_ALIGNMENT_LEFT, -1, 60, P.INK)
	var x := 72.0
	x += _text(f, Vector2(x, 480), str(names.get("qing", "青")), 36, P.QING, -1)
	x += _text(f, Vector2(x + 14, 480), "和", 30, P.INK_SOFT, -1) + 28
	_text(f, Vector2(x, 480), str(names.get("mei", "梅")), 36, P.MEI, -1)
	draw_string(f, Vector2(72, 530), "河畔里 · 住对门", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, P.INK_SOFT)
	# 起点：三岁，两扇对着的门
	_text(f, Vector2(LEFT, 92), "3 岁", 44, P.INK)
	_text(f, Vector2(LEFT, 130), "搬进对门", 26, P.INK_SOFT)


func _draw_lines() -> void:
	var pts := {"qing": PackedVector2Array(), "mei": PackedVector2Array()}
	var overlap: Array = [PackedVector2Array()]
	var far := float(_anchors[-1].x)
	var x := LEFT
	while x <= far + 0.5:
		var both := true
		for r in ROLES:
			if x <= _end_x(r) + 0.5:
				pts[r].append(Vector2(x, _lane(r, x)))
			else:
				both = false
		# 两条线挨到一起的那几段，中间叠印一道深色
		if both and sep_at(x) <= SEP_SAME + 2.0:
			overlap[-1].append(Vector2(x, MID))
		elif overlap[-1].size() > 0:
			overlap.append(PackedVector2Array())
		x += 6.0
	# 梅色的版故意印歪一点点
	if pts.mei.size() > 1:
		draw_polyline(pts.mei, P.MEI, LINE, true)
	if pts.qing.size() > 1:
		draw_polyline(pts.qing, P.QING, LINE, true)
	for seg in overlap:
		if seg.size() > 1:
			draw_polyline(seg, P.OVERLAP, LINE - 1.0, true)
	for r in ROLES:
		draw_circle(Vector2(LEFT, _lane(r, LEFT)), 12.0, P.role_color(r), true, -1.0, true)


## 搭伴的日子：把两条线缝在一起的针脚
func _draw_stitches() -> void:
	for t in model.stitches:
		var x := x_of(float(t))
		if x > minf(_end_x("qing"), _end_x("mei")):
			continue
		var a := _lane("qing", x) + LINE * 0.5
		var b := _lane("mei", x) - LINE * 0.5
		if b - a < 4.0:
			continue
		draw_line(Vector2(x, a), Vector2(x, b), Color(P.INK, 0.32), 2.0, true)


func _draw_memories(f: Font) -> void:
	var rows := [-1e9, -1e9, -1e9]
	for m in model.memories:
		var x := x_of(float(m.turn) + 0.5)
		var c := Vector2(x, MID)
		var vivid := bool(m.vivid)
		draw_circle(c, 9.0, P.PAPER, true, -1.0, true)
		if vivid:
			draw_circle(c, 7.0, P.OVERLAP, true, -1.0, true)
		else:
			draw_arc(c, 6.0, 0, TAU, 20, P.INK_SOFT, 2.0, true)
		var title := str(m.title)
		var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		for row in rows.size():
			if x - tw * 0.5 > float(rows[row]) + 18.0:
				var y := 706.0 + row * 40.0
				rows[row] = x + tw * 0.5
				draw_line(Vector2(x, MID + SEP_APART + 96.0), Vector2(x, y - 26.0), Color(P.INK_SOFT, 0.45), 1.5, true)
				_text(f, Vector2(x, y), title, 24, P.OVERLAP if vivid else P.INK_SOFT)
				break


func _score_text(road: Dictionary) -> String:
	var parts: Array = []
	if road.get("score") != null:
		parts.append("%d %s" % [int(road.score), str(road.unit)])
	if road.get("grade") != null:
		parts.append(str(road.grade))
	if bool(road.get("shadow", false)):
		parts.append("影子替选的")
	return " · ".join(parts)


func _draw_station(f: Font, i: int) -> void:
	var st: Dictionary = model.stations[i]
	var x := float(_anchors[i + 1].x)
	_text(f, Vector2(x, 92), "%d 岁" % int(st.age), 44, P.INK)
	_text(f, Vector2(x, 130), str(st.title), 26, P.INK_SOFT)
	draw_dashed_line(Vector2(x, 150), Vector2(x, 660), Color(P.INK, 0.22), 2.0, 8.0)
	var yq := _lane("qing", x)
	var ym := _lane("mei", x)
	var roads: Dictionary = st.roads
	if bool(st.same):
		# 同路：两个圆叠在一起，路名只写一遍，下面是这一关留下的回忆
		Kit.draw_pair(self, Vector2(x, MID), 20.0, 12.0, 1.0, 2.0)
		_text(f, Vector2(x, MID - 96), str(roads.qing.text), 30, P.OVERLAP)
		var sq := _score_text(roads.qing)
		var sm := _score_text(roads.mei)
		if sq != "" or sm != "":
			var half := 14.0
			if sq != "":
				_text(f, Vector2(x - half, MID - 138), sq, 22, P.QING, 1)
			if sm != "":
				_text(f, Vector2(x + half, MID - 138), sm, 22, P.MEI, -1)
		if str(st.memory) != "":
			_text(f, Vector2(x, MID + 114), "「%s」" % str(st.memory), 26, P.OVERLAP if bool(st.vivid) else P.INK_SOFT)
		return
	for r in ROLES:
		if not roads.has(r):
			continue
		var road: Dictionary = roads[r]
		var y := yq if r == "qing" else ym
		var up: bool = r == "qing"
		var c := Vector2(x, y)
		draw_circle(c, 17.0, P.PAPER, true, -1.0, true)
		if bool(road.shadow):
			draw_arc(c, 13.0, 0, TAU, 32, P.role_color(r), 4.0, true)
		else:
			draw_circle(c, 14.0, P.role_color(r), true, -1.0, true)
		_text(f, Vector2(x, y - 34 if up else y + 52), str(road.text), 28, P.role_color(r))
		var score := _score_text(road)
		if score != "":
			_text(f, Vector2(x, y - 70 if up else y + 84), score, 22, P.INK_SOFT)


## 线的尽头：一个空圈，写着走的那一年
func _draw_ends(f: Font) -> void:
	for r in ROLES:
		if not model.deaths.has(r):
			continue
		var x := _end_x(r)
		var c := Vector2(x, _lane(r, x))
		draw_circle(c, 13.0, P.PAPER, true, -1.0, true)
		draw_arc(c, 10.0, 0, TAU, 32, P.role_color(r), 3.5, true)
		# 岁数写在圈的右边：上下是这一站的路名
		_text(f, Vector2(x + 20, c.y + 9), "%d 岁" % int(model.deaths[r].age), 24, P.role_color(r), -1)


## 卷尾：两个人的结局、各自的一生、题词
func _draw_tail(f: Font) -> void:
	var x := float(_anchors[-1].x) + 110.0
	var width := TAIL - 190.0
	var y := 150.0
	if not model.pair.is_empty():
		draw_string(f, Vector2(x - 14, y), "「%s」" % str(model.pair.title), HORIZONTAL_ALIGNMENT_LEFT, -1, 64, P.OVERLAP)
		y += 52.0
		y = _para(f, Vector2(x, y), str(model.pair.text), width, 30, P.INK) + 26.0
	for r in ROLES:
		if not model.lives.has(r):
			continue
		var life_end: Dictionary = model.lives[r]
		draw_rect(Rect2(x, y - 2, 8, 44), P.role_color(r))
		draw_string(f, Vector2(x + 24, y + 32), "%s ·「%s」" % [str(names.get(r, P.ROLE_NAME[r])), str(life_end.title)], HORIZONTAL_ALIGNMENT_LEFT, -1, 32, P.role_color(r))
		y = _para(f, Vector2(x + 24, y + 48), str(life_end.text), width - 24, 24, P.INK_SOFT) + 22.0
	var c: Dictionary = model.counts
	var line := "一起过了 %d 个被记住的日子，搭伴 %d 回，同路 %d 关，各走各的 %d 关，留下 %d 段共同回忆。" % [int(c.days), int(c.together), int(c.same), int(c.apart), int(c.memories)]
	draw_line(Vector2(x, HEIGHT - 170), Vector2(x + width, HEIGHT - 170), Color(P.INK, 0.3), 2.0)
	_para(f, Vector2(x, HEIGHT - 150), line, width, 24, P.INK_SOFT)
	# 右上角的两个圆：最后有多亲近，就叠多少
	Kit.draw_pair(self, Vector2(x + width - 44, 100), 30.0, lerpf(56.0, 0.0, clampf(float(model.close) / 100.0, 0.0, 1.0)), 1.0, 2.0)


## 画一段会折行的字，返回这段字的底边
func _para(f: Font, pos: Vector2, text: String, width: float, font_size: int, color: Color) -> float:
	var h := f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y
	draw_multiline_string(f, pos + Vector2(0, f.get_ascent(font_size)), text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1, color)
	return pos.y + h
