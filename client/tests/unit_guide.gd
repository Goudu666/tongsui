extends SceneTree
## 开局引导（ui/guide.gd）的单测：
##   - 路标找路：从街上去楼里先走「上楼」那个出口；人就在那张图上不指路；从楼里去河边先下楼
##   - 纸带上的每一句「下一件事」都找得回剧本里的那张图、那一段（章 + 那句话），而且那张图存在
##   - 从家里出发，主线写到的图都有路走过去（外地那几张图要等「坐车去外地」的出口，没路的只打印出来，不算失败）
##   - 岁数落在第几章；小纸条每条都有字、贴的位置认得
## 跑：godot --headless --path client -s res://tests/unit_guide.gd

const Guide := preload("res://scripts/ui/guide.gd")
const ContentStore := preload("res://scripts/net/content_store.gd")

var _failed := 0


func _init() -> void:
	var c: Dictionary = ContentStore.load_bundled()
	_route(c)
	_story_targets(c)
	_chapters(c)
	_tips()
	if _failed == 0:
		print("✓ 开局引导：路标找路 / 每句「下一件事」找得回图和那一段 / 岁数落在第几章 / 小纸条")
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("✗ ", what)


func _exit(map: Dictionary, id: String) -> Dictionary:
	for ex in map.exits:
		if str(ex.id) == id:
			return ex
	return {}


func _route(c: Dictionary) -> void:
	var map: Dictionary = c.map
	var down := _exit(map, "building.hall_down")
	_check(not down.is_empty(), "楼里有下楼的出口")
	var street_pos := Vector2(float(down.arrive[0]) + 300.0, float(down.arrive[1]))
	var r := Guide.route(map, street_pos, "building")
	_check(not r.is_empty() and str(r.get("to", "")) == "building", "街上去楼里先走回楼里的出口：%s" % r.get("id", "（没找到）"))
	var home := Vector2(float(map.spawn.qing[0]), float(map.spawn.qing[1]))
	_check(Guide.route(map, home, "building").is_empty(), "人就在楼里：不指路")
	var to_river := Guide.route(map, home, "river")
	_check(str(to_river.get("id", "")) == "building.hall_down", "从家里去河边先下楼：%s" % to_river.get("id", "（没找到）"))


func _story_targets(c: Dictionary) -> void:
	var map: Dictionary = c.map
	var scenes := {}
	for sc in map.scenes:
		scenes[str(sc.id)] = sc
	var home := Vector2(float(map.spawn.qing[0]), float(map.spawn.qing[1]))
	var unreachable := {}
	for e in c.story.events:
		_check(scenes.has(str(e.scene)), "%s 的图 %s 不存在" % [e.id, e.scene])
		_check(Guide.SLOT_IDS.has(str(e.slot)), "%s 的那一段 %s 认不得" % [e.id, e.slot])
		# 同一章同一句话的几个变体，必须是同一张图、同一段（路标按「章 + 那句话」找回去，找到的是第一个）
		for o in c.story.events:
			if int(o.chapter) == int(e.chapter) and str(o.next) == str(e.next):
				_check(str(o.scene) == str(e.scene) and str(o.slot) == str(e.slot), "第 %d 章「%s」：%s 和 %s 不在同一张图、同一段" % [e.chapter, e.next, e.id, o.id])
				break
		if str(e.scene) != "building" and Guide.route(map, home, str(e.scene)).is_empty():
			unreachable[str(e.scene)] = true
	if not unreachable.is_empty():
		print("  （从家里还走不到：%s）" % ", ".join(unreachable.keys()))
	for must in ["street", "river", "primary", "middle", "across", "park", "hospital"]:
		_check(not unreachable.has(must), "从家里得走得到 %s" % must)


func _chapters(c: Dictionary) -> void:
	var g := Guide.new()
	g.main = _FakeMain.new(c)
	_check(g.chapter_at(3) == 1 and g.chapter_at(5) == 1, "3~5 岁第一章")
	_check(g.chapter_at(6) == 2, "6 岁第二章")
	_check(g.chapter_at(12) == 3, "12 岁第三章")
	_check(g.chapter_at(70) == 7, "70 岁第七章")
	_check(g._dots(3) == "● ● ● ○ ○ ○ ○", "七个点走到第三章：%s" % g._dots(3))
	g.free()


func _tips() -> void:
	for id in Guide.TIPS:
		var t: Array = Guide.TIPS[id]
		_check(str(t[0]).length() >= 8 and str(t[0]).length() <= 70, "小纸条 %s 的字数（8~70）：%d" % [id, str(t[0]).length()])
		_check(["walk", "act", "story", "partner", "goal", "top"].has(str(t[1])), "小纸条 %s 贴的位置认不得：%s" % [id, t[1]])


class _FakeMain extends RefCounted:
	var content: Dictionary

	func _init(c: Dictionary) -> void:
		content = c
