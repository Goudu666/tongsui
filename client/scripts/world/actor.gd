extends Node2D
## 河畔里的一个孩子（会长大）。本地玩家沿寻路的路径走；对方按服务器广播插值。
## 外观是孔版套色的侧视精灵表 res://art/actors/{role}_{stage}.png（tools/art/actors.py 用骨架摆出来）：
##   8 列 × 3 行，每格 200×220 世界像素（贴图 2 倍），脚底在格子里的 (100, 206)，人朝右（朝左翻转）
##   行 0：走一整步 8 帧
##   行 1：0~3 站着喘气（3 眨眼），4~7 在忙
##   行 2：0~1 坐着，2~3 睡觉，4~7 挥手
## 精灵按世界像素原大画：不管 world_view 把这个节点放大多少，人还是那么高（名字牌跟着节点放大）。
## 没有贴图时退回 M0 的墨线简笔。

const P := preload("res://scripts/ui/palette.gd")
const WALK_SPEED := 330.0  ## 略低于服务器限速
const CELL := Vector2(200, 220)
const FOOT := Vector2(100, 206)
const COLS := 8
const ROWS := 3
## 每个年纪的身高（世界像素，梅比青矮 6）、走一整步前进多远
const HEIGHT := {"childhood": 112.0, "teen": 152.0, "young": 172.0, "middle": 170.0, "old": 160.0}
const STRIDE := {"childhood": 74.0, "teen": 104.0, "young": 120.0, "middle": 112.0, "old": 78.0}
const ART_SCALE := 2.0
const STAGES := ["childhood", "teen", "young", "middle", "old"]
const STAGE_FILE := {"childhood": "child", "teen": "teen", "young": "young", "middle": "middle", "old": "old"}
## 做这些事的时候坐着，其它事是"在忙"的姿势（行动 id，见 content/map.yaml）
const SIT_ACTIONS := ["eat", "eat_out", "dine", "picture_book", "study", "read"]
const WAVE_ACTIONS := ["knock"]

var role := "qing"
var display_name := ""
var is_local := false
var net_target := Vector2.ZERO   ## 远端：插值缓冲算出的位置（已经是平滑的）
var snap_remote := false         ## 下一帧直接跳到 net_target（重连快照）
var action_label := ""
var doing := ""                  ## 正在做的行动 id（没在做是 ""）
var at_spot := ""                ## 在哪个点位上做
var together := false            ## 这一次是两个人搭伴做的（长得快）
var asleep := false
var walking := false
var stage := "childhood"
## 兼容旧接口：直接设目标 = 走直线过去
var walk_target := Vector2.ZERO:
	set(v):
		walk_target = v
		_path = PackedVector2Array([v])

var _path := PackedVector2Array()
var _t := 0.0
var _dir := 2       ## 2 朝右 3 朝左（侧视只有左右，竖着挪的时候保持原来的朝向）
var _phase := 0.0   ## 走路走到一步里的哪儿（0~8 帧）
var _idle := 0.0    ## 站着、坐着、在忙的小动作
var _sprite: Sprite2D
var _last_pos := Vector2.ZERO


func setup(p_role: String, p_name: String, p_local: bool, pos: Vector2) -> void:
	role = p_role
	display_name = p_name
	is_local = p_local
	position = pos
	_last_pos = pos
	walk_target = pos
	net_target = pos
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.hframes = COLS
	_sprite.vframes = ROWS
	_sprite.scale = Vector2.ONE / ART_SCALE
	_sprite.offset = -FOOT * ART_SCALE
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sprite)
	set_stage(stage)


## 按人生阶段换外观（LifeTime.at(turn).stage）
func set_stage(p_stage: String) -> void:
	stage = p_stage if p_stage in STAGES else "childhood"
	if _sprite == null:
		return
	var path := "res://art/actors/%s_%s.png" % [role, STAGE_FILE[stage]]
	_sprite.texture = load(path) if ResourceLoader.exists(path) else null
	_sprite.visible = _sprite.texture != null


func set_path(points: PackedVector2Array) -> void:
	_path = points


## 服务器校正：人和还没走完的路一起平移，不会被拽回去再走一遍
func nudge(step: Vector2) -> void:
	position += step
	for i in _path.size():
		_path[i] += step


func _process(delta: float) -> void:
	_t += delta
	var before := position
	if is_local:
		var busy := action_label != "" or asleep
		var budget := WALK_SPEED * delta
		while not busy and budget > 0.0 and not _path.is_empty():
			var to := _path[0] - position
			if to.length() <= budget:
				position = _path[0]
				budget -= to.length()
				_path.remove_at(0)
			else:
				position += to.normalized() * budget
				budget = 0.0
	else:
		if snap_remote or position.distance_to(net_target) > 500.0:
			position = net_target
			before = position  # 瞬移不算走路
			snap_remote = false
		else:
			# 缓冲给出的已经是匀速轨迹，这里只做很轻的平滑，抹掉帧间的小抖动
			position = position.lerp(net_target, 1.0 - exp(-25.0 * delta))
	var v := (position - before) / maxf(delta, 0.001)
	walking = absf(v.x) > 25.0
	if walking:
		_dir = 2 if v.x > 0 else 3
		# 按走了多远翻帧：一整步 8 帧，脚底基本不打滑
		_phase += absf(v.x) * delta / float(STRIDE.get(stage, 110.0)) * 8.0
	else:
		_phase = 0.0
	_idle += delta
	# 精灵按世界原大：抵消掉节点自己的放大
	if _sprite != null and not is_equal_approx(_sprite.scale.x * scale.x, 1.0 / ART_SCALE):
		_sprite.scale = Vector2.ONE / (ART_SCALE * maxf(scale.x, 0.01))
	_update_frame()
	queue_redraw()


func _update_frame() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var row := 1
	var col := 0
	_sprite.flip_h = _dir == 3
	if asleep:
		row = 2
		col = 2 + int(_idle / 1.6) % 2
	elif doing in SIT_ACTIONS:
		row = 2
		col = int(_idle / 0.7) % 2
	elif doing in WAVE_ACTIONS:
		row = 2
		col = 4 + int(_idle * 7.0) % 4
	elif action_label != "":
		col = 4 + int(_idle * 5.0) % 4
	elif walking:
		row = 0
		col = int(_phase) % 8
	else:
		# 站着：慢慢喘气，隔几秒眨一下眼
		var k := int(_idle * 2.2) % 4
		col = 3 if fmod(_idle + float(role.length()), 4.3) < 0.14 else (k if k < 3 else 1)
	_sprite.frame = row * COLS + col


func _draw() -> void:
	var c := P.role_color(role)
	# 脚下的影子（墨网点的感觉：半透明墨）
	var w := 26.0 if stage == "childhood" else 32.0
	draw_set_transform(Vector2(4, 2), 0.0, Vector2(1.0, 0.36))
	draw_circle(Vector2.ZERO, w, Color(P.INK, 0.16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _sprite != null and _sprite.visible:
		var head := -_height() / maxf(scale.x, 0.01) - 14.0
		_name_tag(c)
		if asleep:
			_text("z z", Vector2(34, head + 30 + sin(_t * 2.0) * 6.0), 28, P.INK_SOFT)
		elif action_label != "":
			_text(_doing_text(), Vector2(0, head - 8 + sin(_t * 3.0) * 3.0), 24, P.OVERLAP if together else P.INK_SOFT)
		return
	_draw_fallback(c)


func _doing_text() -> String:
	return ("一起" if together else "") + action_label + "中…"


## 脚下的名字：垫一小片纸，压在网点和砖缝上也看得清。自己的那片多一条色边
func _name_tag(c: Color) -> void:
	var f := P.font()
	var w := f.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var r := Rect2(-w / 2.0 - 9.0, 12.0, w + 18.0, 30.0)
	if is_local:
		draw_rect(Rect2(r.position + Vector2(3, 3), r.size), c)
	draw_rect(r, Color(P.PAPER, 0.94))
	draw_rect(r, Color(P.INK, 0.8), false, 1.5)
	draw_string(f, Vector2(-w / 2.0, 35.0), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, c)


## 精灵里的人有多高（世界像素）
func _height() -> float:
	return float(HEIGHT.get(stage, 160.0)) - (6.0 if role == "mei" else 0.0)


func _draw_fallback(c: Color) -> void:
	var bob := sin(_t * 12.0) * 4.0 if walking else 0.0
	if asleep:
		draw_circle(Vector2(0, -24), 26.0, Color(c, 0.85))
		draw_arc(Vector2(0, -24), 26.0, 0, TAU, 32, P.INK, 3.0)
		_text("z z", Vector2(30, -64 + sin(_t * 2.0) * 6.0), 30, P.INK_SOFT)
		return
	var body := Rect2(Vector2(-20, -40 + bob), Vector2(40, 44))
	draw_rect(Rect2(body.position + Vector2(3, 2), body.size), Color(c, 0.9))
	draw_rect(body, P.INK, false, 3.0)
	draw_circle(Vector2(3, -64 + bob), 22.0, Color(c, 0.9))
	draw_arc(Vector2(0, -66 + bob), 22.0, 0, TAU, 32, P.INK, 3.0)
	draw_circle(Vector2(-7, -68 + bob), 2.5, P.INK)
	draw_circle(Vector2(7, -68 + bob), 2.5, P.INK)
	_text(display_name, Vector2(0, 36), 28, c)
	if action_label != "":
		_text(_doing_text(), Vector2(0, -104 + sin(_t * 3.0) * 3.0), 26, P.OVERLAP if together else P.INK_SOFT)


func _text(s: String, at: Vector2, size: int, color: Color) -> void:
	var f := P.font()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(f, at - Vector2(w / 2.0, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
