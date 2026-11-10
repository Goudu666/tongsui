extends Node2D
## 河畔里的一个孩子（会长大）。本地玩家沿寻路的路径走；对方按服务器广播插值。
## 外观是孔版套色的精灵表 res://art/actors/{role}_{stage}.png（tools/art/actors.py 生成）：
##   6 列 × 4 行，每格 96×128 世界像素（贴图 2 倍），脚底在格子里的 (48, 120)
##   行 0 朝下 / 1 朝上 / 2 朝右（朝左翻转）：列 0 站、1~4 走、5 在忙
##   行 3：列 0 睡觉、1 挥手、2 坐着
## 没有贴图时退回 M0 的墨线简笔。

const P := preload("res://scripts/ui/palette.gd")
const WALK_SPEED := 330.0  ## 略低于服务器限速
const CELL := Vector2(96, 128)
const FOOT := Vector2(48, 120)
const ART_SCALE := 2.0
const STAGES := ["childhood", "teen", "young", "middle", "old"]
const STAGE_FILE := {"childhood": "child", "teen": "teen", "young": "young", "middle": "middle", "old": "old"}
## 做这些事的时候坐着，其它事是"在忙"的姿势
const SIT_ACTIONS := ["吃饭", "写作业"]
const WAVE_ACTIONS := ["开门喊一声"]

var role := "qing"
var display_name := ""
var is_local := false
var net_target := Vector2.ZERO   ## 远端：插值缓冲算出的位置（已经是平滑的）
var snap_remote := false         ## 下一帧直接跳到 net_target（重连快照）
var action_label := ""
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
var _dir := 0       ## 0 下 1 上 2 右 3 左
var _phase := 0.0
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
	_sprite.hframes = 6
	_sprite.vframes = 4
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
	walking = v.length() > 25.0
	if walking:
		if absf(v.x) > absf(v.y) * 1.1:
			_dir = 2 if v.x > 0 else 3
		else:
			_dir = 0 if v.y > 0 else 1
		_phase += delta * clampf(v.length() / 300.0, 0.5, 1.2) * 9.0
	else:
		_phase = 0.0
	_update_frame()
	queue_redraw()


func _update_frame() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var row := 0 if _dir == 0 else (1 if _dir == 1 else 2)
	var col := 0
	_sprite.flip_h = _dir == 3
	if asleep:
		row = 3
		col = 0
		_sprite.flip_h = role == "mei"
	elif action_label in SIT_ACTIONS:
		row = 3
		col = 2
		_sprite.flip_h = false
	elif action_label in WAVE_ACTIONS:
		row = 3
		col = 1
		_sprite.flip_h = false
	elif action_label != "":
		col = 5
	elif walking:
		col = 1 + int(_phase) % 4
	_sprite.frame = row * 6 + col


func _draw() -> void:
	var c := P.role_color(role)
	# 脚下的影子（墨网点的感觉：半透明墨）
	var w := 26.0 if stage == "childhood" else 32.0
	draw_set_transform(Vector2(4, 2), 0.0, Vector2(1.0, 0.36))
	draw_circle(Vector2.ZERO, w, Color(P.INK, 0.16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _sprite != null and _sprite.visible:
		var head := -CELL.y * _height_ratio()
		_text(display_name, Vector2(0, 30), 24, c)
		if asleep:
			_text("z z", Vector2(34, head + 30 + sin(_t * 2.0) * 6.0), 28, P.INK_SOFT)
		elif action_label != "":
			_text(action_label + "中…", Vector2(0, head - 8 + sin(_t * 3.0) * 3.0), 24, P.INK_SOFT)
		return
	_draw_fallback(c)


func _height_ratio() -> float:
	return {"childhood": 0.58, "teen": 0.74, "young": 0.82, "middle": 0.80, "old": 0.76}.get(stage, 0.7)


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
		_text(action_label + "中…", Vector2(0, -104 + sin(_t * 3.0) * 3.0), 26, P.INK_SOFT)


func _text(s: String, at: Vector2, size: int, color: Color) -> void:
	var f := P.font()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(f, at - Vector2(w / 2.0, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
