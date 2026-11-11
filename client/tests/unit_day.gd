extends SceneTree
## 一天的行动循环（客户端这一半）：
##   - 行动按钮的小字：花多久、累多少、长什么；剩的时间不够一整回写「只够做一截」
##   - 一天收工的小结卡：时间条、长了多少、离下一道关、照这样还要几个日子（来得及 / 得再加把劲 / 明天就是那一天）
## 跑：godot --headless --path client -s res://tests/unit_day.gd

const Main := preload("res://scripts/main.gd")
const DayCard := preload("res://scripts/ui/day_card.gd")

var _failed := 0


func _init() -> void:
	_cost()
	_card()
	_menu()
	if _failed == 0:
		print("✓ 一天的行动：按钮写清花多久、累多少、长什么 / 只够做一截 / 小结卡的时间条和「照这样还要几个日子」/ 点位菜单的牌子和「几点才有」")
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("✗ ", what)


func _cost() -> void:
	var study := {"id": "study", "label": "写作业", "minutes": 90, "needs": {"energy": -10, "mood": -6}, "stats": {"mind": 0.4}}
	var c: Array = Main.act_cost(study, 240.0, 0.56)
	_check(c[0] == "一个半钟头", "时长：%s" % c[0])
	_check(c.has("精力 -6"), "精力按摊到一回的算：%s" % str(c))
	_check(c.has("长心智"), "长什么：%s" % str(c))
	var short: Array = Main.act_cost(study, 30.0, 0.56)
	_check(str(short[0]).begins_with("30 分钟") and str(short[0]).contains("一截"), "剩半个钟头：%s" % short[0])
	var roof := {"id": "play_roof", "minutes": 60, "needs": {"mood": 12, "energy": -4}, "stats": {}}
	var r: Array = Main.act_cost(roof, 240.0, 1.0)
	_check(r.has("心情好"), "不长属性的写心情：%s" % str(r))
	var work := {"id": "work", "minutes": 120, "money": 2, "needs": {"energy": -12}, "stats": {"body": 0.15, "mind": 0.1}}
	_check(Main.act_cost(work, 240.0).has("挣 2 块"), "挣钱的写挣多少")
	_check(Main.duration_text(60) == "一个钟头" and Main.duration_text(120) == "两个钟头" and Main.duration_text(45) == "45 分钟", "时长的说法")


func _card() -> void:
	var g := {"title": "小升初", "turns": 4, "line": "去重点班", "unit": "分", "have0": 62, "have": 65, "need": 74, "ok": false, "pace": 3}
	_check(DayCard.pace_text(g).contains("来得及"), "三个日子够得上、还剩四个：来得及")
	g.pace = 6
	_check(DayCard.pace_text(g).contains("加把劲"), "要六个、只剩四个：加把劲")
	g.erase("pace")
	_check(DayCard.pace_text(g).contains("没往上挪"), "今天没挪")
	g.turns = 0
	_check(DayCard.pace_text(g).contains("明天就是"), "明天开考")
	_check(DayCard.countdown(0) == "明天就是那一天" and DayCard.countdown(3) == "还剩 3 个日子", "倒计时")
	_check(DayCard.goal_line({"title": "中考", "line": "重点高中", "unit": "分", "have0": 70, "have": 72, "need": 76, "ok": false}).contains("今天 +2"), "TA 那一行写今天挪了几分")
	# 摆得出来：有时间条、有进度条
	var box := VBoxContainer.new()
	var e := {
		"gains": {"qing": {"mind": 0.4}},
		"spent": {"qing": [{"a": "study", "l": "写作业", "f": 930, "t": 1110}, {"a": "play_roof", "l": "楼顶放鸽子", "f": 1110, "t": 1170, "tg": true}], "mei": [{"a": "study", "l": "写作业", "f": 1110, "t": 1320}]},
		"goal": {"qing": {"title": "小升初", "turns": 4, "line": "去重点班", "unit": "分", "have0": 62, "have": 65, "need": 74, "ok": false, "pace": 3, "crossed": []}},
	}
	DayCard.build(box, e, "qing", "mei", {"mei": "梅"})
	var strips := 0
	var bars := 0
	var text := ""
	for c in box.get_children():
		if c is DayCard.DayStrip:
			strips += 1
		elif c is DayCard.GoalBar:
			bars += 1
		elif c is Label:
			text += (c as Label).text
	_check(strips == 1, "有一条今天的时间")
	_check(text.contains("4 个钟头") and text.contains("和 TA 一起 1 个钟头"), "写今天花了多久、和 TA 一起多久：%s" % text)
	_check(text.contains("心智 +4"), "长了多少：%s" % text)
	box.free()
	# 旧服务器：没有 spent / goal，只写长了什么
	var old := VBoxContainer.new()
	DayCard.build(old, {"gains": {"qing": {}}}, "qing", "mei", {})
	_check(old.get_child_count() == 1, "旧服务器的那一条照样摆得出来")
	old.free()


## 点位菜单：菜单按 spots[].actions 的顺序列出这个人现在看得见的几件；不在钟点上的也列着、带 _late；默认是头一件现在就能做的
func _menu() -> void:
	const WV := preload("res://scripts/world/world_view.gd")
	var w = WV.new()
	w.actions = {
		"listen": {"id": "listen", "label": "喝茶听一段", "minutes": 40, "requires": {"minAge": 6, "hours": [540, 1260]}},
		"tea_box": {"id": "tea_box", "label": "在茶社包个座", "minutes": 90, "requires": {"minAge": 6, "flags": ["fam_rich"], "hours": [780, 1260]}},
		"tea_runner": {"id": "tea_runner", "label": "在茶社跑堂", "minutes": 120, "requires": {"minAge": 15, "maxAge": 29, "hours": [540, 1260]}},
		"cards": {"id": "cards", "label": "跟街坊打扑克", "minutes": 60, "requires": {"minAge": 18, "hours": [1110, 1320]}},
	}
	w.my_role = "qing"
	w.unlocks = {"qing": []}
	w.age = 17
	w.slot = 2
	var sp := {"id": "tea_seat", "actions": ["listen", "tea_box", "tea_runner", "cards"]}
	var ids: Array = []
	for a in w.actions_of(sp):
		ids.append(str(a.id))
	_check(ids == ["listen", "tea_runner"], "十七岁、没有家底：听一段、跑堂（包座要殷实人家，打扑克要成年）：%s" % [ids])
	_check(str(w.action_of(sp).get("id")) == "listen", "不点就是头一件")
	_check(str(w.action_of(sp, "tea_runner").get("id")) == "tea_runner", "点了跑堂就是跑堂")
	w.unlocks = {"qing": ["tea_box"]}
	w.slot = 0
	var early: Array = w.actions_of(sp)
	_check(early.size() == 3 and bool(early[0].get("_late", false)), "一早茶社没开：几件都列着，带着几点才有")
	_check(Main._late_text(early[0]) == "09:00–21:00 才有", "按钮上写几点才有：%s" % Main._late_text(early[0]))
	# 后添的事（menu）只在点到时做：头一件不在钟点上，不点还是头一件，不会掉到后添的那件上（和服务器一样）
	w.actions["boat"] = {"id": "boat", "label": "划船", "minutes": 60, "menu": true, "requires": {"minAge": 45, "hours": [540, 1080]}}
	w.actions["morning_walk"] = {"id": "morning_walk", "label": "遛弯", "minutes": 60, "requires": {"hours": [360, 540]}}
	w.age = 70
	w.slot = 2
	var lake := {"id": "lake_walk", "actions": ["morning_walk", "boat"]}
	_check(str(w.action_of(lake).get("id")) == "morning_walk", "下午不点：还是遛弯（不是时候），不去划船")
	_check(str(w.action_of(lake, "boat").get("id")) == "boat", "点了划船才划船")
	var chip := Main.menu_chip("在茶社跑堂", true, false)
	_check(chip.text == "在茶社跑堂", "牌子上写着那件事")
	chip.free()
	w.free()
