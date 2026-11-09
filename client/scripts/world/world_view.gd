extends Node2D
## 河畔里：按 content.json 里的地图画出来，放两个孩子，点哪走哪。
## 画面全部用 _draw 的墨线完成（M0 占位美术），之后替换成手绘贴图时只改这里。

signal move_report(pos: Vector2)

const P := preload("res://scripts/ui/palette.gd")
const Actor := preload("res://scripts/world/actor.gd")
const SPOT_RADIUS := 100.0  ## 比服务器的 110 小一点，避免边缘抖动
const MOVE_SEND_INTERVAL := 0.1
const SnapshotBuffer := preload("res://scripts/net/snapshot_buffer.gd")
const TICK_RATE := 10.0
const CORRECT_DEADZONE := 6.0   ## 服务器和本地差这么点就不管
const SNAP_DIST := 220.0        ## 差太多（换天回家、被叫去事件）直接到位

var map: Dictionary = {}
var actions: Dictionary = {}
var my_role := "qing"
var actors: Dictionary = {}  ## role -> Actor
var hints: Array = []
var controllable := true
var camera: Camera2D
var _send_timer := 0.0
var _last_sent := Vector2.INF
## 联机客户端（lifeline_client.gd）：提供服务器时钟和「第 seq 条 MOVE 我在哪」。离线逛逛时为 null
var net = null
var buffers: Dictionary = {}    ## role -> SnapshotBuffer（只用于对方）
var _correction := Vector2.ZERO ## 本地角色还没消化掉的服务器校正量
var _corrected_upto := 0        ## 这个序号及以前的 MOVE 是在校正之前发的，不再拿来校正（避免重复校正）


func setup(content: Dictionary, role: String, names: Dictionary) -> void:
	map = content.map
	for a in map.actions:
		actions[a.id] = a
	my_role = role
	for r in ["qing", "mei"]:
		var sp: Array = map.spawn[r]
		var actor := Actor.new()
		actor.setup(r, str(names.get(r, P.ROLE_NAME[r])), r == role, Vector2(sp[0], sp[1]))
		add_child(actor)
		actors[r] = actor
		buffers[r] = SnapshotBuffer.new()
	camera = Camera2D.new()
	camera.zoom = Vector2.ONE * 1.2
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(map.size[0])
	camera.limit_bottom = int(map.size[1])
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	camera.make_current()
	queue_redraw()


func me() -> Actor:
	return actors.get(my_role)


func _process(delta: float) -> void:
	var a := me()
	if a == null:
		return
	# 本地预测的校正：每帧吃掉一部分，人不会瞬移
	if _correction.length_squared() > 0.01:
		var step := _correction * minf(1.0, delta * 10.0)
		a.position += step
		a.walk_target += step
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
		me().walk_target = target


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
	var t := float(view.get("tick", 0)) / TICK_RATE
	for r in ["qing", "mei"]:
		var a: Actor = actors[r]
		var s: Variant = view.actors.get(r)
		if s == null:
			a.visible = false
			continue
		a.visible = true
		var server_pos := Vector2(s.x, s.y)
		var act: Variant = s.get("act")
		a.asleep = bool(s.get("sleep", false))
		a.action_label = "" if act == null or a.asleep else str(actions.get(act, {}).get("label", act))
		if a.is_local:
			_reconcile(a, server_pos, act != null or a.asleep, int(s.get("seq", 0)))
		else:
			var buf = buffers[r]
			if net == null or not view.has("tick"):
				a.net_target = server_pos
			else:
				buf.push(t, server_pos)
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


## 离自己最近、够得着的互动点
func nearest_spot() -> Dictionary:
	var a := me()
	if a == null or not a.visible or a.action_label != "" or a.asleep:
		return {}
	var best: Dictionary = {}
	var best_d := SPOT_RADIUS
	for sp in map.spots:
		var d := a.position.distance_to(Vector2(sp.at[0], sp.at[1]))
		if d < best_d:
			best_d = d
			best = sp
	return best


func action_of(spot: Dictionary) -> Dictionary:
	return actions.get(spot.get("action", ""), {})


# ======================================================================
# 画地图
# ======================================================================

func _draw() -> void:
	if map.is_empty():
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

	# 互动点
	for sp in map.spots:
		var at := Vector2(sp.at[0], sp.at[1])
		draw_circle(at, 12.0, P.PAPER)
		draw_arc(at, 12.0, 0, TAU, 20, P.INK, 2.5)
		var label := str(action_of(sp).get("label", ""))
		var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string(f, at + Vector2(-w / 2.0, 42), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(P.INK, 0.55))

	# 命运的提示：一行很淡的字，飘在那个地方
	for h in hints:
		for z in map.zones:
			if z.id == h.zone:
				var top := Vector2(z.rect[0] + z.rect[2] / 2.0, z.rect[1] - 16)
				var tw := f.get_string_size(str(h.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
				draw_string(f, top - Vector2(tw / 2.0, 0), str(h.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(P.OVERLAP, 0.75))


func _zone_frame(r: Rect2, fill: Color) -> void:
	if fill.a > 0.0:
		draw_rect(r, fill)
	# 手绘感：线条两端各出头一点
	var e := 10.0
	draw_line(r.position + Vector2(-e, 0), Vector2(r.end.x + e, r.position.y), P.INK, 3.0)
	draw_line(Vector2(r.position.x - e, r.end.y), r.end + Vector2(e, 0), P.INK, 3.0)
	draw_line(r.position + Vector2(0, -e), Vector2(r.position.x, r.end.y + e), P.INK, 3.0)
	draw_line(Vector2(r.end.x, r.position.y - e), r.end + Vector2(0, e), P.INK, 3.0)
