extends CanvasLayer
## 开局引导和主线的路标（第一个钟头的手感）。不碰服务器，只看 main 手里已经有的东西：
##   1. 章首卡：进了新的一章，整版墨盖下来写「第几章 · 章名」和章首那一句，底下七个点是走到第几章了。
##      和「长大了」那张卡撞在同一天（12、18、30、60 岁）就并成一张（fx.card_hook）。
##   2. 主线路标：纸带上的「下一件事」在别的图上，就在去那儿的第一个出口上套一圈墨色的波纹，
##      出口不在画面里就贴着屏幕边一个「主」字的箭头。到了那张图、还没到那一段，脚下写一句「到了傍晚就在这儿」。
##   3. 小纸条：头一世的头几天，碰到第一次的事（第一次能定、第一次等 TA、第一次搭伴、第一次过完一天、第一道关口……）
##      贴一张小纸条说一句怎么玩。每条只出一次，记在 user://guide.cfg，点一下或者过几秒就收。
##   4. 过完一件主线，提示条写下一件在哪儿。
## main.gd 只挂两处：_build_layers 里 new 一个，_enter_world 里 enter()。

const P := preload("res://scripts/ui/palette.gd")
const Kit := preload("res://scripts/ui/kit.gd")
const SAVE := "user://guide.cfg"
const SLOT_IDS := ["morning", "am", "pm", "evening", "night"]
const SLOT_NAME := ["早上", "上午", "下午", "傍晚", "晚上"]
const CHAPTER_NUM := ["", "一", "二", "三", "四", "五", "六", "七"]
## 每一章两个人大概隔多远（章首卡上两个圆的间距，按半径算）：一起长大挨着，第四章各奔东西分得最开，老了又挨上
const CHAPTER_PAIR := [0.9, 0.7, 1.25, 2.5, 1.6, 1.2, 0.5]
const TIP_SECONDS := 9.0
const TIP_GAP := 2.5  ## 两张纸条之间至少隔这么久

## 小纸条：id → [字, 贴在哪儿]。贴在哪儿：walk 地面中间 / act 行动按钮上头 / story 主线小签底下 / partner 对门的牌底下 / top 顶上正中
const TIPS := {
	"walk": ["点地面，人就走过去。走到亮着的圆点跟前，右下角的按钮写着在这儿能做什么。", "walk"],
	"story": ["这张小签是主线：第几章，下一件事在哪儿、哪一段。到点走过去就会遇上，出口上套着圈的就是去那儿的路。", "story"],
	"slot": ["按一下做一回：写作业就是一个半钟头，钟往前拨，当场看得到长了什么、累了多少。这一段的时间用完，或者按「就这么过」，就等 TA。吃饭、洗澡不占时间。", "act"],
	"wait": ["定下了。两个人都定了，这一段才过去。右上角是对门的牌：TA 在哪儿、定没定。", "partner"],
	"together": ["和 TA 在一块儿做同一件事就是搭伴：长得快一半，两个人也更近。", "act"],
	"gate": ["这是一道关口。选的路管接下来几年。和 TA 选了同一条，两条线就并在一起。", "modal"],
	"need": ["圆表红了：饿了回家吃饭，脏了去洗，累了就早点睡。不管它，做什么都事倍功半。", "top"],
	"night": ["晚上了。回家上床睡下，这一天就到头了。", "act"],
	"day": ["这一天过去了。这辈子只过被记住的日子：小时候一年四天，上了中学一年两天，长大了一年一天，再往后三年一天。", "top"],
	"goal": ["最上面那条是下一道关口：还有几个日子、分数线在哪。平时做的事都在往上攒。", "goal"],
}

var main  ## main.gd（单测里是个只带 content 的假的）
var _done: Dictionary = {}
var _first_life := true
var _tip: PanelContainer
var _tip_label: Label
var _tip_id := ""
var _tip_t := 0.0
var _since_tip := 99.0
var _seen_chapter := -1
var _card_chapter := -1  ## 章首卡已经和「长大了」并成一张的那一章
var _last_next := ""
var _last_turn := -1
var _marks: Control
var _route_exit: Dictionary = {}  ## 主线路标指着的出口
var _route_key := ""
var _route_cache: Dictionary = {}
var _target: Dictionary = {}      ## 今天主线在哪 { scene, slot, next }
var _t := 0.0


func _ready() -> void:
	layer = 4  # 界面（1）上面、小游戏和音量按钮（5）下面
	var cfg := ConfigFile.new()
	if cfg.load(SAVE) == OK:
		for k in cfg.get_section_keys("tips") if cfg.has_section("tips") else []:
			_done[k] = true
	# 自己是一层 CanvasLayer，拿不到 main.ui 的主题（字体）：挂一个带主题的根
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = main.ui.theme if main != null and main.ui != null else Kit.theme()
	add_child(root)
	_marks = Control.new()
	_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	root.add_child(_marks)
	_tip = Kit.card(P.INK, 24.0, false, 6.0)
	_tip.mouse_filter = Control.MOUSE_FILTER_STOP
	_tip.modulate.a = 0.0
	_tip.visible = false
	_tip.custom_minimum_size = Vector2(560, 0)
	_tip.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			_hide_tip())
	root.add_child(_tip)
	_tip_label = Kit.label(_tip, "", 30, P.INK)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(520, 0)


## 进河畔里（新的一世或者重连）。头一世的第一天才出小纸条；第二世起就不讲了
func enter() -> void:
	var life: Dictionary = main.life
	_first_life = int(life.get("life", 1)) <= 1
	_last_turn = int(life.get("turn", 0))
	_last_next = ""
	var ch := chapter_at(LifeTimeAge.age(_last_turn))
	# 头一天进来：第一章的章首卡。重连回来不再放
	if _last_turn == 0 and _seen_chapter != ch and ch > 0:
		_seen_chapter = ch
		_chapter_card(ch, "")
	else:
		_seen_chapter = ch


# ---------- 章 ----------

func chapters() -> Array:
	var st: Variant = main.content.get("story")
	return st.get("chapters", []) if st is Dictionary else []


func chapter_at(age: int) -> int:
	var list := chapters()
	for i in list.size():
		var a: Array = list[i].get("ages", [0, 0])
		if age >= int(a[0]) and age <= int(a[1]):
			return i + 1
	return 0


## fx.stage_card 盖下来的时候问一句：这一天是不是也进了新的一章。是的话卡上多两行，就不再单放章首卡了
func card_lines() -> Array:
	if main == null or main.life.is_empty():
		return []
	var ch := chapter_at(LifeTimeAge.age(int(main.life.get("turn", 0))))
	if ch <= 0 or ch == _seen_chapter:
		return []
	_seen_chapter = ch
	_card_chapter = ch
	var c: Dictionary = chapters()[ch - 1]
	var out: Array = [["第%s章 · %s" % [CHAPTER_NUM[ch] if ch < CHAPTER_NUM.size() else str(ch), str(c.get("title", ""))], 56, P.PAPER], [str(c.get("intro", "")), 34, Color(P.PAPER, 0.8)]]
	var less := chapter_more(ch)
	if less != "":
		out.append([less, 26, Color(P.PAPER, 0.6)])
	out.append([_dots(ch), 34, Color(P.PAPER, 0.7)])
	return out


## 章首卡底下那行小字：这一章新开的图、这一章走到哪道关（story.yaml 的 opens / closes）
func chapter_more(ch: int) -> String:
	var c: Dictionary = chapters()[ch - 1]
	var map: Dictionary = main.content.get("map", {})
	var names: Array = []
	for id in c.get("opens", []):
		for sc in map.get("scenes", []):
			if str(sc.id) == str(id):
				names.append(str(sc.name))
	var gates: Array = []
	for id in c.get("closes", []):
		for e in main.content.get("events", []):
			if str(e.id) == str(id):
				gates.append("%d 岁%s" % [int(e.get("age", 0)), str(e.get("title", ""))])
	var parts: Array = []
	if not names.is_empty():
		parts.append("新去处　" + "　".join(names))
	if not gates.is_empty():
		parts.append("这一章到　" + "　".join(gates))
	return "　·　".join(parts)


func _dots(ch: int) -> String:
	var s := ""
	for i in chapters().size():
		s += ("●" if i < ch else "○") + (" " if i < chapters().size() - 1 else "")
	return s


func _chapter_card(ch: int, small: String) -> void:
	var c: Dictionary = chapters()[ch - 1]
	var num := "第%s章" % (CHAPTER_NUM[ch] if ch < CHAPTER_NUM.size() else str(ch))
	main.fx.chapter_card(num, str(c.get("title", "")), str(c.get("intro", "")), _dots(ch), small, CHAPTER_PAIR[ch - 1] if ch <= CHAPTER_PAIR.size() else -1.0, chapter_more(ch))


# ---------- 每帧 ----------

func _process(delta: float) -> void:
	_t += delta
	_since_tip += delta
	if _tip.visible:
		# 弹窗（事件、关口）压上来时纸条先让开、计时停住，弹窗关了再接着显示：不然纸条正好盖在事件的字上
		var covered: bool = main != null and main.modal.visible and str(TIPS[_tip_id][1]) != "modal"
		if covered:
			_tip.modulate.a = 0.0
		else:
			_tip.modulate.a = minf(1.0, _tip.modulate.a + delta * 4.0)
			_tip_t += delta
		if _tip_t > TIP_SECONDS:
			_hide_tip()
		else:
			_place_tip()
	var world = main.world if main != null else null
	if world == null or main.offline_preview or main.screen.visible:
		_route_exit = {}
		_target = {}
		_marks.queue_redraw()
		if world == null:
			_hide_tip()
		return
	var w: Dictionary = main.last_world
	var turn := int(main.life.get("turn", 0))
	# 换了一天
	if turn != _last_turn:
		if _last_turn >= 0 and turn == _last_turn + 1:
			want("day")
		_last_turn = turn
	# 进了新的一章（没和「长大了」并成一张的：6 岁、45 岁）
	var ch := chapter_at(LifeTimeAge.age(turn))
	if ch > 0 and ch != _seen_chapter and not main.fx.is_busy():
		_seen_chapter = ch
		_chapter_card(ch, "%d 岁" % LifeTimeAge.age(turn))
	_follow_story(world, w)
	_first_times(world, w)
	_marks.queue_redraw()


## 纸带上的下一件事：在哪张图、哪一段。服务器只给那一句话，按章和那句话在剧本里找回来
func _follow_story(world, w: Dictionary) -> void:
	var st: Dictionary = w.get("story") if w.get("story") is Dictionary else {}
	var next: Variant = (st.get("next", {}) as Dictionary).get(main.my_role) if st.get("next") is Dictionary else null
	var text := str(next) if next is String else ""
	if text != _last_next:
		if _last_next != "" and text != "" and not main.modal.visible:
			main._toast("主线 · 下一件事：" + text)
		_last_next = text
	_target = {}
	_route_exit = {}
	if text == "":
		return
	var story: Variant = main.content.get("story")
	for ev in (story.get("events", []) if story is Dictionary else []):
		if int(ev.get("chapter", 0)) == int(st.get("chapter", 0)) and str(ev.get("next", "")) == text:
			_target = {"scene": str(ev.get("scene", "")), "slot": SLOT_IDS.find(str(ev.get("slot", ""))), "next": text}
			break
	if _target.is_empty():
		return
	var me = world.me()
	if me == null or not me.visible:
		return
	var here := str(world.scene.get("id", ""))
	if here != _target.scene:
		# 找路不每帧跑：换了目标、换了一层，或者横着走出去一截才重找
		var key := "%s|%d|%d" % [_target.scene, int(me.position.y), int(me.position.x / 60.0)]
		if key != _route_key:
			_route_key = key
			_route_cache = route(main.content.get("map", {}), me.position, _target.scene)
		_route_exit = _route_cache


## 从这儿去那张图要先走哪个出口（出口连成的图上找横着走得最少的路；走出口不算路）
static func route(map: Dictionary, from: Vector2, scene_id: String) -> Dictionary:
	var exits: Array = map.get("exits", [])
	var best := {}
	var dist := {}
	var first := {}
	var todo: Array = [[from.x, from.y]]
	var key0 := "%d,%d" % [int(from.x), int(from.y)]
	dist[key0] = 0.0
	first[key0] = {}
	var done := {}
	var best_d := INF
	var stride := float(map.get("stride", 2000))
	var scene_index := {}
	for sc in map.get("scenes", []):
		scene_index[int(sc.index)] = str(sc.id)
	while not todo.is_empty():
		var bi := 0
		for i in todo.size():
			if float(dist["%d,%d" % [int(todo[i][0]), int(todo[i][1])]]) < float(dist["%d,%d" % [int(todo[bi][0]), int(todo[bi][1])]]):
				bi = i
		var cur: Array = todo[bi]
		todo.remove_at(bi)
		var key := "%d,%d" % [int(cur[0]), int(cur[1])]
		if done.has(key):
			continue
		done[key] = true
		var d0: float = dist[key]
		if str(scene_index.get(int(floor(float(cur[1]) / stride)), "")) == scene_id:
			if d0 < best_d:
				best_d = d0
				best = first[key]
			continue
		for ex in exits:
			if absf(float(ex.at[1]) - float(cur[1])) > 1.0:
				continue
			var nk := "%d,%d" % [int(ex.arrive[0]), int(ex.arrive[1])]
			var nd := d0 + absf(float(cur[0]) - float(ex.at[0])) + 40.0
			if not dist.has(nk) or nd < float(dist[nk]):
				dist[nk] = nd
				first[nk] = first[key] if not (first[key] as Dictionary).is_empty() else ex
				todo.append([float(ex.arrive[0]), float(ex.arrive[1])])
	return best


# ---------- 第一次 ----------

func _first_times(world, w: Dictionary) -> void:
	if not _first_life or main.fx.is_busy():
		return
	if main.modal.visible:
		# 第一道关口（六岁上学那天）：这个选择的分量要说一句
		var ev: Dictionary = main.events_by_id.get(str(main.modal.get_meta("waiting_event", "")), {})
		if str(ev.get("kind", "")) == "milestone":
			want("gate")
		return
	var me = world.me()
	if me == null or not me.visible:
		return
	var state: String = main._slot_state()
	if state == "open":
		want("walk")
		if w.get("story") is Dictionary and not (w.story as Dictionary).is_empty() and _done.has("walk"):
			want("story")
		if _done.has("story"):
			want("slot")
		if int(w.get("slot", 0)) == 4:
			want("night")
		var needs: Dictionary = (w.get("needs", {}) as Dictionary).get(main.my_role, {}) if w.get("needs") is Dictionary else {}
		for k in needs:
			if float(needs[k]) < 30.0:
				want("need")
		var sp: Dictionary = world.nearest_spot()
		if not sp.is_empty() and world.partner_doing(sp, world.action_of(sp)):
			want("together")
		if int(main.life.get("turn", 0)) >= 1 and main.goal_panel.visible:
			want("goal")
	elif state == "decided" and not main._ready_of(main._other()):
		want("wait")


## 想出这张纸条：没出过、眼下没有别的纸条、离上一张够久
func want(id: String) -> void:
	if _done.has(id) or _tip.visible or _since_tip < TIP_GAP or not _first_life:
		return
	if not TIPS.has(id):
		return
	_done[id] = true
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	cfg.set_value("tips", id, true)
	cfg.save(SAVE)
	_tip_id = id
	_tip_label.text = str(TIPS[id][0])
	_tip.visible = true
	_tip_t = 0.0
	_tip.modulate.a = 0.0  # _process 里淡入（被弹窗压着时不显示）
	_tip.reset_size()
	_place_tip()


func _hide_tip() -> void:
	if not _tip.visible:
		return
	_tip.visible = false
	_tip.modulate.a = 0.0
	_since_tip = 0.0


func _place_tip() -> void:
	var view: Vector2 = main.ui.size
	# 头一回排版时字还没量宽，卡片会被撑得很高，而且 PanelContainer 不会自己缩回去：每帧按最小尺寸重设
	var sz := _tip.get_combined_minimum_size()
	if _tip.size != sz:
		_tip.size = sz
	var at := Vector2((view.x - sz.x) / 2.0, view.y * 0.42)
	match str(TIPS[_tip_id][1]):
		"act":
			var b: Control = main.action_btn
			at = Vector2(view.x - sz.x - 40.0 - main.hud.inset.y, b.global_position.y - sz.y - 30.0)
		"story":
			var r: Rect2 = main.hud.story_rect
			at = Vector2(clampf(r.position.x, 40.0, view.x - sz.x - 40.0), r.end.y + 26.0)
		"partner":
			at = Vector2(view.x - sz.x - 40.0 - main.hud.inset.y, 300.0)
		"goal":
			var g: Rect2 = main.hud.strip_rect()
			at = Vector2(clampf(g.get_center().x - sz.x / 2.0, 40.0, view.x - sz.x - 40.0), g.end.y + 80.0)
		"top":
			at = Vector2((view.x - sz.x) / 2.0, 300.0)
		"modal":
			at = Vector2((view.x - sz.x) / 2.0, 24.0)
	_tip.position = at.round()
	_tip.rotation = -0.01


# ---------- 画：主线的路标 ----------

func _draw_marks() -> void:
	var world = main.world if main != null else null
	if world == null or _target.is_empty() or main.modal.visible or main.screen.visible:
		return
	var f := P.font()
	var xf: Transform2D = world.get_canvas_transform()
	var view := Rect2(Vector2.ZERO, main.ui.size)
	var k := fmod(_t / 1.4, 1.0)
	if not _route_exit.is_empty():
		var at: Vector2 = xf * Vector2(float(_route_exit.at[0]), float(_route_exit.at[1]) - 210.0)
		if view.grow(-60.0).has_point(at):
			# 出口牌子上一圈墨色的波纹，牌子上头一张小签「主线 · 往这儿」
			var zoom := xf.get_scale().x
			var box := Rect2(at - Vector2(90, 26) * zoom, Vector2(180, 52) * zoom)
			_marks.draw_rect(box.grow(6.0 + k * 26.0), Color(P.INK, 0.85 * (1.0 - k)), false, 4.0)
			_tag(f, at + Vector2(0, -56.0 * zoom), "主线 · 往这儿")
		else:
			_edge_arrow(f, view, at)
	elif world.slot != int(_target.get("slot", -1)) and int(_target.get("slot", -1)) >= 0:
		# 到了那张图，还没到那一段：脚下写一句
		var me = world.me()
		if me != null and me.visible:
			var at: Vector2 = xf * (me.position + Vector2(0, 40))
			_tag(f, at, "到了%s就在这儿" % SLOT_NAME[int(_target.slot)])


func _tag(f: Font, center: Vector2, text: String) -> void:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var r := Rect2(center - Vector2(w / 2.0 + 14.0, 18.0), Vector2(w + 28.0, 38.0))
	_marks.draw_rect(Rect2(r.position + Vector2(4, 4), r.size), Color(P.INK, 0.3))
	_marks.draw_rect(r, P.INK)
	_marks.draw_string(f, r.position + Vector2(14, 28), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, P.PAPER)


## 出口不在画面里：贴着左右边一个墨色的圆，写个「主」，尖儿朝那边
func _edge_arrow(f: Font, view: Rect2, at: Vector2) -> void:
	var left := at.x < view.get_center().x
	var y := clampf(at.y, 360.0, view.size.y - 260.0)
	var c := Vector2(110.0 + main.hud.inset.x if left else view.size.x - 110.0 - main.hud.inset.y, y)
	var dir := Vector2(-1, 0) if left else Vector2(1, 0)
	var r := 30.0 + sin(_t * 2.4) * 1.5
	var tip := c + dir * (r + 22.0)
	var side := Vector2(0, 15)
	var base := c + dir * (r - 6.0)
	_marks.draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), P.INK)
	_marks.draw_circle(c, r, P.INK, true, -1.0, true)
	_marks.draw_arc(c, r, 0, TAU, 32, P.PAPER, 2.0, true)
	var w := f.get_string_size("主", HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	_marks.draw_string(f, c + Vector2(-w / 2.0, 11), "主", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, P.PAPER)


## 第几个日子是几岁（和 LifeTime.at 一样的表，这里只要岁数）
class LifeTimeAge:
	const LT := preload("res://scripts/ui/life_time.gd")

	static func age(turn: int) -> int:
		return int(LT.at(turn).age)
