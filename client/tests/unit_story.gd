extends SceneTree
## 主线的界面单测：
##   - HUD 上那张小签写什么：第几章、章名、今天的下一件事；章末躲不过的写「今天……」；没排上只写章名
##   - 主线弹窗摆哪些选项：家里给不了的（带标记门槛又走不了的）不摆，钱不够的摆着（灰的）
##   - 关口摆哪些路（milestone_options，docs/CAREER.md）：写了 hide、锁的理由正是它的 lock 的不摆；分数、积蓄不够的照旧摆；没写 hide 的照旧摆
##   - 安装包里的内容带着主线，七章每章都有事
## 跑：godot --headless --path client -s res://tests/unit_story.gd

const Hud := preload("res://scripts/ui/hud.gd")
const ContentStore := preload("res://scripts/net/content_store.gd")

var _failed := 0


func _init() -> void:
	_strip()
	_options()
	_milestone()
	_content()
	if _failed == 0:
		print("✓ 主线界面：小签（第几章 / 下一件事 / 躲不过的写今天 / 没排上）/ 弹窗按家底摆选项 / 关口按 hide 藏别的行当的路 / 安装包里七章都有事")
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("✗ ", what)


func _strip() -> void:
	var t := Hud.story_text({"chapter": 1, "title": "对门", "next": "上午，楼道里", "force": false})
	_check(t[0] == "第一章", "章号写成汉字：%s" % t[0])
	_check(t[1] == "对门 · 下一件事 上午，楼道里", "小签正文：%s" % t[1])
	t = Hud.story_text({"chapter": 7, "title": "河边", "next": "傍晚，河边的长椅", "force": true})
	_check(t[0] == "第七章" and t[1] == "河边 · 今天傍晚，河边的长椅 · 到点一定会去", "章末躲不过的那一件一早写明「今天……到点一定会去」：%s" % t[1])
	t = Hud.story_text({"chapter": 2, "title": "一个班", "next": null})
	_check(t[1] == "一个班", "今天没排上主线只写章名：%s" % t[1])


func _options() -> void:
	var main: Script = load("res://scripts/main.gd")
	var ev := {"options": [
		{"id": "line", "text": "排队", "requires": {}},
		{"id": "egg", "text": "举过头顶", "requires": {}},
		{"id": "extra", "text": "多买一套", "requires": {"flags": ["fam_rich"]}, "cost": 1},
		{"id": "half", "text": "掰成两半", "requires": {"flags": ["fam_poor"]}},
		{"id": "treat", "text": "请客", "requires": {}, "cost": 5},
	]}
	var ids := func(list: Array) -> Array: return list.map(func(o): return o.id)
	var poor: Array = ids.call(main.story_options(ev, {"extra": "这条路不是给你留的", "treat": "积蓄 2 块，要 5 块"}))
	_check(poor == ["line", "egg", "half", "treat"], "清贫人家：殷实人家的那条不摆，钱不够的摆着：%s" % [poor])
	var rich: Array = ids.call(main.story_options(ev, {"half": "这条路不是给你留的"}))
	_check(rich == ["line", "egg", "extra", "treat"], "殷实人家：%s" % [rich])


func _milestone() -> void:
	var main: Script = load("res://scripts/main.gd")
	var ev := {"options": [
		{"id": "up_desk", "text": "评上组长", "requires": {"flags": ["job_desk"]}, "lock": "不是你这一行", "hide": true, "min": 8.8},
		{"id": "up_trade", "text": "盘下一间门脸", "requires": {"flags": ["job_trade"]}, "lock": "不是你这一行", "hide": true, "min": 7.6, "cost": 30},
		{"id": "jump", "text": "跳到别家", "requires": {"notFlags": ["job_odd"]}, "hide": true, "min": 7.9},
		{"id": "seat", "text": "家里托人", "requires": {"flags": ["fam_rich"]}, "lock": "家里没这层关系", "min": 8.0, "cost": 25},
		{"id": "steady", "text": "不争不抢", "requires": {}},
	]}
	var ids := func(list: Array) -> Array: return list.map(func(o): return o.id)
	# 坐办公室的、本事够：别的行当的 up_trade 标记不对，藏起来；殷实人家那条没写 hide，灰着摆
	var desk: Array = ids.call(main.milestone_options(ev, {"up_trade": "不是你这一行", "seat": "家里没这层关系"}))
	_check(desk == ["up_desk", "jump", "seat", "steady"], "坐办公室的：别的行当的路不摆，没写 hide 的托人灰着摆：%s" % [desk])
	# 本事不够：自己这行锁的理由是分数，照旧摆出来（灰的，写着差多少）；钱不够的也一样
	var weak: Array = ids.call(main.milestone_options(ev, {"up_desk": "心智和魅力 61 分，线是 88 分", "up_trade": "不是你这一行", "jump": "魅力和运气 40 分，线是 79 分"}))
	_check(weak == ["up_desk", "jump", "seat", "steady"], "分数不够的照旧摆：%s" % [weak])
	var broke: Array = ids.call(main.milestone_options(ev, {"up_desk": "不是你这一行", "up_trade": "积蓄 3 块，要 30 块"}))
	_check(broke == ["up_trade", "jump", "seat", "steady"], "做买卖的、钱不够：自己这行灰着摆，别的行当的藏起来：%s" % [broke])
	# 没写 lock 的 hide：理由是默认那句「这条路不是给你留的」时才藏
	var odd: Array = ids.call(main.milestone_options(ev, {"up_desk": "不是你这一行", "up_trade": "不是你这一行", "jump": "这条路不是给你留的"}))
	_check(odd == ["seat", "steady"], "打零工的：跳槽（没写 lock）也藏起来：%s" % [odd])
	# 什么都没锁：全摆（服务器没发 locks 的旧内容也一样）
	_check(ids.call(main.milestone_options(ev, {})).size() == 5, "没锁的全摆")
	# 没写 hide 的旧关口：锁着也照旧摆（接班、托关系那几条一直是灰着给人看的）
	var old := {"options": [{"id": "succeed", "requires": {"flags": ["fam_factory"]}, "lock": "家里没人在厂里"}, {"id": "odd", "requires": {}}]}
	_check(ids.call(main.milestone_options(old, {"succeed": "家里没人在厂里"})) == ["succeed", "odd"], "没写 hide 的路锁着也照旧摆")
	# 安装包里的升迁关：写了 hide 的路都带着 requires 和 lock（客户端拿 lock 认「标记不对」）
	var c: Dictionary = ContentStore.load_bundled()
	var hidden := 0
	for e in c.get("events", []):
		if str(e.id) not in ["m_rise", "m_rise2"]:
			continue
		for o in e.get("options", []):
			if o.get("hide", false):
				hidden += 1
				_check(o.get("requires") is Dictionary and str(o.get("lock", "")) != "", "%s.%s 写了 hide 要带 requires 和 lock" % [e.id, o.id])
	_check(hidden >= 18, "两道升迁关上每个行当的路都写了 hide：%d 条" % hidden)


func _content() -> void:
	var c: Dictionary = ContentStore.load_bundled()
	var story: Dictionary = c.get("story", {})
	_check(story.get("chapters", []).size() == 7, "安装包里应有七章")
	var by := {}
	for e in story.get("events", []):
		by[int(e.chapter)] = true
		_check(str(e.get("next", "")) != "" and e.has("scene") and e.has("slot"), "%s 缺 next / scene / slot" % e.get("id"))
	_check(by.size() == 7, "每章都有事：%s" % [by.keys()])
