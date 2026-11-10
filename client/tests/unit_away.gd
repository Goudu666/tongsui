extends SceneTree
## 外地、写信的界面单测：
##   - 出口按钮底下那行：去哪张图、路上花多久（过桥一个钟头、去外地一整段）
##   - 信：只挑寄给我的、正文加落款、老服务器没有 post 也不出错
##   - 安装包里的内容：写信的文字、外地的出口带 ride
## 跑：godot --headless --path client -s res://tests/unit_away.gd

const LetterCard := preload("res://scripts/ui/letter_card.gd")
const ContentStore := preload("res://scripts/net/content_store.gd")

var _failed := 0


func _init() -> void:
	_run()


func _run() -> void:
	_exits()
	_letters()
	if _failed == 0:
		print("✓ 外地和写信：出口写路上多久 / 信只挑寄给我的、带落款 / 安装包里有信的文字和坐车的出口")
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("✗ ", what)


func _exits() -> void:
	var main: Script = load("res://scripts/main.gd")
	_check(main.exit_cost({"to": "across", "ride": 60}, {"name": "河对岸"}, "river") == "去河对岸 · 路上 一个钟头", "过桥：%s" % main.exit_cost({"to": "across", "ride": 60}, {"name": "河对岸"}, "river"))
	_check(main.exit_cost({"to": "away", "ride": 240}, {"name": "外地"}, "street") == "去外地 · 路上一整段", "去外地")
	_check(main.exit_cost({"to": "street"}, {"name": "楼下"}, "building") == "去楼下", "走过去的不写路上")
	_check(main.exit_cost({"to": "building", "ride": 0}, {}, "building") == "", "同一张图上下楼什么也不写")
	var c: Dictionary = ContentStore.load_bundled()
	var rides := {}
	for ex in c.map.exits:
		rides[str(ex.id)] = int(ex.get("ride", 0))
	_check(rides.get("street.to_away", 0) == 240 and rides.get("away.to_home", 0) == 240, "外地和楼下之间坐车，一整段：%s" % [rides])
	_check(rides.get("river.to_across", 0) == 60 and rides.get("across.to_river", 0) == 60, "过桥一个钟头")


func _letters() -> void:
	var names := {"qing": "小满", "mei": "阿蘅"}
	var entry := {"kind": "day", "post": [
		{"from": "mei", "to": "qing", "label": "19 岁", "lines": ["食堂的馒头是甜的。", "这边下雨不打雷。", "先写到这儿。"], "side": "away"},
		{"from": "qing", "to": "mei", "label": "19 岁", "lines": ["楼下的早点铺换了招牌。", "今年冬天暖气来得早。", "等你回来。"], "side": "home"},
	], "crossed": "两封信在路上错过去了。"}
	var mine := LetterCard.mine(entry, "qing")
	_check(mine.size() == 1 and mine[0].from == "mei", "只挑寄给我的：%s" % [mine])
	var t := LetterCard.text_of(mine[0], names)
	_check(t.size() == 4 and t[0] == "食堂的馒头是甜的。" and t[3] == "—— 阿蘅", "正文加落款：%s" % [t])
	_check(LetterCard.mine({"kind": "day"}, "qing").is_empty(), "老服务器没有 post")
	_check(LetterCard.mine({"kind": "day", "post": "坏的"}, "qing").is_empty(), "post 不是列表")
	var c: Dictionary = ContentStore.load_bundled()
	var letters: Dictionary = c.get("letters", {})
	_check(letters.get("lines", {}).has("home") and letters.get("lines", {}).has("work") and letters.get("ends", []).size() >= 4, "安装包里有写信的文字")
	# 信纸画得出来
	var box := VBoxContainer.new()
	var card := LetterCard.build(box, mine[0], names)
	_check(card != null and box.get_child_count() == 1, "信纸")
	box.free()
