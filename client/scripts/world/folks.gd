extends Node2D
## 横版的街坊和路人：只是画面，不进结算。
##   街坊：client/data/folks.json（content/maps/<图>.yaml 的 npcs，npm run content 生成）说谁在哪张图、哪个年纪在、几段在、搭什么腔；
##        长相和营生动作是 client/art/folks/<图>.png（tools/art/folks.py）：一人一行，列 0~3 干活、4~7 歇着。
##        干一阵、歇一阵，干活时头顶偶尔冒个气泡；你走近了转过脸来搭一句（一个人二十多秒最多说一回）。
##   路人：client/art/folks/walkers.png，一种一行 8 帧走路。白天隔几秒从图的一头走到另一头，夜里稀稀拉拉；
##        分前后两道：后道的小一点、浅一点，从人身后过；前道的从人跟前过。屋里（楼里、出租屋）没有路人。
## world_view 把它挂在 street 上（同 street_life 的接口：set_stage / set_minute / set_night / set_busy），换图时调 show_scene。

const P := preload("res://scripts/ui/palette.gd")
const Bubble := preload("res://scripts/world/bubble.gd")
const Overlay := preload("res://scripts/world/overlay.gd")
const FOLKS_PATH := "res://data/folks.json"
const INDEX_PATH := "res://art/folks/index.json"
## 一天五段的起点（同 world_view.SLOTS）
const SLOT_STARTS := [390, 480, 720, 930, 1110, 1320]
const SLOT_IDS := ["morning", "am", "pm", "evening", "night"]
const INDOOR := ["building", "rental"]
const TALK_DIST := 190.0
const TALK_COOLDOWN := 24.0
## 给主角让地方：只在主角停下来做事、站得跟街坊几乎叠在一块时才让；走过去不让（以前一走近就滑开 95，像被挤走）
const GIVE_NEAR := 70.0   ## 叠得多近才算挡着
const GIVE_WAIT := 0.6    ## 停下来做事多久之后才挪（刚到跟前不动）
const GIVE_STEP := 78.0   ## 挪一步多远
const GIVE_SPEED := 70.0  ## 慢慢踱过去（像迈了一步），不是滑
const BACK_WAIT := 1.2    ## 人走了等一下再踱回原处

var world: Node = null        ## world_view（拿主角的位置）
var stage := "childhood"
var minute := 480.0
var night := 0.0
var scene: Dictionary = {}
var _folks: Dictionary = {}   ## 图 id → [街坊]
var _index: Dictionary = {}
var _walk_tex: Texture2D
var _tex: Texture2D
var _people: Array = []       ## 眼前这张图上的街坊（Folk）
var _walkers: Array = []      ## 正在走的路人（Walker）
var _spawn_wait := 1.5
var _slot := -1
var talk_until := 0.0  ## 同一时间只让一位街坊开口（几个人挨着站时纸条不叠在一块）


func _ready() -> void:
	y_sort_enabled = true
	_folks = _load_json(FOLKS_PATH)
	_index = _load_json(INDEX_PATH)
	if ResourceLoader.exists("res://art/folks/walkers.png"):
		_walk_tex = load("res://art/folks/walkers.png")


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func set_stage(s: String) -> void:
	if s != stage:
		stage = s
		_rebuild()


func set_minute(m: float) -> void:
	minute = m
	var sl := _slot_of(m)
	if sl != _slot:
		_slot = sl
		_rebuild()


func set_night(n: float) -> void:
	night = n


func set_busy(_busy: Array) -> void:
	pass


func show_scene(sc: Dictionary) -> void:
	scene = sc
	var path := "res://art/folks/%s.png" % str(sc.get("id", ""))
	_tex = load(path) if ResourceLoader.exists(path) else null
	for w in _walkers:
		w.queue_free()
	_walkers.clear()
	_spawn_wait = randf_range(0.5, 2.5)
	_rebuild()


func _slot_of(m: float) -> int:
	for i in range(SLOT_IDS.size() - 1, -1, -1):
		if m >= float(SLOT_STARTS[i]):
			return i
	return 0


## 按图、年纪、时段把街坊摆出来（已经在的不动，保住他们手上干到哪儿了）
func _rebuild() -> void:
	if scene.is_empty():
		return
	var sid := str(scene.get("id", ""))
	var want: Dictionary = {}
	for n in _folks.get(sid, []):
		var eras: Array = n.get("eras", [])
		var slots: Array = n.get("slots", [])
		if not eras.is_empty() and not stage in eras:
			continue
		if not slots.is_empty() and not SLOT_IDS[clampi(_slot, 0, 4)] in slots:
			continue
		if not _index.get("folks", {}).has(str(n.id)):
			continue
		want[str(n.id)] = n
	for f in _people.duplicate():
		if not want.has(f.id) or f.scene_id != sid:
			_people.erase(f)
			f.queue_free()
	var have := {}
	for f in _people:
		have[f.id] = true
	var floors: Array = scene.get("floors", [0])
	for id in want:
		if have.has(id) or _tex == null:
			continue
		var n: Dictionary = want[id]
		var info: Dictionary = _index.folks[id]
		var f := Folk.new()
		f.id = id
		f.scene_id = sid
		f.display_name = str(n.get("name", ""))
		f.lines = n.get("lines", {})
		f.bubbles = info.get("bubbles", ["dots"])
		f.host = self
		var fl := clampi(int(n.get("floor", floors.size() - 1)), 0, floors.size() - 1)
		f.position = Vector2(float(n.at), float(floors[fl]) - 1.0)
		add_child(f)
		f.setup(_tex, int(info.row), _tex.get_height() / int(float(_index.cell[1]) * float(_index.scale)), float(_index.scale), Vector2(_index.foot[0], _index.foot[1]))
		_people.append(f)


func _process(delta: float) -> void:
	if scene.is_empty() or _walk_tex == null:
		return
	var sid := str(scene.get("id", ""))
	if sid in INDOOR:
		return
	_spawn_wait -= delta
	var max_n := 1 if night > 0.6 else 3
	if _spawn_wait <= 0.0:
		_spawn_wait = randf_range(9.0, 16.0) if night > 0.6 else randf_range(3.5, 8.0)
		if _walkers.size() < max_n:
			_spawn_walker()
	for w in _walkers.duplicate():
		if w.position.x < -120.0 or w.position.x > float(scene.get("width", 4000)) + 120.0:
			_walkers.erase(w)
			w.queue_free()


func _spawn_walker() -> void:
	var names: Array = _index.get("walkers", [])
	if names.is_empty():
		return
	var row := randi() % names.size()
	# 小孩、学生只在白天；拄拐的老人走得慢
	var floors: Array = scene.get("floors", [0])
	var w := Walker.new()
	var back := randf() < 0.6
	var left := randf() < 0.5
	w.speed = (48.0 if str(names[row]) == "cane_old" else randf_range(70.0, 95.0)) * (1.0 if left else -1.0)
	w.stride = 74.0 if str(names[row]) == "kid" else (80.0 if str(names[row]) == "cane_old" else 108.0)
	w.position = Vector2(-80.0 if left else float(scene.get("width", 4000)) + 80.0, float(floors[-1]) + (-6.0 if back else 3.0))
	add_child(w)
	w.setup(_walk_tex, row, names.size(), float(_index.scale), Vector2(_index.foot[0], _index.foot[1]))
	if back:
		w.scale = Vector2.ONE  # 像素画不缩放（缩 0.9 点会糊、大小不匀）：远近只靠站位和淡一点
		w.modulate = Color(1.0, 1.0, 1.0, 0.82)
	_walkers.append(w)


## 主角（本地玩家）在哪：街坊搭腔看这个
func me_pos() -> Variant:
	if world == null or world.me() == null:
		return null
	return world.me().position


## ------------------------------------------------------------------
## 一位街坊：干一阵、歇一阵；你走近了转过来搭一句
## ------------------------------------------------------------------
class Folk extends Node2D:
	var id := ""
	var scene_id := ""
	var display_name := ""
	var lines: Dictionary = {}
	var bubbles: Array = []
	var host: Node = null
	var _sprite: Sprite2D
	var _over: Node2D
	var _lift := 0.0  ## 旁边的主角头顶正写着"在做什么"：搭的话往上让一行
	var _row := 0
	var _working := true
	var _left := 0.0
	var _t := 0.0
	var _phase := 0.0
	var _bub := ""
	var _bub_t := 0.0
	var _bub_wait := 0.0
	var _say := ""
	var _say_t := 0.0
	var _cool := 0.0
	var _flip := false
	var _give_side := 0.0  ## 往哪边让（-1 左 / 1 右 / 0 没让）：定下来就不变，不会人一过中线就从这边滑到那边
	var _settle := 0.0     ## 主角在跟前停了多久
	var _away := 99.0      ## 主角走开多久了
	var _step := 0.0

	func setup(tex: Texture2D, row: int, rows: int, art_scale: float, foot: Vector2) -> void:
		_row = row
		_sprite = Sprite2D.new()
		_sprite.texture = tex
		_sprite.centered = false
		_sprite.hframes = 8
		_sprite.vframes = maxi(rows, 1)
		_sprite.scale = Vector2.ONE / art_scale
		_sprite.offset = -foot * art_scale
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
		_over = Overlay.new(_draw_over)
		add_child(_over)
		# 每人起步的节拍错开，不会一条街齐刷刷一起动
		_phase = randf() * 4.0
		_left = randf_range(2.0, 7.0)
		_flip = randf() < 0.35
		_bub_wait = randf_range(2.0, 6.0)

	func _process(delta: float) -> void:
		_t += delta
		_left -= delta
		_cool -= delta
		if _left <= 0.0:
			_working = not _working
			_left = randf_range(5.0, 9.0) if _working else randf_range(2.0, 4.0)
		# 你走近了：转过脸来，说一句
		var me: Variant = host.me_pos() if host != null else null
		var now := Time.get_ticks_msec() / 1000.0
		if me != null and _cool <= 0.0 and now > float(host.talk_until) and absf((me as Vector2).y - position.y) < 60.0 and absf((me as Vector2).x - position.x) < TALK_DIST:
			var said := _pick_line()
			if said != "":
				_say = said
				_say_t = 0.0
				_cool = TALK_COOLDOWN
				host.talk_until = now + 3.8
				_flip = (me as Vector2).x < position.x
				_bub = ""
		if _say != "":
			_say_t += delta
			if _say_t > 3.6:
				_say = ""
		# 干活时偶尔冒个泡
		_bub_t += delta
		_bub_wait -= delta
		if _working and _say == "" and _bub_wait <= 0.0 and not bubbles.is_empty():
			_bub = str(bubbles[randi() % bubbles.size()])
			_bub_t = 0.0
			_bub_wait = randf_range(5.0, 9.0)
		# 主角在跟前停下来做事（同一个点位，比如在小卖部柜台帮忙）：街坊等一会儿，再往旁边挪一步，别叠成一团。
		# 只是走过：谁也不让，前后错身过去（y_sort）。往哪边让定下来就不变，人走了等一下再踱回原处。
		var occupied := false
		var occ_x := 0.0
		var lift := 0.0
		if host != null and host.world != null:
			for a in host.world.actors.values():
				if not a.visible or absf(a.position.y - position.y) >= 60.0:
					continue
				var settled: bool = not a.walking and (str(a.action_label) != "" or a.asleep)
				if settled and absf(a.position.x - position.x) < GIVE_NEAR:
					occupied = true
					occ_x = a.position.x
				if absf(a.position.x - position.x) < 320.0 and (str(a.action_label) != "" or a.asleep):
					lift = 58.0
		_lift = lerpf(_lift, lift, minf(1.0, delta * 6.0))
		_settle = _settle + delta if occupied else 0.0
		_away = 0.0 if occupied else _away + delta
		if occupied and _settle > GIVE_WAIT and _give_side == 0.0:
			# 人在我左边（或正当中）就往右让，反之往左
			_give_side = 1.0 if occ_x <= position.x else -1.0
		var target := _give_side * GIVE_STEP if (occupied or _away < BACK_WAIT) else 0.0
		var before := _sprite.position.x
		_sprite.position.x = move_toward(before, target, GIVE_SPEED * delta)
		var moving := absf(_sprite.position.x - before) > 0.01
		if moving:
			# 挪步：小步颠两下，脸朝着走的方向
			_step += delta
			_sprite.position.y = -absf(sin(_step * TAU * 1.6)) * 3.0
			_flip = _sprite.position.x < before
		else:
			_step = 0.0
			_sprite.position.y = 0.0
			if _give_side != 0.0 and is_zero_approx(_sprite.position.x):
				_give_side = 0.0
			elif occupied and _give_side != 0.0:
				_flip = occ_x < position.x + _sprite.position.x  # 让到了：回过脸看着你干
		var fps := 4.0 if _working else 2.0
		var k := int(_t * fps + _phase) % 4
		_sprite.frame = _row * 8 + (k if _working else 4 + k)
		_sprite.flip_h = _flip
		queue_redraw()
		_over.queue_redraw()

	func _pick_line() -> String:
		var host_stage: String = host.stage if host != null else "childhood"
		var pool: Variant = lines.get(host_stage, lines.get("default", []))
		if not pool is Array or (pool as Array).is_empty():
			return ""
		return str(pool[randi() % pool.size()])

	func _draw() -> void:
		draw_set_transform(Vector2(3 + _sprite.position.x, 2), 0.0, Vector2(1.0, 0.34))
		draw_circle(Vector2.ZERO, 28.0, Color(P.INK, 0.13))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## 搭的话和气泡：画在 overlay.gd 那层（z 71），不被夜色和光与空气压灰
	func _draw_over(cv: CanvasItem) -> void:
		var night: float = host.night if host != null else 0.0
		if _say != "":
			cv.draw_set_transform(Vector2(_sprite.position.x * 1.6, 0.0))
			_draw_say(cv, night)
			cv.draw_set_transform(Vector2.ZERO)
		elif _bub != "" and _bub_t < 1.8:
			Bubble.draw(cv, _bub, Vector2(_sprite.position.x + (-30.0 if _flip else 30.0), -196.0), 17.0, P.INK_SOFT, _bub_t, 1.8, 1.0 if _flip else -1.0)

	## 搭的那句话：一条纸片，上头一行小字写是谁
	func _draw_say(cv: CanvasItem, night: float) -> void:
		var f := P.font()
		var a := clampf(_say_t / 0.2, 0.0, 1.0) * clampf((3.6 - _say_t) / 0.4, 0.0, 1.0)
		var dim := 1.0 - 0.25 * night
		var w := f.get_string_size(_say, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var r := Rect2(-w / 2.0 - 12.0, -238.0 - _lift - (1.0 - a) * 8.0, w + 24.0, 40.0)
		cv.draw_rect(Rect2(r.position + Vector2(4, 4), r.size), Color(P.INK_SOFT, 0.5 * a))
		cv.draw_rect(r, Color(P.PAPER * dim, 0.96 * a))
		cv.draw_rect(r, Color(P.INK, 0.8 * a), false, 1.5)
		var tail := PackedVector2Array([Vector2(-8, r.end.y), Vector2(8, r.end.y), Vector2(0, r.end.y + 12)])
		cv.draw_colored_polygon(tail, Color(P.PAPER * dim, 0.96 * a))
		cv.draw_polyline(PackedVector2Array([tail[0], tail[2], tail[1]]), Color(P.INK, 0.8 * a), 1.5)
		cv.draw_string(f, Vector2(-w / 2.0, r.position.y + 28.0), _say, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(P.INK, a))
		var nw := f.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		cv.draw_string(f, Vector2(-nw / 2.0, r.position.y - 6.0), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(P.INK_SOFT, a))


## ------------------------------------------------------------------
## 一个路人：从图的一头走到另一头，按走过的距离翻帧
## ------------------------------------------------------------------
class Walker extends Node2D:
	var speed := 80.0
	var stride := 108.0
	var _sprite: Sprite2D
	var _row := 0
	var _phase := 0.0
	var _pause := 0.0
	var _next_pause := 0.0

	func setup(tex: Texture2D, row: int, rows: int, art_scale: float, foot: Vector2) -> void:
		_row = row
		_sprite = Sprite2D.new()
		_sprite.texture = tex
		_sprite.centered = false
		_sprite.hframes = 8
		_sprite.vframes = maxi(rows, 1)
		_sprite.scale = Vector2.ONE / art_scale
		_sprite.offset = -foot * art_scale
		_sprite.flip_h = speed < 0.0
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
		_next_pause = randf_range(8.0, 20.0)

	func _process(delta: float) -> void:
		# 偶尔站住歇一下脚（看看橱窗、回个头）
		_next_pause -= delta
		if _next_pause <= 0.0:
			_next_pause = randf_range(10.0, 24.0)
			_pause = randf_range(0.8, 2.0)
		if _pause > 0.0:
			_pause -= delta
			_sprite.frame = _row * 8 + 2
			return
		position.x += speed * delta
		_phase += absf(speed) * delta / stride * 8.0
		_sprite.frame = _row * 8 + int(_phase) % 8
		queue_redraw()

	func _draw() -> void:
		draw_set_transform(Vector2(3, 2), 0.0, Vector2(1.0, 0.34))
		draw_circle(Vector2.ZERO, 24.0, Color(P.INK, 0.11))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
