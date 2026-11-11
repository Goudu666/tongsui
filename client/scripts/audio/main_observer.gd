extends Node
## 观察者：看着主场景（scripts/main.gd）和联机信号，把「发生了什么」翻译成声音导演的接口。
##
## 所有对主场景内部结构的依赖都关在这一个文件里，而且全部是「看」，不改任何东西：
##   - 读 main 的属性（READS）
##   - 监听 net 的信号（SIGNALS）
##   - 场景树里新出现的按钮和输入框，自动接上按键音
## 主场景以后要是拆了，这个文件跟着改（或者删掉，由新代码直接调导演的接口）。
## 读属性一律用 get() 加默认值：对不上就不出声，不报错。
## 「不报错」的代价是改名之后声音会悄悄哑掉，所以依赖都列在下面几张表里，
## tests/unit_audio.gd 会对着源码查：表里的名字不在了，CI 就红。

const LifeTime := preload("res://scripts/ui/life_time.gd")
const P := preload("res://scripts/ui/palette.gd")

## 从主场景（scripts/main.gd）读的属性
const READS := ["world", "net", "life", "last_world", "my_role", "content", "events_by_id", "ui", "screen",
	"modal", "modal_body", "toast", "offline_preview", "_preview_minute", "_page_id"]
## 监听的联机信号（scripts/net/lifeline_client.gd）
const SIGNALS := ["snapshot", "world_state", "event_started", "log_entries", "presence", "failed"]
## 页面名（main._page_id）→ 配乐的场景。没列出来的页面都算 title
const PAGE_SCENE := {"roll": "roll", "scroll": "ending", "ending": "ending"}
## 按钮的音效种类。优先读按钮的 meta "sfx"（tap / back / shake / birth / option / none）；
## 没有 meta 的按下面这几个字认，认不出来就是普通的 tap
const TEXT_KINDS := [["重新投胎", "shake"], ["出生吧", "birth"], ["返回", "back"], ["回大厅", "back"]]

var main: Node
var audio: Node

var _net: Object = null
var _scene := ""
var _page := ""
var _themed := false
var _accent := Color.TRANSPARENT
var _toast_alpha := 0.0
var _acts := {}
var _dids := {}  ## role -> 看过的最后一条 did 的序号（一回一回做的事）
var _money := -1
var _other_chosen := false
var _paired := false  ## 这会儿两人正搭伴做同一件事（world_state 里 actors[我].tg）
var _partner_live := true
var _last_pos := {}
var _page_cool := 0.0


func attach(p_main: Node, p_audio: Node) -> void:
	main = p_main
	audio = p_audio
	get_tree().node_added.connect(_on_node_added)


func _other(role: String) -> String:
	return "mei" if role == "qing" else "qing"


func _role() -> String:
	return str(main.get("my_role")) if main.get("my_role") != null else "qing"


func _dict(key: String) -> Dictionary:
	var v: Variant = main.get(key)
	return v if v is Dictionary else {}


func _ctl(key: String) -> Control:
	var v: Variant = main.get(key)
	return v if v is Control and is_instance_valid(v) else null


# ---------------------------------------------------------------- 按钮 ----

func _on_node_added(n: Node) -> void:
	if n is LineEdit:
		n.text_changed.connect(func(_t): audio.cue("type", 0.0, randf_range(0.92, 1.08)))
	elif n is BaseButton:
		n.pressed.connect(_on_pressed.bind(n))


## 按下的那一刻再认它是哪种按钮（那时候 meta 和文字都已经设好了）
func _kind(b: BaseButton) -> String:
	if b.has_meta("sfx"):
		return str(b.get_meta("sfx"))
	var modal_body := _ctl("modal_body")
	var modal := _ctl("modal")
	if modal_body != null and modal != null and modal_body.is_ancestor_of(b) and modal.has_meta("waiting_event"):
		var events: Variant = main.get("events_by_id")
		var ev: Dictionary = events.get(modal.get_meta("waiting_event"), {}) if events is Dictionary else {}
		return "option_mirror" if str(ev.get("kind", "")) == "mirror" else "option"
	var text: String = b.text if b is Button else ""
	for pair in TEXT_KINDS:
		if text.contains(pair[0]):
			return pair[1]
	return "tap"


func _on_pressed(b: BaseButton) -> void:
	match _kind(b):
		"none":
			pass
		"option_mirror":  # 默契事件：我先把我这半句说出去
			audio.cue("stamp")
			audio.sting("call_" + _role())
		"option":
			audio.cue("stamp")
		"shake":
			audio.cue("shake")
		"birth":
			audio.cue("birth")
		"back":
			audio.cue("tap", -2.0, 0.84)
		_:
			audio.cue("tap", 0.0, randf_range(0.96, 1.04))


# ---------------------------------------------------------------- 联机信号 ----

func _watch_net() -> void:
	var net: Variant = main.get("net")
	if net == _net or (net != null and not is_instance_valid(net)):
		return
	_net = net
	if net == null:
		return
	for sig in SIGNALS:
		var handler := Callable(self, "_on_" + sig)
		if net.has_signal(sig) and not net.is_connected(sig, handler):
			net.connect(sig, handler)


func _on_failed(_text: String) -> void:
	audio.cue("error")


func _on_snapshot(data: Dictionary) -> void:
	var online: Variant = data.get("online")
	if online is Dictionary:
		_partner_live = bool(online.get(_other(str(data.get("you", "qing"))), true))
	_acts.clear()
	_paired = false
	_money = -1


func _on_presence(data: Dictionary) -> void:
	var online: Variant = data.get("online")
	if not online is Dictionary:
		return
	var live := bool(online.get(_other(_role()), true))
	if live != _partner_live and _scene == "life":
		audio.cue("door_open" if live else "door_close")
	_partner_live = live


func _on_event_started(data: Dictionary) -> void:
	var pe: Variant = data.get("event")
	if not pe is Dictionary:
		return
	_other_chosen = false
	if str(pe.get("kind", "")) == "milestone":
		audio.hush(30.0)  # 关口（升学、找工作、安家）：不拍醒木，把音乐收住，越静越重
	elif (pe.get("roles", []) as Array).has(_role()):
		audio.cue("xingmu")  # 醒木一拍，开说


func _on_world_state(data: Dictionary) -> void:
	var me := _role()
	var other := _other(me)
	var actors: Variant = data.get("actors")
	if actors is Dictionary:
		for r in [me, other]:
			var a: Variant = actors.get(r)
			var act: Variant = a.get("act") if a is Dictionary else null
			if act != null and _acts.get(r) != act and _acts.has(r):
				audio.act(str(act), r == me, _near())
			_acts[r] = act
			# 一回一回当场做完的（did 的序号变了，不是对门补上的那一份）：也响一声那件事
			var did: Variant = a.get("did") if a is Dictionary else null
			if did is Dictionary:
				var n := int(did.get("n", 0))
				if _dids.has(r) and int(_dids[r]) != n and not bool(did.get("j", false)):
					audio.act(str(did.get("a", "")), r == me, _near())
				_dids[r] = n
		var mine: Variant = actors.get(me)
		_paired = mine is Dictionary and bool(mine.get("tg", false))
	var money: Variant = data.get("money")
	if money is Dictionary:
		var m := int(money.get(me, 0))
		if _money >= 0 and m > _money:
			audio.cue("coin")
		_money = m
	# 默契事件里对方选好了：听得见 TA 开了口，听不出 TA 说的是什么
	var ev: Variant = data.get("event")
	if ev is Dictionary and str(ev.get("kind", "")) == "mirror" and ev.get("chosen") is Dictionary:
		var chosen := bool(ev.chosen.get(other, false))
		if chosen and not _other_chosen and (ev.get("roles", []) as Array).has(me):
			audio.sting("call_" + other, -7.0)
		_other_chosen = chosen
	elif ev == null:
		_other_chosen = false


func _on_log_entries(data: Dictionary) -> void:
	for e in data.get("entries", []):
		match str(e.get("kind", "")):
			"together":
				audio.cue("bell_duet")
			"mirror":
				audio.sting("resonance" if bool(e.get("resonance", false)) else "mismatch", 0.0)
			"milestone":  # 关口揭晓：同路是合上的那一句；分开走，只剩我这半句，没人接
				audio.sting("resonance" if bool(e.get("resonance", false)) else "call_" + _role())
			"day":
				audio.hush(7.0)
				audio.cue("day_end")
			"death":
				audio.hush(600.0)
				audio.cue("death")


# ---------------------------------------------------------------- 每帧 ----

func _near() -> float:
	var world: Variant = main.get("world")
	if world == null or not is_instance_valid(world):
		return 0.0
	var actors: Dictionary = world.get("actors") if world.get("actors") is Dictionary else {}
	var a: Variant = actors.get(_role())
	var b: Variant = actors.get(_other(_role()))
	if a == null or b == null or not b.visible:
		return 0.0
	return 1.0 - smoothstep(260.0, 1300.0, a.position.distance_to(b.position))


func _process(delta: float) -> void:
	if main == null or not is_instance_valid(main):
		return
	_watch_net()
	var world: Variant = main.get("world")
	var screen := _ctl("screen")
	var modal := _ctl("modal")
	var life := _dict("life")
	var in_world: bool = world != null and is_instance_valid(world) and (screen == null or not screen.visible)

	# 现在是哪一场
	var page := str(main.get("_page_id")) if main.get("_page_id") != null else ""
	var scene: String = "life" if in_world else PAGE_SCENE.get(page, "title")
	if scene != _scene:
		_scene = scene
		audio.set_scene(scene)
		_last_pos.clear()

	_watch_pages(delta, page, in_world)
	_watch_toast()
	_place_button(in_world, modal)

	if not in_world:
		audio.idle()
		return
	var me := _role()
	var actors: Dictionary = world.get("actors") if world.get("actors") is Dictionary else {}
	var a: Variant = actors.get(me)
	if a == null:
		return
	var b: Variant = actors.get(_other(me))
	var preview := bool(main.get("offline_preview"))
	var last := _dict("last_world")
	var turn := int(life.get("turn", 0))
	var minute := float(main.get("_preview_minute")) if preview else float(last.get("minute", 390.0))
	var bond: Variant = last.get("bond", life.get("bond", {}))
	var sync := float(bond.get("sync", 0.0)) if bond is Dictionary else 0.0
	var other_pos: Variant = b.position if b != null and b.visible else null
	# 上学日：老字段 schoolDay；新字段 rest 的意思反过来（true 是休息日）
	var school_day := bool(last.get("schoolDay", false)) if last.has("schoolDay") else (last.has("rest") and not bool(last.get("rest")))
	if preview:
		sync = 30.0
	elif _paired:
		sync = 100.0  # 搭伴的时候「合」一直浮着，不用等默契攒起来
	audio.set_life(_dict("content").get("map", {}), me, a.position, other_pos, _partner_live or preview, turn,
		str(LifeTime.at(turn).stage), LifeTime.SEASONS[turn % 4], minute, school_day,
		sync, modal != null and modal.visible)

	# 脚步
	for r in actors:
		var actor: Variant = actors[r]
		var pos: Vector2 = actor.position
		var moved: float = pos.distance_to(_last_pos.get(r, pos))
		_last_pos[r] = pos
		if moved > 0.0 and moved < 80.0 and bool(actor.get("walking")) and actor.visible:
			var gain := 1.0 if r == me else 1.0 - smoothstep(150.0, 900.0, pos.distance_to(a.position))
			audio.step(str(r), pos, moved, r == me, gain)


## 整页换了（标题 → 大厅 → 投胎……）：抽一张纸的声音。进出河畔里有自己的转场，不抽
func _watch_pages(delta: float, page: String, in_world: bool) -> void:
	_page_cool = maxf(0.0, _page_cool - delta)
	if page == _page:
		return
	if _page != "" and not in_world and _page_cool <= 0.0:
		audio.cue("page")
		_page_cool = 0.35
	_page = page


## 音量按钮：用主界面的主题和玩家自己的颜色；在河畔里挪到「亲近 / 默契」卡片下面；
## 弹窗出来的时候藏起来；人生长卷那一页整屏都是那张纸，也藏
func _place_button(in_world: bool, modal: Control) -> void:
	if not _themed:
		var ui := _ctl("ui")
		if ui != null and ui.theme != null:
			audio.adopt_theme(ui.theme)
			_themed = true
	var accent := P.role_color(_role())
	if _themed and accent != _accent:
		_accent = accent
		audio.tint_button(accent)
	# 离线逛逛时右上角没有对门的牌，按钮回到角上
	audio.place_button(in_world and main.get("offline_preview") != true, (modal != null and modal.visible) or _page == "scroll")


func _watch_toast() -> void:
	var toast := _ctl("toast")
	if toast == null:
		return
	var a := toast.modulate.a
	if a > 0.99 and _toast_alpha < 0.99:
		audio.cue("toast")
	_toast_alpha = a
