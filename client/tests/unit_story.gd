extends SceneTree
## 主线的界面单测：
##   - HUD 上那张小签写什么：第几章、章名、今天的下一件事；章末躲不过的写「今天一早」；没排上只写章名
##   - 主线弹窗摆哪些选项：家里给不了的（带标记门槛又走不了的）不摆，钱不够的摆着（灰的）
##   - 安装包里的内容带着主线，七章每章都有事
## 跑：godot --headless --path client -s res://tests/unit_story.gd

const Hud := preload("res://scripts/ui/hud.gd")
const ContentStore := preload("res://scripts/net/content_store.gd")

var _failed := 0


func _init() -> void:
	_strip()
	_options()
	_content()
	if _failed == 0:
		print("✓ 主线界面：小签（第几章 / 下一件事 / 今天一早 / 没排上）/ 弹窗按家底摆选项 / 安装包里七章都有事")
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
	_check(t[0] == "第七章" and t[1].ends_with("今天一早"), "章末强制的那一件写「今天一早」：%s" % t[1])
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


func _content() -> void:
	var c: Dictionary = ContentStore.load_bundled()
	var story: Dictionary = c.get("story", {})
	_check(story.get("chapters", []).size() == 7, "安装包里应有七章")
	var by := {}
	for e in story.get("events", []):
		by[int(e.chapter)] = true
		_check(str(e.get("next", "")) != "" and e.has("scene") and e.has("slot"), "%s 缺 next / scene / slot" % e.get("id"))
	_check(by.size() == 7, "每章都有事：%s" % [by.keys()])
