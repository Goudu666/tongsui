extends Node2D
## 河畔里：铺上孔版套色的地图（map_art.gd），放两个孩子，点哪走哪（nav.gd 寻路绕开墙和家具）。
## 地图贴图不在时，退回 M0 的墨线占位画法（_draw_fallback_map）。

signal move_report(pos: Vector2)

const P := preload("res://scripts/ui/palette.gd")
const Actor := preload("res://scripts/world/actor.gd")
const MapArt := preload("res://scripts/world/map_art.gd")
const Nav := preload("res://scripts/world/nav.gd")
const StreetLife := preload("res://scripts/world/street_life.gd")
const PrintLight := preload("res://scripts/world/print_light.gd")
const SPOT_RADIUS := 100.0  ## 比服务器的 110 小一点，避免边缘抖动
const MOVE_SEND_INTERVAL := 0.1
const SnapshotBuffer := preload("res://scripts/net/snapshot_buffer.gd")
const TICK_RATE := 10.0
const CORRECT_DEADZONE := 6.0   ## 服务器和本地差这么点就不管
const SNAP_DIST := 220.0        ## 差太多（换天回家、被叫去事件）直接到位
## 一天五段 [从, 到, 名字]：和服务器 world.ts 的 SLOTS 一样（server/test/arch.test.mjs 对着查）
const SLOTS := [[390, 480, "早上"], [480, 720, "上午"], [720, 930, "下午"], [930, 1110, "傍晚"], [1110, 1320, "晚上"]]
const ZOOM := 1.4               ## 镜头：1080 高的屏幕上看到 771 高的一段河畔里
const HUD_SHIFT := 56.0         ## 人在屏幕上比正中低这么多（界面坐标）

var map: Dictionary = {}
var actions: Dictionary = {}
var my_role := "qing"
var age := 3                 ## 现在几岁（main 喂）：一个点位上挂着几件事，按年纪取第一件合适的
var duties: Dictionary = {}  ## role -> 今天该去的地方 { label, spot, arrive, until, done, open }，没有是 null（服务器 WORLD 里的 tracks）
var unlocks: Dictionary = {} ## role -> 关口上挣来的去处（带 requires.flags 的行动 id，服务器 WORLD 里的 tracks[role].unlocks）
var minute := 0.0            ## 现在几点（一天里的第几分钟）：有的去处只在一段钟点里开
var slot := 0                ## 现在是一天里的第几段（SLOTS）。离线预览跟着 minute 算
var playing := false         ## 两个人都定了，这一段正在眼前过：这时候不能走、不能做事
var actors: Dictionary = {}  ## role -> Actor
var hints: Array = []
var controllable := true
var camera: Camera2D
var art: MapArt
var street: StreetLife  ## 街坊、车流、年代道具（纯街景，不参与结算）
var light: PrintLight  ## 昼夜和旧纸感（夜版套印）
var nav := Nav.new()
var _marks: Node2D  ## 互动点和命运提示：画在叠印层上面
var _tap_fx := Vector2.INF
var _tap_t := 0.0
var _send_timer := 0.0
var _last_sent := Vector2.INF
## 联机客户端（lifeline_client.gd）：提供服务器时钟和「第 seq 条 MOVE 我在哪」。离线逛逛时为 null
var net = null
var buffers: Dictionary = {}    ## role -> SnapshotBuffer（只用于对方）
var _correction := Vector2.ZERO ## 本地角色还没消化掉的服务器校正量
var _corrected_upto := 0        ## 这个序号及以前的 MOVE 是在校正之前发的，不再拿来校正（避免重复校正）
var _stage_set := false


func setup(content: Dictionary, role: String, names: Dictionary) -> void:
	map = content.map
	for a in map.actions:
		actions[a.id] = a
	my_role = role
	y_sort_enabled = true
	art = MapArt.new()
	art.plate_lighting = true
	add_child(art)
	light = PrintLight.new()
	add_child(light)
	light.setup(Vector2(map.size[0], map.size[1]), art.anchors)
	nav.load_mask()
	_marks = _Marks.new(self)
	_marks.z_index = 70
	add_child(_marks)
	for r in ["qing", "mei"]:
		var sp: Array = map.spawn[r]
		var actor := Actor.new()
		actor.setup(r, str(names.get(r, P.ROLE_NAME[r])), r == role, Vector2(sp[0], sp[1]))
		add_child(actor)
		actors[r] = actor
		buffers[r] = SnapshotBuffer.new()
		light.actors.append(actor)
	camera = Camera2D.new()
	# 横屏：一屏横着能看到大半条街。屏幕特别长（或者平板特别高）时一屏比地图还大，就再放大一点，别露出地图外面的白纸
	var view := get_viewport_rect().size
	camera.zoom = Vector2.ONE * maxf(ZOOM, maxf(view.x / float(map.size[0]), view.y / float(map.size[1])) + 0.01)
	# 顶上有一条 HUD：人往下站一点，头顶上的字不被纸带压住
	camera.offset = Vector2(0, -HUD_SHIFT / camera.zoom.y)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(map.size[0])
	camera.limit_bottom = int(map.size[1])
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	camera.make_current()
	street = StreetLife.new()
	add_child(street)
	street.setup(self)
	queue_redraw()


func me() -> Actor:
	return actors.get(my_role)


## 人生阶段变了（长大了），换外观
func set_stage(stage: String) -> void:
	for a in actors.values():
		a.set_stage(stage)
	if street != null:
		street.set_stage(stage)
	if light != null:
		light.set_stage(stage, not _stage_set)
	_stage_set = true


## 时钟：决定昼夜（联机时 apply_world 自动调用；离线预览由 main 喂）
func set_minute(m: float) -> void:
	minute = m
	slot = slot_at(m)
	if art != null:
		art.set_minute(m)
	if street != null:
		street.set_minute(m)
	if light != null:
		light.set_minute(m)
		# 互动点的小纸片在夜版上面，夜里跟着暗一点，不然太扎眼
		if _marks != null:
			_marks.modulate = Color.WHITE.lerp(Color(0.72, 0.76, 0.9), light.night)
		if street != null:
			street.set_night(light.night)


func _process(delta: float) -> void:
	var a := me()
	if a == null:
		return
	# 本地预测的校正：每帧吃掉一部分，人不会瞬移
	if _correction.length_squared() > 0.01:
		var step := _correction * minf(1.0, delta * 10.0)
		a.nudge(step)
		_correction -= step
	# 对方：落后服务器 DELAY 秒，从插值缓冲里取位置
	if net != null and net.clock.is_ready():
		var render_t: float = net.clock.server_now() - SnapshotBuffer.DELAY
		for r in actors:
			var other: Actor = actors[r]
			var buf = buffers[r]
			if not other.is_local and not buf.is_empty():
				other.net_target = buf.sample(render_t)
	camera.position = a.position
	_tap_t += delta
	_marks.queue_redraw()
	_send_timer += delta
	if _send_timer >= MOVE_SEND_INTERVAL:
		_send_timer = 0.0
		if a.position.distance_to(_last_sent) > 2.0:
			_last_sent = a.position
			move_report.emit(a.position)


func _unhandled_input(event: InputEvent) -> void:
	if not controllable or me() == null:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var target := get_global_mouse_position()
		target.x = clampf(target.x, 0.0, float(map.size[0]))
		target.y = clampf(target.y, 0.0, float(map.size[1]))
		if nav.ready():
			target = nav.snap(target)
			me().set_path(nav.path(me().position, target))
		else:
			me().walk_target = target
		_tap_fx = target
		_tap_t = 0.0


## 断线重连 / 进房时的快照：所有人直接放到服务器的位置
func apply_snapshot_actors(server_actors: Variant) -> void:
	if not server_actors is Dictionary:
		return
	for r in ["qing", "mei"]:
		var s: Variant = server_actors.get(r)
		var a: Actor = actors[r]
		if s == null:
			a.visible = false
			continue
		a.visible = true
		var pos := Vector2(float(s.x), float(s.y))
		a.position = pos
		a.walk_target = pos
		a.net_target = pos
		a.snap_remote = true
		buffers[r].clear()
	_correction = Vector2.ZERO
	_corrected_upto = 0
	_last_sent = Vector2.INF


## 服务器 5Hz 的世界广播
func apply_world(view: Dictionary) -> void:
	hints = view.get("hints", [])
	var tracks: Variant = view.get("tracks")
	if tracks is Dictionary:
		for r in tracks:
			duties[r] = tracks[r].get("duty") if tracks[r] is Dictionary else null
			unlocks[r] = tracks[r].get("unlocks", []) if tracks[r] is Dictionary else []
	if view.has("minute"):
		set_minute(float(view.minute))
	if view.has("slot"):
		slot = int(view.slot)
	playing = bool(view.get("playing", false))
	var t := float(view.get("tick", 0)) / TICK_RATE
	var busy: Array = []
	var qs: Variant = view.actors.get("qing")
	var ms: Variant = view.actors.get("mei")
	# 两个人在同一个点上做同一件事：左右错开半步，别叠成一个人
	var side_by_side: bool = qs != null and ms != null and qs.get("act") != null \
		and qs.get("act") == ms.get("act") and Vector2(qs.x, qs.y).distance_to(Vector2(ms.x, ms.y)) < 4.0
	for r in ["qing", "mei"]:
		var a: Actor = actors[r]
		var s: Variant = view.actors.get(r)
		if s == null:
			a.visible = false
			continue
		a.visible = true
		var server_pos := Vector2(s.x, s.y)
		if side_by_side:
			server_pos.x += -24.0 if r == "qing" else 24.0
		var act: Variant = s.get("act")
		if act != null:
			busy.append(str(act))
		a.asleep = bool(s.get("sleep", false))
		a.doing = "" if act == null else str(act)
		a.at_spot = str(s.get("spot", "")) if s.get("spot") != null else ""
		a.action_label = "" if act == null or a.asleep else _doing_label(r, str(act))
		a.together = bool(s.get("tg", false)) and a.action_label != ""
		if a.is_local:
			_reconcile(a, server_pos, act != null or a.asleep, int(s.get("seq", 0)))
		else:
			var buf = buffers[r]
			if net == null or not view.has("tick"):
				a.net_target = server_pos
			else:
				buf.push(t, server_pos)
	if street != null:
		street.set_busy(busy)
	queue_redraw()


## 本地预测 + 服务器校正：
## 服务器说「处理完你第 seq 条 MOVE 后你在 P」，我们查当时自己上报的位置 Q；
## P≈Q 说明服务器认可，什么都不做（不会被 200ms 前的旧位置往回拽）；
## P≠Q 说明被限速/边界截过，把差值 P-Q 平滑地加到现在的位置上。
func _reconcile(a: Actor, server_pos: Vector2, busy: bool, seq: int) -> void:
	if busy:
		# 在忙（被服务器放到行动点上、睡着了）：以服务器为准
		a.position = server_pos
		a.walk_target = server_pos
		_correction = Vector2.ZERO
		return
	var reference: Variant = null
	if seq > 0 and seq <= _corrected_upto:
		return
	if net != null and seq > 0:
		reference = net.sent_position(seq)
	if reference == null:
		if a.position.distance_to(server_pos) > SNAP_DIST:
			a.position = server_pos
			a.walk_target = server_pos
			_correction = Vector2.ZERO
		return
	var err: Vector2 = server_pos - (reference as Vector2)
	if err.length() > SNAP_DIST:
		a.position = server_pos
		a.walk_target = server_pos
		_correction = Vector2.ZERO
	elif err.length() > CORRECT_DEADZONE:
		_correction += err
		_corrected_upto = net.last_move_seq()


## 头顶上写的「正在做什么」。日程（duty）的名字跟着这个人走的路：上学 / 出摊 / 过桥上班
func _doing_label(role: String, act: String) -> String:
	if bool(actions.get(act, {}).get("duty", false)):
		var d: Variant = duties.get(role)
		if d is Dictionary:
			return str(d.get("label", "忙"))
	return str(actions.get(act, {}).get("label", act))


## 这个位置叫什么（HUD 上「对门在哪」用）。自己家写「家里」，串门写「你家」，不在哪块地方上就是路上
func place_name(pos: Vector2, role: String) -> String:
	for z in map.zones:
		if Rect2(z.rect[0], z.rect[1], z.rect[2], z.rect[3]).has_point(pos):
			if z.has("owner"):
				return "家里" if str(z.owner) == role else ("你家" if str(z.owner) == my_role else str(z.name))
			return str(z.name)
	return "路上"


## 离自己最近、够得着、现在有事可做的互动点
func nearest_spot() -> Dictionary:
	var a := me()
	if a == null or not a.visible or a.action_label != "" or a.asleep:
		return {}
	var best: Dictionary = {}
	var best_d := SPOT_RADIUS
	for sp in map.spots:
		var d := a.position.distance_to(Vector2(sp.at[0], sp.at[1]))
		if d < best_d and not action_of(sp).is_empty():
			best_d = d
			best = sp
	return best


## 我今天该去的地方（还去得了才算）。没有返回 {}
func my_duty() -> Dictionary:
	var d: Variant = duties.get(my_role)
	if d is Dictionary and bool(d.get("open", false)):
		return d
	return {}


## 我现在在这个点位上能做的事。和服务器 world.ts 的 worldPickAction 一个规则：
## 点位上的行动按顺序看，日程只给今天该来这儿、还来得及的人，其余按年纪、关口上挣来的资格、钟点取第一件合适的。没有就是 {}
func action_of(spot: Dictionary) -> Dictionary:
	var late := {}
	var ids: Array = spot.get("actions", [])
	if ids.is_empty() and spot.has("action"):
		ids = [spot.action]
	for id in ids:
		var act: Dictionary = actions.get(id, {})
		if act.is_empty():
			continue
		if bool(act.get("duty", false)):
			var d := my_duty()
			if not d.is_empty() and str(d.get("spot", "")) == str(spot.id):
				var mine := act.duplicate()
				mine["label"] = str(d.get("label", act.get("label", "")))
				mine["until"] = d.get("until")
				return mine
			continue
		var rq: Dictionary = act.get("requires", {})
		if rq.has("minAge") and age < int(rq.minAge):
			continue
		if rq.has("maxAge") and age > int(rq.maxAge):
			continue
		# 标记在服务器手里，客户端只认它发来的那张单子
		if (rq.has("flags") or rq.has("notFlags")) and not (unlocks.get(my_role, []) as Array).has(str(id)):
			continue
		# 不在钟点上先看后面还有没有别的事；都没有就还是它（点了服务器回「现在不是时候」）
		var hours: Variant = rq.get("hours")
		if hours is Array and hours.size() == 2 and not overlaps(hours, slot):
			if late.is_empty():
				late = act
			continue
		return act
	return late


## 这一分钟在第几段
static func slot_at(m: float) -> int:
	for i in SLOTS.size():
		if m < float(SLOTS[i][1]):
			return i
	return SLOTS.size() - 1


## 钟点窗 [从, 到] 和第 i 段有没有重叠（服务器 worldOverlaps）
static func overlaps(win: Array, i: int) -> bool:
	return float(win[0]) < float(SLOTS[i][1]) and float(win[1]) > float(SLOTS[i][0])


## 对门正在这个点位上做同一件事：现在过去就是搭伴
func partner_doing(spot: Dictionary, act: Dictionary) -> bool:
	var other: Actor = actors.get("mei" if my_role == "qing" else "qing")
	if other == null or not other.visible or other.asleep or act.is_empty():
		return false
	return other.doing == str(act.get("id", "")) and other.at_spot == str(spot.get("id", ""))


# ======================================================================
# 互动点 + 命运提示（在叠印层之上）
# ======================================================================

func draw_marks(c: CanvasItem) -> void:
	if map.is_empty():
		return
	var f := P.font()
	var near := nearest_spot()
	var t := _tap_t
	var labeled: Array = []  ## 挨得很近的同名互动点（两扇门）只写一次
	# 点击落点：一个墨圈散开
	if _tap_fx != Vector2.INF and t < 0.6:
		c.draw_arc(_tap_fx, 10.0 + t * 40.0, 0, TAU, 24, Color(P.INK, 0.6 * (1.0 - t / 0.6)), 2.0)
	var duty := my_duty()
	for sp in map.spots:
		var at := Vector2(sp.at[0], sp.at[1])
		var act := action_of(sp)
		if act.is_empty():
			continue  # 这个年纪、这个时候在这儿没事可做：不画，免得走过去扑个空
		var is_near: bool = not near.is_empty() and near.id == sp.id
		var is_duty: bool = not duty.is_empty() and str(duty.get("spot", "")) == str(sp.id)
		var r := 9.0 + (sin(Time.get_ticks_msec() / 220.0) * 2.0 if is_near else 0.0)
		if is_duty and not is_near:
			# 今天该去的地方：一圈自己颜色的波纹往外散，远远就看得见
			var k := fmod(Time.get_ticks_msec() / 1400.0, 1.0)
			c.draw_arc(at, 14.0 + k * 34.0, 0, TAU, 32, Color(P.role_color(my_role), 0.9 * (1.0 - k)), 4.0, true)
		c.draw_circle(at, r, Color(P.PAPER, 0.85))
		c.draw_arc(at, r, 0, TAU, 20, P.MEI if is_near else Color(P.INK, 0.7), 2.4)
		c.draw_circle(at, 3.0, P.MEI if is_near else Color(P.INK, 0.7))
		if is_near:
			continue  # 走近了由底部按钮显示，不重复
		var label := str(act.get("label", ""))
		if is_duty:
			var from: int = int((duty.get("slots", [slot]) as Array)[0])
			label += " · %s" % ("现在" if from <= slot else str(SLOTS[from][2]))
		var dup := false
		for l in labeled:
			if l[0] == label and (l[1] as Vector2).distance_to(at) < 120.0:
				dup = true
		if dup:
			continue
		labeled.append([label, at])
		var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		c.draw_rect(Rect2(at + Vector2(-w / 2.0 - 6, 16), Vector2(w + 12, 26)), Color(P.PAPER, 0.8))
		c.draw_string(f, at + Vector2(-w / 2.0, 36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(P.INK, 0.75))
	# 命运的提示：一行很淡的字，飘在那个地方
	for h in hints:
		for z in map.zones:
			if z.id == h.zone:
				var top := Vector2(z.rect[0] + z.rect[2] / 2.0, z.rect[1] + 36 + sin(Time.get_ticks_msec() / 900.0) * 4.0)
				var tw := f.get_string_size(str(h.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
				c.draw_rect(Rect2(top + Vector2(-tw / 2.0 - 10, -26), Vector2(tw + 20, 38)), Color(P.PAPER, 0.85))
				c.draw_string(f, top - Vector2(tw / 2.0, 0), str(h.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, P.OVERLAP)


class _Marks extends Node2D:
	var view: Node

	func _init(v: Node) -> void:
		view = v

	func _draw() -> void:
		view.draw_marks(self)


# ======================================================================
# 占位地图（没有生成美术时）
# ======================================================================

func _draw() -> void:
	if map.is_empty() or (art != null and art.has_art):
		return
	var f := P.font()
	for z in map.zones:
		var r := Rect2(z.rect[0], z.rect[1], z.rect[2], z.rect[3])
		match z.id:
			"alley":  # 楼下的街：柏油路 + 自行车道虚线
				draw_rect(r, P.PAPER_DARK)
				draw_line(r.position, r.position + Vector2(r.size.x, 0), P.INK, 3.0)
				draw_line(r.position + Vector2(0, r.size.y), r.end, P.INK, 3.0)
				var x := 30.0
				while x < r.size.x:
					draw_line(r.position + Vector2(x, r.size.y / 2.0), r.position + Vector2(x + 60, r.size.y / 2.0), Color(P.INK, 0.3), 3.0)
					x += 140.0
			"river":  # 海河：青色水纹 + 一座铁桥
				draw_rect(r, Color(P.QING, 0.10))
				for i in 22:
					var y := r.position.y + 40.0 + i * 60.0
					var x0 := r.position.x + 30.0 + fmod(i * 37.0, 120.0)
					draw_arc(Vector2(x0, y), 26.0, PI * 1.1, PI * 1.9, 10, Color(P.QING, 0.6), 2.5)
					draw_arc(Vector2(x0 + 180.0, y + 20.0), 26.0, PI * 1.1, PI * 1.9, 10, Color(P.QING, 0.6), 2.5)
				var by := r.position.y + 520.0
				draw_line(Vector2(r.position.x - 20, by), Vector2(r.end.x, by), P.INK, 5.0)
				draw_line(Vector2(r.position.x - 20, by + 60), Vector2(r.end.x, by + 60), P.INK, 5.0)
				var bx := r.position.x
				while bx < r.end.x:  # 桥上的钢桁架
					draw_line(Vector2(bx, by), Vector2(bx + 40, by + 60), P.INK, 2.0)
					draw_line(Vector2(bx + 40, by + 60), Vector2(bx + 80, by), P.INK, 2.0)
					bx += 80.0
			"roof":  # 楼顶：晾衣绳上一件青、一件梅，几只鸽子
				_zone_frame(r, Color(P.INK, 0.03))
				var y0 := r.position.y + 60.0
				draw_line(Vector2(r.position.x + 120, y0), Vector2(r.position.x + 560, y0 + 10), P.INK, 2.0)
				draw_rect(Rect2(r.position.x + 220, y0 + 4, 50, 60), Color(P.QING, 0.8))
				draw_rect(Rect2(r.position.x + 330, y0 + 6, 50, 60), Color(P.MEI, 0.8))
				draw_line(Vector2(r.position.x + 900, r.end.y), Vector2(r.position.x + 900, r.position.y + 10), P.INK, 3.0)  # 天线
				draw_line(Vector2(r.position.x + 860, r.position.y + 40), Vector2(r.position.x + 940, r.position.y + 40), P.INK, 3.0)
				for i in 5:
					var g := Vector2(r.position.x + 700 + i * 60.0, r.position.y + 30.0 + sin(i * 1.7) * 14.0)
					draw_line(g + Vector2(-12, -6), g, P.INK, 2.5)
					draw_line(g, g + Vector2(12, -6), P.INK, 2.5)
			"breakfast":  # 早点铺：摊子 + 热气
				_zone_frame(r, Color(P.MEI, 0.05))
				var c := r.get_center()
				draw_rect(Rect2(c + Vector2(-110, 10), Vector2(220, 70)), P.PAPER)
				draw_rect(Rect2(c + Vector2(-110, 10), Vector2(220, 70)), P.INK, false, 3.0)
				draw_circle(c + Vector2(-40, 0), 34.0, Color(P.INK, 0.1))  # 鏊子
				draw_arc(c + Vector2(-40, 0), 34.0, 0, TAU, 32, P.INK, 3.0)
				for i in 3:
					var sx := c.x - 70.0 + i * 30.0
					draw_arc(Vector2(sx, c.y - 60), 14.0, PI * 0.5, PI * 1.5, 8, Color(P.INK, 0.4), 2.0)
					draw_arc(Vector2(sx + 6, c.y - 88), 14.0, -PI * 0.5, PI * 0.5, 8, Color(P.INK, 0.4), 2.0)
				draw_string(f, c + Vector2(20, -30), "煎饼果子", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, P.MEI)
			"hallway":  # 楼道：一级级台阶
				draw_rect(r, Color(P.INK, 0.05))
				for i in 8:
					var sy := r.position.y + 40.0 + i * 50.0
					draw_line(Vector2(r.position.x + 10, sy), Vector2(r.end.x - 10, sy), Color(P.INK, 0.35), 2.0)
			_:
				var tint := Color(0, 0, 0, 0)
				if z.has("owner"):
					tint = Color(P.role_color(z.owner), 0.07)
				_zone_frame(r, tint)
				if z.has("owner"):  # 红砖墙的砖缝
					for row in 3:
						var wy := r.end.y - 52.0 + row * 14.0
						var off := 0.0 if row % 2 == 0 else 20.0
						var wx := r.position.x + off
						while wx < r.end.x - 30.0:
							draw_rect(Rect2(wx, wy, 34, 10), Color(P.MEI, 0.18))
							wx += 40.0
		draw_string(f, r.position + Vector2(20, 44), str(z.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 32, P.INK_SOFT)


func _zone_frame(r: Rect2, fill: Color) -> void:
	if fill.a > 0.0:
		draw_rect(r, fill)
	# 手绘感：线条两端各出头一点
	var e := 10.0
	draw_line(r.position + Vector2(-e, 0), Vector2(r.end.x + e, r.position.y), P.INK, 3.0)
	draw_line(Vector2(r.position.x - e, r.end.y), r.end + Vector2(e, 0), P.INK, 3.0)
	draw_line(r.position + Vector2(0, -e), Vector2(r.position.x, r.end.y + e), P.INK, 3.0)
	draw_line(Vector2(r.end.x, r.position.y - e), r.end + Vector2(0, e), P.INK, 3.0)
