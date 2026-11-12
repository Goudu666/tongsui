extends Node2D
## 河畔里的街景：街坊、街上过的车、对岸的天际线——都随年代更替。
##
## 数据：res://data/street.json（content/street.yaml 编译来的）：谁、站哪、哪个年代在、几点在、说什么
## 美术：res://art/street/atlas.png + sprites.json（tools/art/pixel/pxstreet.py 生成，像素版：scale 1，foot 落在 3×3 的点格上）
## 只是街景，不参与结算：能做的事还是 map.yaml 里的互动点，这里只负责"街上有人"。
##
## 层级：街坊和车挂在 world_view 下面，和主角一起按 y 排序（z 0）；对岸的东西贴地（z -60）；
##       烟和水花（z 45）；说话的气泡在最上面（z 80）。
## 调美术：godot --path client -- --era=young --minute=1140   强制年代 / 钟点（只影响街景）

const P := preload("res://scripts/ui/palette.gd")
const DATA := "res://data/street.json"
const ATLAS := "res://art/street/atlas.png"
const META := "res://art/street/sprites.json"
const STAGES := ["childhood", "teen", "young", "middle", "old"]
const TALK_RADIUS := 150.0
const LINE_SECONDS := 4.6
const STREET_EAST := 1905.0   ## 街的东头：再往东是海河步道，车在这儿淡出

var view: Node2D              ## world_view：街坊挂在它下面，和主角一起排序
var stage := "childhood"
var minute := 390.0
var eras: Dictionary = {}
var ready_ok := false

var _atlas: Texture2D
var _sprites: Dictionary = {}
var _art_scale := 1.0
var _things: Array = []       ## 街坊 + 道具：{def, node, on, t, talk_i}
var _traffic: Array = []      ## {def, wait}
var _movers: Array = []       ## 正在街上的车：{def, node, state, ...}
var _busy: Array = []         ## 两位主角此刻在做的行动
var _fx: Node2D
var _talk: Node2D
var _t := 0.0
var _talker := -1             ## 正在说话的那位在 _things 里的下标
var _talk_t := 0.0
var _talk_text := ""
var _splashes: Array = []     ## 水花：{at, t}
var _rng := RandomNumberGenerator.new()
var _force_stage := ""
var _force_minute := -1.0


func setup(p_view: Node2D) -> void:
	view = p_view
	_rng.seed = 20261110
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--era=") and a.substr(6) in STAGES:
			_force_stage = a.substr(6)
		elif a.begins_with("--minute="):
			_force_minute = float(a.substr(9))
	if not _load():
		return
	ready_ok = true
	_fx = _Layer.new(self, "fx")
	_fx.z_index = 45
	add_child(_fx)
	_talk = _Layer.new(self, "talk")
	_talk.z_index = 80
	add_child(_talk)
	if _force_stage != "":
		stage = _force_stage
	if _force_minute >= 0.0:
		minute = _force_minute
	_refresh(true)


func _load() -> bool:
	if not (FileAccess.file_exists(DATA) and FileAccess.file_exists(META) and ResourceLoader.exists(ATLAS)):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(META))
	if not (data is Dictionary and meta is Dictionary):
		return false
	_atlas = load(ATLAS)
	_sprites = meta.get("sprites", {})
	_art_scale = float(meta.get("scale", 1.0))
	eras = data.get("eras", {})
	for kind in ["props", "npcs"]:
		for d in data.get(kind, []):
			if not _sprites.has(d.get("sprite", "")):
				continue
			var far: bool = str(d.get("layer", "")) == "far"
			var node := _make_sprite(str(d.sprite), Vector2(d.at[0], d.at[1]))
			node.visible = false
			node.modulate.a = 0.0
			if far:
				node.z_index = -60
				add_child(node)
			else:
				view.add_child(node)
			_things.append({"def": d, "node": node, "on": false, "t": float(d.get("phase", _rng.randf())) * 2.0, "talk_i": 0, "dive": 0.0})
	for d in data.get("traffic", []):
		if _sprites.has(d.get("sprite", "")):
			_traffic.append({"def": d, "wait": _rng.randf_range(1.0, float(d.gap[1]) * 0.6)})
	return true


func _make_sprite(sprite_name: String, at: Vector2) -> Sprite2D:
	var m: Dictionary = _sprites[sprite_name]
	var s := Sprite2D.new()
	s.texture = _atlas
	s.centered = false
	s.region_enabled = true
	s.scale = Vector2.ONE / _art_scale
	s.offset = -Vector2(m.foot[0], m.foot[1]) * _art_scale
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 像素画：脚底落在点格上（格子原点是世界 (0, -200)，一格 3 像素），和底图的点对得上
	s.position = Vector2(roundf(at.x / 3.0) * 3.0, roundf((at.y + 200.0) / 3.0) * 3.0 - 200.0)
	s.set_meta("m", m)
	_set_frame(s, 0)
	return s


func _set_frame(s: Sprite2D, frame: int) -> void:
	var m: Dictionary = s.get_meta("m")
	var f := frame % int(m.frames)
	var w := float(m.w) * _art_scale
	s.region_rect = Rect2(float(m.x) + f * w, float(m.y), w, float(m.h) * _art_scale)


# ----------------------------------------------------------------------
# 年代、钟点、主角在忙什么 → 谁该在场
# ----------------------------------------------------------------------

func set_stage(p_stage: String) -> void:
	var s := p_stage if _force_stage == "" else _force_stage
	if s == stage or not (s in STAGES):
		return
	stage = s
	_refresh(false)


func set_minute(m: float) -> void:
	var before := minute
	minute = m if _force_minute < 0.0 else _force_minute
	if int(before / 15.0) != int(minute / 15.0):
		_refresh(false)


## 夜版套印盖不到最上面的气泡：夜里跟互动点的小纸片一样暗一点（0 白天 ~ 1 深夜）
func set_night(night: float) -> void:
	if _talk != null:
		_talk.modulate = Color.WHITE.lerp(Color(0.72, 0.76, 0.9), night)


## 两位主角正在做的行动（world_view 每次收到世界广播时喂进来）
func set_busy(acts: Array) -> void:
	if acts != _busy:
		_busy = acts
		_refresh(false)


func era_name() -> String:
	return str(eras.get(stage, {}).get("name", ""))


func _wanted(d: Dictionary) -> bool:
	var e: Array = d.get("eras", [])
	if not e.is_empty() and not (stage in e):
		return false
	var h: Array = d.get("hours", [])
	if h.size() == 2 and (minute < float(h[0]) or minute > float(h[1])):
		return false
	if d.has("hide_when") and str(d.hide_when) in _busy:
		return false
	return true


func _refresh(instant: bool) -> void:
	if not ready_ok:
		return
	for th in _things:
		var want := _wanted(th.def)
		if want == th.on:
			continue
		th.on = want
		var node: Sprite2D = th.node
		if instant:
			node.visible = want
			node.modulate.a = 1.0 if want else 0.0
			continue
		node.visible = true
		var tw := node.create_tween()
		tw.tween_property(node, "modulate:a", 1.0 if want else 0.0, 0.9)
		if not want:
			tw.tween_callback(node.hide)


# ----------------------------------------------------------------------
# 每帧：换帧、车流、搭话
# ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_ok:
		return
	_t += delta
	for th in _things:
		if not th.on:
			continue
		th.t += delta
		var node: Sprite2D = th.node
		var m: Dictionary = node.get_meta("m")
		if int(m.frames) > 1:
			# 大多数时候是第一帧，隔一会儿换个动作；跳舞的两帧来回
			var beat := 0.55 if str(th.def.sprite) == "dama" else 1.3
			var k := int(th.t / beat)
			var alt: bool = (k % 2 == 1) if str(th.def.sprite) == "dama" else (k % 3 == 2)
			_set_frame(node, 1 if alt else 0)
		if str(th.def.get("fx", "")) == "dive":
			_dive(th, delta)
	_tick_traffic(delta)
	_tick_talk(delta)
	for sp in _splashes:
		sp.t += delta
	_splashes = _splashes.filter(func(sp): return sp.t < 2.4)
	_fx.queue_redraw()
	_talk.queue_redraw()


## 游泳的大爷：在栏杆边站好一会儿，举手，扎下去，水花，过一阵又站回来
func _dive(th: Dictionary, delta: float) -> void:
	var node: Sprite2D = th.node
	var home := Vector2(th.def.at[0], th.def.at[1])
	th.dive += delta
	var cycle := 31.0
	var k: float = fmod(th.dive, cycle) - 18.0
	if k < 8.0:           # 站着（最后一秒举手）
		node.position = home
		node.rotation = 0.0
		node.modulate.a = minf(node.modulate.a + delta * 2.0, 1.0)
		_set_frame(node, 1 if k > 6.6 else 0)
	elif k < 9.0:         # 腾空：先往上蹿，再头朝下
		var u := k - 8.0
		_set_frame(node, 1)
		node.position = home + Vector2(26.0 * u, -70.0 * u + 150.0 * u * u)
		node.rotation = PI * smoothstep(0.1, 0.9, u)
		if u > 0.86 and (_splashes.is_empty() or _splashes.back().t > 1.0):
			_splashes.append({"at": home + Vector2(30, 74), "t": 0.0})
			node.modulate.a = 0.0
	else:                 # 在水里
		node.modulate.a = 0.0
		node.position = home
		node.rotation = 0.0


func _in_rush(d: Dictionary) -> bool:
	for r in d.get("rush", []):
		if minute >= float(r[0]) and minute <= float(r[1]):
			return true
	return false


func _tick_traffic(delta: float) -> void:
	var day := minute >= 400.0 and minute <= 1290.0
	for tr in _traffic:
		var d: Dictionary = tr.def
		if not (stage in d.get("eras", STAGES)) or not day:
			continue
		tr.wait -= delta
		if tr.wait > 0.0:
			continue
		var gap: Array = d.rush_gap if (d.has("rush_gap") and _in_rush(d)) else d.gap
		tr.wait = _rng.randf_range(float(gap[0]), float(gap[1]))
		_spawn(d)
	for mv in _movers:
		_move(mv, delta)
	_movers = _movers.filter(func(mv): return not mv.done)


func _spawn(d: Dictionary) -> void:
	var taxi: bool = str(d.kind) == "taxi"
	var dir := 1.0 if taxi else float(d.get("dir", 1))
	var lane := float(d.lane) + _rng.randf_range(-4.0, 4.0)
	var x0 := -120.0 if dir > 0.0 else STREET_EAST + 50.0
	var node := _make_sprite(str(d.sprite), Vector2(x0, lane))
	node.flip_h = dir < 0.0
	if node.flip_h:   # 翻转是绕贴图左边翻的，把锚点挪回脚底
		var m: Dictionary = node.get_meta("m")
		node.offset.x = -(float(m.w) - float(m.foot[0])) * _art_scale
	view.add_child(node)
	_movers.append({
		"def": d, "node": node, "dir": dir, "state": "go", "dist": 0.0, "done": false, "said": false, "say_t": 99.0,
		"stop_x": _rng.randf_range(520.0, 1480.0), "hold": _rng.randf_range(3.0, 5.5), "taxi": taxi,
		"speed": float(d.speed) * _rng.randf_range(0.9, 1.12),
	})


func _move(mv: Dictionary, delta: float) -> void:
	var node: Sprite2D = mv.node
	var m: Dictionary = node.get_meta("m")
	mv.say_t += delta
	if mv.state == "hold":
		mv.hold -= delta
		if mv.hold <= 0.0:    # 掉头
			mv.state = "back"
			mv.dir = -1.0
			node.flip_h = true
			node.offset.x = -(float(m.w) - float(m.foot[0])) * _art_scale
			node.position.y -= 28.0
		return
	var step: float = mv.speed * delta
	node.position.x += mv.dir * step
	mv.dist += step
	if int(m.frames) > 1:
		_set_frame(node, int(mv.dist / 20.0))
	# 东头淡入淡出：往东是河边步道
	node.modulate.a = clampf((STREET_EAST + 40.0 - node.position.x) / 90.0, 0.0, 1.0)
	if mv.taxi and mv.state == "go" and node.position.x >= mv.stop_x:
		mv.state = "hold"
		mv.say_t = 0.0
	var me: Node2D = view.call("me") if view.has_method("me") else null
	if not mv.taxi and not mv.said and mv.def.has("say") and me != null and absf(node.position.x - me.position.x) < 220.0 and absf(node.position.y - me.position.y) < 260.0:
		mv.said = true
		mv.say_t = 0.0
	if node.position.x < -160.0 or node.position.x > STREET_EAST + 60.0:
		mv.done = true
		node.queue_free()


# ----------------------------------------------------------------------
# 搭话：走到跟前，TA 说一句；站着不走，过一会儿换一句
# ----------------------------------------------------------------------

func _lines(d: Dictionary) -> Array:
	var all: Dictionary = d.get("lines", {})
	var own: Array = all.get(stage, [])
	return own if not own.is_empty() else all.get("default", [])


func _tick_talk(delta: float) -> void:
	var me: Node2D = view.call("me") if view != null and view.has_method("me") else null
	if me == null:
		_talker = -1
		return
	var best := -1
	var best_d := TALK_RADIUS
	for i in _things.size():
		var th: Dictionary = _things[i]
		if not th.on or _lines(th.def).is_empty() or (th.node as Sprite2D).modulate.a < 0.5:
			continue
		var d := me.position.distance_to(Vector2(th.def.at[0], th.def.at[1]))
		if d < best_d:
			best_d = d
			best = i
	if best != _talker:
		_talker = best
		_talk_t = 0.0
		if best >= 0:
			_next_line(_things[best])
		return
	if best < 0:
		return
	_talk_t += delta
	if _talk_t > LINE_SECONDS:
		_talk_t = 0.0
		_next_line(_things[best])


func _next_line(th: Dictionary) -> void:
	var ls := _lines(th.def)
	_talk_text = str(ls[int(th.talk_i) % ls.size()])
	th.talk_i = int(th.talk_i) + 1


# ----------------------------------------------------------------------
# 画：烟、水花、气泡
# ----------------------------------------------------------------------

func draw_layer(c: CanvasItem, which: String) -> void:
	match which:
		"fx":
			_draw_fx(c)
		"talk":
			_draw_talk(c)


func _draw_fx(c: CanvasItem) -> void:
	# 老厂的烟：慢、大、往东北飘
	for th in _things:
		if not th.def.has("smoke"):
			continue
		var a: float = (th.node as Sprite2D).modulate.a
		if a <= 0.01:
			continue
		for p in th.def.smoke:
			for k in 4:
				var ph := fmod(_t * 0.16 + k / 4.0, 1.0)
				var at := Vector2(p[0] + ph * 46.0 + sin(_t * 0.7 + k) * 4.0, p[1] - ph * 54.0)
				c.draw_circle(at, 5.0 + ph * 15.0, Color(P.INK, 0.2 * (1.0 - ph) * a))
	# 水花
	for sp in _splashes:
		var u: float = sp.t / 2.4
		for k in 3:
			var r := 6.0 + (u + k * 0.14) * 44.0
			c.draw_arc(sp.at, r, PI * 1.05, PI * 1.95, 14, Color(P.QING, 0.8 * (1.0 - u)), 2.0)
			c.draw_arc(sp.at + Vector2(0, 5), r * 0.8, PI * 0.1, PI * 0.9, 12, Color(P.QING, 0.5 * (1.0 - u)), 1.6)
		if sp.t < 0.5:
			for k in 5:
				var d := Vector2(cos(PI * (1.15 + k * 0.175)), sin(PI * (1.15 + k * 0.175)))
				var h: float = sp.t / 0.5
				c.draw_line(sp.at + d * (6.0 + h * 16.0), sp.at + d * (14.0 + h * 26.0), Color(P.INK, 0.8 * (1.0 - h)), 1.8)
	# 车喇叭、车铃
	var f := P.font()
	for mv in _movers:
		if mv.say_t < 1.4 and mv.def.has("say"):
			var node: Sprite2D = mv.node
			var m: Dictionary = node.get_meta("m")
			var at := node.position + Vector2(0, -float(m.foot[1]) - 6.0 - mv.say_t * 14.0)
			var txt := str(mv.def.say)
			var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			c.draw_string(f, at - Vector2(w / 2.0, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(P.MEI, 1.0 - mv.say_t / 1.4))


func _wrap(text: String, per_line: int) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for ch in text:
		if cur.length() >= per_line and not (ch in "，。！？：；、”…—）"):
			out.append(cur)
			cur = ""
		cur += ch
	if cur != "":
		out.append(cur)
	return out


func _draw_talk(c: CanvasItem) -> void:
	if _talker < 0 or _talk_text == "":
		return
	var th: Dictionary = _things[_talker]
	var node: Sprite2D = th.node
	var m: Dictionary = node.get_meta("m")
	var f := P.font()
	var size := 22
	var lines := _wrap(_talk_text, 13)
	var name := str(th.def.get("name", ""))
	var w := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	for l in lines:
		w = maxf(w, f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	var h := 26.0 + lines.size() * 28.0
	var pop := clampf(_talk_t / 0.18, 0.0, 1.0)
	var tip := Vector2(th.def.at[0], th.def.at[1]) + Vector2(0, -float(m.foot[1]) + 6.0)
	var box := Rect2(tip + Vector2(-w / 2.0 - 14.0, -h - 16.0 + (1.0 - pop) * 8.0), Vector2(w + 28.0, h + 6.0))
	# 别顶出地图上沿
	if box.position.y < 6.0:
		box.position.y = 6.0
	var a := pop
	c.draw_rect(Rect2(box.position + Vector2(4, 4), box.size), Color(P.INK, 0.16 * a))
	c.draw_rect(box, Color(P.PAPER, 0.96 * a))
	c.draw_rect(box, Color(P.INK, a), false, 2.0)
	var tail := PackedVector2Array([Vector2(tip.x - 8, box.end.y - 1), Vector2(tip.x + 8, box.end.y - 1), Vector2(tip.x, box.end.y + 10)])
	c.draw_colored_polygon(tail, Color(P.PAPER, a))
	c.draw_polyline(PackedVector2Array([tail[0], tail[2], tail[1]]), Color(P.INK, a), 2.0)
	c.draw_string(f, box.position + Vector2(14, 22), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(P.MEI, a))
	for i in lines.size():
		c.draw_string(f, box.position + Vector2(14, 48 + i * 28.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(P.INK, a))


class _Layer extends Node2D:
	var life: Node
	var which := ""

	func _init(p_life: Node, p_which: String) -> void:
		life = p_life
		which = p_which

	func _draw() -> void:
		life.draw_layer(self, which)
