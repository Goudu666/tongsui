extends Node2D
## 河畔里的一个孩子（会长大）。本地玩家沿寻路的路径走；对方按服务器广播插值。
## 外观是孔版套色的侧视精灵表 res://art/actors/{role}_{stage}.png（tools/art/actors.py 用骨架摆出来）：
##   8 列 × 3 行，每格 200×220 世界像素（贴图 2 倍），脚底在格子里的 (100, 206)，人朝右（朝左翻转）
##   行 0：走一整步 8 帧
##   行 1：0~3 站着喘气（3 眨眼），4~7 在忙
##   行 2：0~1 坐着，2~3 睡觉，4~7 挥手
##   行 3：0~3 高兴（蹦一下），4~7 泄气；行 4：0~3 击掌，4~7 不好意思（挠头）
## 每个行动还有一张专属动作表 {role}_{stage}_act.png（tools/art/actor_acts.py，1.5 倍）：
##   11 行 × 两套 4 帧循环，顺序见 ACT_LOOP；行动 id 怎么对到哪一套见 ACTION_LOOP / DUTY_LOOP
##   两个人一起踢球时不颠球、换成 pass：面对面对着踢一个球（球由 pass_lead 那个人画，钟是 pass_clock）
## 头顶的情绪气泡（bubble.gd）：做事时按这套动作冒（FAMILY_BUBBLES），做完一回按 did 的需求变化反应（react），
## 闲着按精力和心情冒（needs）；碰面招手、搭伴击掌由 world_view 叫
## 精灵按世界像素原大画：不管 world_view 把这个节点放大多少，人还是那么高（名字牌跟着节点放大）。
## 没有贴图时退回 M0 的墨线简笔。

const P := preload("res://scripts/ui/palette.gd")
const Bubble := preload("res://scripts/world/bubble.gd")
const Overlay := preload("res://scripts/world/overlay.gd")
const WALK_SPEED := 330.0  ## 略低于服务器限速
const CELL := Vector2(200, 220)
const FOOT := Vector2(100, 206)
const COLS := 8
const ROWS := 5
const ACT_ROWS := 11
const ACT_ART_SCALE := 1.5
## 每个年纪的身高（世界像素，梅比青矮 6）、走一整步前进多远
const HEIGHT := {"childhood": 112.0, "teen": 152.0, "young": 172.0, "middle": 170.0, "old": 160.0}
const STRIDE := {"childhood": 74.0, "teen": 104.0, "young": 120.0, "middle": 112.0, "old": 78.0}
const ART_SCALE := 2.0
const STAGES := ["childhood", "teen", "young", "middle", "old"]
const STAGE_FILE := {"childhood": "child", "teen": "teen", "young": "young", "middle": "middle", "old": "old"}
## 专属动作表里的顺序（和 tools/art/actor_acts.py 的 ACTS 一致：第 i 套在第 i/2 行、第 (i%2)×4 列起）
const ACT_LOOP := ["write", "read", "eat", "type", "kick", "hop", "fix", "carry", "cook", "fish",
	"chess", "talk", "sing", "piano", "kite", "gaze", "wash", "exercise", "chalk", "brush", "pass"]
## 两个人一起踢球：面对面对着踢一个球（world_view._pair_faces 配对）。一来一回 PASS_PERIOD 秒，两人按同一个钟走
const PASS_PERIOD := 1.9
## 行动 id（content/map.yaml）→ 哪一套动作。没写的：SIT_ACTIONS 坐着，WAVE_ACTIONS 招手，其余是通用的"在忙"
const ACTION_LOOP := {
	"study": "write", "club_math": "write", "tutor": "write", "lang_class": "write", "night_class": "write",
	"old_lessons": "write", "letter": "write",
	"picture_book": "read", "read": "read", "read_store": "read",
	"eat": "eat", "eat_out": "eat", "dine": "eat", "dine_west": "eat", "night_snack": "eat", "banquet": "eat",
	"overtime": "type",
	"ball": "kick", "club_sport": "kick",
	"play_alley": "hop",
	"work": "fix", "side_fix": "fix",
	"help_out": "carry", "night_shift": "carry",
	"cook": "cook", "night_market": "cook",
	"fish": "fish", "chess": "chess",
	"chat": "talk", "club_campus": "talk", "side_tutor": "talk",
	"perform": "sing", "choir": "sing", "broadcast": "sing", "club_art": "sing",
	"piano": "piano",
	"play_river": "kite", "play_roof": "kite",
	"walk_river": "gaze", "rail_talk": "gaze", "balcony": "gaze", "window_shop": "gaze",
	"wash": "wash", "factory_bath": "wash",
	"morning_walk": "exercise", "run_dawn": "exercise", "swim_class": "exercise",
	"blackboard": "chalk", "ground_write": "brush",
	# 点位菜单上后添的（PR #57）
	"pancake": "cook", "tea_runner": "carry", "mall_clerk": "talk", "river_run": "exercise", "laps": "exercise",
	"hopscotch": "hop", "sketch": "brush", "coal": "carry", "cards": "chess", "teach_chess": "chess",
	"flowers": "gaze", "boat": "gaze", "huqin": "sing",
	# 后半生押时间（content/events/later.yaml）
	"old_breakfast": "cook", "old_bikes": "fix", "mind_kids": "talk", "grandkid_park": "kite",
	"kid_homework": "write", "kid_run": "kick", "kid_listen": "talk", "kid_class": "read",
	"square_dance": "exercise", "pair_cook": "cook", "gk_pickup": "talk",
}
## 上学 / 上班（duty）按在哪个点上：坐办公桌敲电脑、修车铺修车、早点铺出摊…（没写的就招手进门）
const DUTY_LOOP := {
	"office_desk": "type", "bike_bench": "fix", "breakfast_stall": "cook", "class_desk": "write",
	"middle_desk": "write", "away_work": "carry", "river_bridge": "carry", "uni_gate": "read",
}
const SIT_ACTIONS := ["listen", "accompany", "tea_box"]
const WAVE_ACTIONS := ["knock"]
## 两个人一起做这几样时面对面（world_view 把两人错开得远一点）
const FACE_LOOPS := ["talk", "chess", "eat", "gaze"]
## 做事时头顶冒什么（第一个先冒，之后随机）
const FAMILY_BUBBLES := {
	"write": ["dots", "bulb"], "read": ["dots", "spark"], "eat": ["steam", "heart"], "type": ["dots", "sweat"],
	"kick": ["note", "spark"], "hop": ["note", "spark"], "fix": ["sweat", "spark"], "carry": ["sweat", "sweat"],
	"cook": ["steam", "heart"], "fish": ["dots", "bang"], "chess": ["ask", "bulb"], "talk": ["dots", "note"],
	"sing": ["note", "note"], "piano": ["note", "spark"], "kite": ["note", "spark"], "gaze": ["dots", "heart"],
	"wash": ["spark", "note"], "exercise": ["sweat", "note"], "chalk": ["dots", "spark"], "brush": ["dots", "spark"],
	"sit": ["dots", "heart"], "busy": ["dots", "sweat"], "wave": ["bang", "note"],
}
## 情绪动作在基础表里的位置 [行, 起始列]
const EMOTE_CELL := {"joy": [3, 0], "sad": [3, 4], "five": [4, 0], "shy": [4, 4], "wave": [2, 4]}

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
var needs: Dictionary = {}       ## 我的饱腹 / 精力 / 心情 / 清洁（world_view 从 WORLD.needs 喂；闲着时冒气泡用）
var face_to := 0                 ## 0 按走的方向；2 朝右 3 朝左（搭伴面对面、碰面招手时 world_view 设）
var quiet_label := false         ## 搭伴挨着做同一件事：「一起……中」只让一个人写（world_view 设）
var tag_dx := 0.0                ## 两人挨得太近时名字牌往两边让一让（画布坐标）
var label_dx := 0.0              ## 「一起……中」挪到两人中间写
var label_dy := 0.0              ## 两人挨着各做各的：一个人的那行字抬高一行，不叠在一起
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
var _over: Node2D  ## 字和气泡那层（overlay.gd，z 71）
var _ball: Node2D  ## 对着踢的那个球（领头的那个人画）
var _ball_on := false  ## 上一帧画没画球
var _last_pos := Vector2.ZERO
var _base_tex: Texture2D
var _act_tex: Texture2D
var _on_act := false     ## 现在贴的是专属动作表
var pass_with: Node2D = null  ## 对着踢球的那个人（不是 null 时，"kick" 换成 "pass"）
var pass_lead := false        ## 球由我来画、钟由我来走（两人里只一个）
static var pass_clock := 0.0  ## 对着踢的钟：游戏时间（不用墙上的钟：卡顿、录屏时两人和球都还对得上）
var _loop := ""          ## 现在演的是哪一套（ACT_LOOP 里的名字，或 sit / wave / busy）
var _loop_t := 0.0
var _emote := ""         ## 正在演的情绪动作（EMOTE_CELL）
var _emote_left := 0.0
var _bubbles: Array = [] ## [{kind, t, life}]，最多两个，后来的顶掉先来的
var _bubble_wait := 0.0  ## 下一个"做事气泡"还要等多久
var _idle_wait := 4.0    ## 下一个"闲着气泡"还要等多久


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
	_over = Overlay.new(_draw_over)
	add_child(_over)
	# 对着踢的那个球：比人高一层（压在两人脚上），但还在夜版底下
	_ball = Overlay.new(_draw_pass)
	_ball.z_as_relative = true
	_ball.z_index = 1
	add_child(_ball)
	set_stage(stage)


## 按人生阶段换外观（LifeTime.at(turn).stage）
func set_stage(p_stage: String) -> void:
	stage = p_stage if p_stage in STAGES else "childhood"
	if _sprite == null:
		return
	var path := "res://art/actors/%s_%s.png" % [role, STAGE_FILE[stage]]
	_base_tex = load(path) if ResourceLoader.exists(path) else null
	var act_path := "res://art/actors/%s_%s_act.png" % [role, STAGE_FILE[stage]]
	_act_tex = load(act_path) if ResourceLoader.exists(act_path) else null
	_on_act = true  # 让 _use_sheet 一定换一次
	_use_sheet(false)
	_sprite.visible = _base_tex != null


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
	_loop_t += delta
	_tick_moods(delta)
	# 精灵按世界原大：抵消掉节点自己的放大
	var art := ACT_ART_SCALE if _on_act else ART_SCALE
	if _sprite != null and not is_equal_approx(_sprite.scale.x * scale.x, 1.0 / art):
		_sprite.scale = Vector2.ONE / (art * maxf(scale.x, 0.01))
	if pass_lead and _loop == "pass":
		pass_clock += delta
	_update_frame()
	queue_redraw()
	if _over != null:
		_over.queue_redraw()
	# 球那层：对着踢时每帧重画；刚解对那一帧也再画一次，把上一帧留下的球擦掉
	var ball_on := pass_lead and _loop == "pass"
	if _ball != null and (ball_on or _ball_on):
		_ball.queue_redraw()
	_ball_on = ball_on


## 贴哪张表：基础表（走、站、坐、睡、招手、情绪）还是专属动作表
func _use_sheet(act: bool) -> void:
	if _sprite == null:
		return
	act = act and _act_tex != null
	if act == _on_act and _sprite.texture != null:
		return
	_on_act = act
	_sprite.texture = _act_tex if act else _base_tex
	_sprite.vframes = ACT_ROWS if act else ROWS
	var art := ACT_ART_SCALE if act else ART_SCALE
	_sprite.offset = -FOOT * art
	_sprite.scale = Vector2.ONE / (art * maxf(scale.x, 0.01))


## 正在做的这件事演哪一套："" 没在做；ACT_LOOP 里的名字；或 sit / wave / busy
func loop_name() -> String:
	var lp := base_loop()
	return "pass" if lp == "kick" and pass_with != null else lp


## 不看搭伴、光按在做什么挑的那一套
func base_loop() -> String:
	if asleep or action_label == "":
		return ""
	if doing == "duty":
		return str(DUTY_LOOP.get(at_spot, "wave"))
	if ACTION_LOOP.has(doing):
		return str(ACTION_LOOP[doing])
	if doing in SIT_ACTIONS:
		return "sit"
	if doing in WAVE_ACTIONS:
		return "wave"
	return "busy"


## 演一个情绪动作（joy 高兴 / sad 泄气 / five 击掌 / shy 挠头 / wave 招手），走路和睡觉时不演
func play_emote(name: String, secs := 1.3) -> void:
	if not EMOTE_CELL.has(name):
		return
	_emote = name
	_emote_left = secs
	_idle = 0.0


## 头顶冒一个气泡（bubble.gd 的 kind）
func bubble(kind: String, life := 1.8) -> void:
	if kind == "pair" and quiet_label:
		return  # 两个人挨着：两个圆让另一个人冒一个就够了
	if not _bubbles.is_empty() and str(_bubbles[-1].kind) == kind and float(_bubbles[-1].t) < 0.6:
		return
	_bubbles.append({"kind": kind, "t": 0.0, "life": life})
	while _bubbles.size() > 2:
		_bubbles.pop_front()


## 刚当场做完一回（服务器的 did）：看需求和属性怎么变的，脸上、头顶给个反应
func react(did: Dictionary) -> void:
	var nd: Dictionary = did.get("nd", {}) if did.get("nd") is Dictionary else {}
	var mood := float(nd.get("mood", 0.0))
	var energy := float(nd.get("energy", 0.0))
	var st: Dictionary = did.get("s", {}) if did.get("s") is Dictionary else {}
	var grew := 0.0
	for k in st:
		grew += maxf(0.0, float(st[k]))
	if bool(did.get("tg", false)):
		bubble("pair", 2.0)
	elif mood <= -3.0:
		play_emote("sad", 1.4)
		bubble("cloud", 1.8)
	elif mood >= 4.0 or grew >= 1.5:
		play_emote("joy", 1.1)
		bubble("heart" if mood >= 4.0 else "spark", 1.6)
	elif energy <= -10.0:
		bubble("sweat", 1.6)
	else:
		bubble("spark", 1.3)


func _tick_moods(delta: float) -> void:
	for b in _bubbles:
		b.t = float(b.t) + delta
	_bubbles = _bubbles.filter(func(b): return float(b.t) < float(b.life))
	if _emote_left > 0.0:
		_emote_left -= delta
		if _emote_left <= 0.0:
			_emote = ""
			face_to = 0 if action_label == "" else face_to
	var lp := loop_name()
	if lp != _loop:
		_loop = lp
		_loop_t = 0.0
		_bubble_wait = 0.5
		if lp != "":
			_emote = ""
			_emote_left = 0.0
	if not visible:
		return
	if lp != "":
		_bubble_wait -= delta
		if _bubble_wait <= 0.0:
			var kinds: Array = FAMILY_BUBBLES.get(lp, ["dots"])
			var first := _loop_t < 1.0
			var kind: String = "pair" if together and (first or randf() < 0.35) else str(kinds[0] if first else kinds[randi() % kinds.size()])
			bubble(kind, 1.7)
			_bubble_wait = randf_range(3.2, 5.2)
		_idle_wait = randf_range(4.0, 7.0)
		return
	if asleep:
		return
	# 闲着：累了、心里不痛快就冒一下，偶尔还泄口气
	_idle_wait -= delta
	if _idle_wait > 0.0 or walking or _emote != "":
		return
	_idle_wait = randf_range(6.0, 10.0)
	var en := float(needs.get("energy", 60.0))
	var md := float(needs.get("mood", 60.0))
	var hu := float(needs.get("hunger", 60.0))
	if en < 22.0:
		bubble("zzz", 2.0)
		play_emote("sad", 1.2)
	elif md < 30.0:
		bubble("cloud", 2.0)
		play_emote("sad", 1.4)
	elif hu < 25.0:
		bubble("steam", 1.8)
	elif md > 78.0 and randf() < 0.5:
		bubble("note", 1.6)


func _update_frame() -> void:
	if _sprite == null or _base_tex == null:
		return
	var row := 1
	var col := 0
	var lp := _loop
	var dir := _dir
	if face_to != 0 and not walking:
		dir = face_to
	_sprite.flip_h = dir == 3
	if lp != "" and lp in ACT_LOOP and _act_tex != null:
		# 专属动作：一圈 4 帧，节奏按这套动作的性子（钓鱼慢、颠球快）
		_use_sheet(true)
		var i := ACT_LOOP.find(lp)
		if lp == "pass":
			# 对着踢：球到脚边那一下才出脚（按球走到哪挑帧，不按节拍轮播）
			var ph := _pass_phase()
			var c := 2 if ph < 0.1 else (3 if ph < 0.24 else (1 if ph > 0.84 else 0))
			_sprite.frame = (i / 2) * COLS + (i % 2) * 4 + c
			return
		var fps: float = {"fish": 2.2, "gaze": 1.8, "read": 1.6, "kick": 6.0, "hop": 6.5, "exercise": 2.6, "chess": 2.4, "piano": 6.0}.get(lp, 4.5)
		_sprite.frame = (i / 2) * COLS + (i % 2) * 4 + int(_loop_t * fps) % 4
		return
	_use_sheet(false)
	if asleep:
		row = 2
		col = 2 + int(_idle / 1.6) % 2
	elif lp == "sit":
		row = 2
		col = int(_idle / 0.7) % 2
	elif lp == "wave":
		row = 2
		col = 4 + int(_idle * 7.0) % 4
	elif lp != "":
		col = 4 + int(_idle * 5.0) % 4
	elif walking:
		row = 0
		col = int(_phase) % 8
	elif _emote != "":
		var cell: Array = EMOTE_CELL[_emote]
		row = int(cell[0])
		var fps2 := 7.0 if _emote == "wave" else 5.5
		var k := int((_idle) * fps2)
		# 高兴、击掌演一遍就停在最后一帧附近；泄气、挠头来回
		if _emote in ["joy", "five"]:
			k = mini(k, 3) if k < 8 else 3
		col = int(cell[1]) + k % 4
	else:
		# 站着：慢慢喘气，隔几秒眨一下眼
		var k := int(_idle * 2.2) % 4
		col = 3 if fmod(_idle + float(role.length()), 4.3) < 0.14 else (k if k < 3 else 1)
	_sprite.frame = row * COLS + col


## 对着踢这一圈走到哪了：0 = 正好轮到我出脚（领头的在 0，另一个差半圈）
func _pass_phase() -> float:
	var u := fmod(pass_clock / PASS_PERIOD, 1.0)
	return u if pass_lead else fmod(u + 0.5, 1.0)


## 两人中间那一个球：从出脚的人脚边滚到另一个人脚边，先弹两下再贴地滚，越滚越慢；转着
func _draw_pass(cv: CanvasItem) -> void:
	if not pass_lead or _loop != "pass" or _sprite == null or not _sprite.visible:
		return
	if pass_with == null or not is_instance_valid(pass_with) or not pass_with.visible:
		return
	var u := fmod(pass_clock / PASS_PERIOD, 1.0)
	var f := fmod(u * 2.0, 1.0)
	var mine := u < 0.5  # 前半圈从我脚下出去，后半圈从对面回来
	var k := 1.0 / maxf(scale.x, 0.01)
	var h := _height()
	var r := 8.5 * h / 170.0 + 1.5
	var reach := h * 0.2
	var me := Vector2(signf(pass_with.position.x - position.x) * reach, 0.0)
	var other := (pass_with.position - position) * k + Vector2(-signf(pass_with.position.x - position.x) * reach, 0.0)
	var a := me if mine else other
	var b := other if mine else me
	var e := 1.0 - pow(1.0 - f, 1.7)
	var x := lerpf(a.x, b.x, e)
	var hop := absf(sin(f * PI * 2.0)) * (1.0 - f) * h * 0.09
	var at := Vector2(x, lerpf(a.y, b.y, e) - r - hop)
	# 影子：球离地越高越小
	cv.draw_set_transform(Vector2(x, lerpf(a.y, b.y, e) + 1.0), 0.0, Vector2(1.0, 0.3))
	cv.draw_circle(Vector2.ZERO, r * (1.1 - hop / (h * 0.09 + 0.01) * 0.3), Color(P.INK, 0.2))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	cv.draw_circle(at, r, P.PAPER_HI)
	var spin := (x - a.x) / r * signf(b.x - a.x)
	var pent := PackedVector2Array()
	for i in 5:
		pent.append(at + Vector2.from_angle(spin + i * TAU / 5.0) * r * 0.4)
	cv.draw_colored_polygon(pent, P.INK)
	for i in 3:
		var d := Vector2.from_angle(spin + i * TAU / 3.0 + 0.6)
		cv.draw_line(at + d * r * 0.44, at + d * r * 0.92, P.INK, 1.0, true)
	cv.draw_arc(at, r, 0.0, TAU, 20, P.INK, 1.6, true)


func _draw() -> void:
	var c := P.role_color(role)
	# 脚下的影子（墨网点的感觉：半透明墨）
	var w := 26.0 if stage == "childhood" else 32.0
	draw_set_transform(Vector2(4, 2), 0.0, Vector2(1.0, 0.36))
	draw_circle(Vector2.ZERO, w, Color(P.INK, 0.16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _sprite == null or not _sprite.visible:
		_draw_fallback(c)


## 名字牌、"正在做什么"、气泡：画在 overlay.gd 那层（z 71），不被夜色和光与空气压灰
func _draw_over(cv: CanvasItem) -> void:
	if _sprite == null or not _sprite.visible:
		return
	var c := P.role_color(role)
	var head := -_height() / maxf(scale.x, 0.01) - 14.0
	_name_tag(cv, c)
	if asleep:
		_text(cv, "z z", Vector2(34, head + 30 + sin(_t * 2.0) * 6.0), 28, P.INK_SOFT)
	elif action_label != "" and not quiet_label:
		_text(cv, _doing_text(), Vector2(label_dx, label_dy + head - 8 + sin(_t * 3.0) * 3.0), 24, P.OVERLAP if together else Color(P.INK, 0.86), 6)
	_draw_bubbles(cv, head, c)


## 头顶的气泡：在脑袋斜上方、朝着脸的那边（"正在做什么"那行字的旁边，不压字）
func _draw_bubbles(cv: CanvasItem, head: float, c: Color) -> void:
	var side := 1.0 if (face_to if face_to != 0 and not walking else _dir) == 2 else -1.0
	var lift := (62.0 - label_dy) if action_label != "" and not quiet_label else 10.0
	for i in _bubbles.size():
		var b: Dictionary = _bubbles[i]
		var at := Vector2(side * (34.0 + i * 10.0), head - lift - i * 30.0)
		Bubble.draw(cv, str(b.kind), at, 22.0, c, float(b.t), float(b.life), -side)


func _doing_text() -> String:
	return ("一起" if together else "") + action_label + "中…"


## 脚下的名字：垫一小片纸，压在网点和砖缝上也看得清。自己的那片多一条色边
func _name_tag(cv: CanvasItem, c: Color) -> void:
	var f := P.font()
	var w := f.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var r := Rect2(-w / 2.0 - 9.0 + tag_dx, 12.0, w + 18.0, 30.0)
	if is_local:
		cv.draw_rect(Rect2(r.position + Vector2(3, 3), r.size), c)
	cv.draw_rect(r, Color(P.PAPER, 0.94))
	cv.draw_rect(r, Color(P.INK, 0.8), false, 1.5)
	cv.draw_string(f, Vector2(-w / 2.0 + tag_dx, 35.0), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, c)


## 精灵里的人有多高（世界像素）
func _height() -> float:
	return float(HEIGHT.get(stage, 160.0)) - (6.0 if role == "mei" else 0.0)


func _draw_fallback(c: Color) -> void:
	var bob := sin(_t * 12.0) * 4.0 if walking else 0.0
	if asleep:
		draw_circle(Vector2(0, -24), 26.0, Color(c, 0.85))
		draw_arc(Vector2(0, -24), 26.0, 0, TAU, 32, P.INK, 3.0)
		_text(self, "z z", Vector2(30, -64 + sin(_t * 2.0) * 6.0), 30, P.INK_SOFT)
		return
	var body := Rect2(Vector2(-20, -40 + bob), Vector2(40, 44))
	draw_rect(Rect2(body.position + Vector2(3, 2), body.size), Color(c, 0.9))
	draw_rect(body, P.INK, false, 3.0)
	draw_circle(Vector2(3, -64 + bob), 22.0, Color(c, 0.9))
	draw_arc(Vector2(0, -66 + bob), 22.0, 0, TAU, 32, P.INK, 3.0)
	draw_circle(Vector2(-7, -68 + bob), 2.5, P.INK)
	draw_circle(Vector2(7, -68 + bob), 2.5, P.INK)
	_text(self, display_name, Vector2(0, 36), 28, c)
	if action_label != "":
		_text(self, _doing_text(), Vector2(0, -104 + sin(_t * 3.0) * 3.0), 26, P.OVERLAP if together else P.INK_SOFT)


## rim > 0：字外面描一圈纸色（像印在一小条贴纸上），压在夜色、网点、光柱上都读得出
func _text(cv: CanvasItem, s: String, at: Vector2, size: int, color: Color, rim := 0) -> void:
	var f := P.font()
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if rim > 0:
		cv.draw_string_outline(f, at - Vector2(w / 2.0, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, rim, Color(P.PAPER_HI, 0.9))
	cv.draw_string(f, at - Vector2(w / 2.0, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
