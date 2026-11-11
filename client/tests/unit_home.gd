extends SceneTree
## 家里的东西（content/home.yaml）的客户端：godot --headless --path client -s res://tests/unit_home.gd
## 查：点位菜单认 requires.home（看点位那一户）和 buys（只在自己家、服务器说买得了）；老服务器不发 homes 时照常；
## home_life.gd 挑出来的每一张图图集里都有；年代名认得；kind "home" 的日志进长卷不出错。

const WorldView := preload("res://scripts/world/world_view.gd")
const HomeLife := preload("res://scripts/world/home_life.gd")
const LifeScroll := preload("res://scripts/ui/life_scroll.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("✗ ", what)


func _ids(list: Array) -> Array:
	return list.map(func(a): return str(a.id))


## 和 world_view.apply_world 里那两行一样（apply_world 本身要整个世界搭起来）
func _feed(w, view: Dictionary) -> void:
	w.homes = WorldView._role_lists(view.get("homes"))
	w.buys = WorldView._role_lists(view.get("buys"))


func _initialize() -> void:
	# 1. 点位菜单
	var w := WorldView.new()
	w.my_role = "qing"
	w.age = 10
	for a in [
		{"id": "eat", "requires": {}},
		{"id": "hm_tv", "menu": true, "requires": {"home": ["tv"]}},
		{"id": "hm_pc", "menu": true, "requires": {"home": ["pc"], "minAge": 10}},
		{"id": "buy_tape", "menu": true, "quick": true, "buys": "tape", "requires": {}},
	]:
		w.actions[a.id] = a
	w._zone_owner = {"home_qing": "qing", "home_mei": "mei"}
	var mine := {"id": "table_qing", "zone": "home_qing", "actions": ["eat", "hm_tv", "hm_pc", "buy_tape"]}
	var theirs := {"id": "table_mei", "zone": "home_mei", "actions": ["eat", "hm_tv", "hm_pc", "buy_tape"]}
	var hall := {"id": "hall_stool", "zone": "hallway", "actions": ["eat", "hm_tv"]}
	check(_ids(w.actions_of(mine)) == ["eat"], "老服务器不发 homes：家里的东西都不显示，吃饭照旧")
	_feed(w, {"homes": {"qing": [], "mei": ["tv", "pc"]}, "buys": {"qing": ["buy_tape"], "mei": []}})
	check(_ids(w.actions_of(mine)) == ["eat", "buy_tape"], "自己家没电视：不显示看电视；买得了复读机就显示")
	check(_ids(w.actions_of(theirs)) == ["eat", "hm_tv", "hm_pc"], "去对门：看对门家有什么；在对门家不能买东西")
	check(_ids(w.actions_of(hall)) == ["eat"], "不在谁家的点位看自己家")
	_feed(w, {"homes": {"qing": ["tv"], "mei": []}, "buys": {}})
	check(_ids(w.actions_of(mine)) == ["eat", "hm_tv"], "家里添了电视就能看；buys 空了买的那一项收起来")
	check(_ids(w.actions_of(hall)) == ["eat", "hm_tv"], "不在谁家的点位看自己家（有电视）")
	_feed(w, {"homes": "坏的", "buys": null})
	check(_ids(w.actions_of(mine)) == ["eat"], "homes 形状不对当成空")
	w.free()

	# 2. 屋里摆的图：每种家境、每个年代、什么都有 / 什么都没有，挑出来的都在图集里
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(HomeLife.META))
	check(meta is Dictionary and ResourceLoader.exists(HomeLife.ATLAS), "图集和 sprites.json 都在")
	var sprites: Dictionary = meta.get("sprites", {}) if meta is Dictionary else {}
	var everything := ["radio", "tv", "fridge", "books", "milk", "phone", "console", "tape", "pc"]
	for wealth in 3:
		for d in 7:
			for have in [[], everything, ["radio", "tv"]]:
				for k in HomeLife.pick(wealth, have, d):
					for r in ["qing", "mei"]:
						check(sprites.has("%s_%s" % [k, r]), "图集里没有 %s_%s（家境 %d 年代 %d）" % [k, r, wealth, d])
	check(HomeLife.pick(0, [], 3).has("curtain") and HomeLife.pick(2, [], 3).has("sofa") and HomeLife.pick(1, [], 3).has("sewing"), "三种家境各有各的陈设")
	check(HomeLife.pick(0, ["tv"], 3).has("tv_bw_0") and HomeLife.pick(2, ["tv"], 3).has("tv_color_2") and HomeLife.pick(2, ["tv"], 5).has("tv_flat_2"), "电视按年代和家境换样子")
	check(HomeLife.decade_index("九十年代", "") == 3 and HomeLife.decade_index("二〇年代", "") == 6 and HomeLife.decade_index("", "teen") == 4, "年代名认得，没有就按街景猜")
	var hl := HomeLife.new()
	root.add_child(hl)
	hl.set_look({"qing": 0, "mei": 2}, "九十年代", "childhood")
	hl.set_items({"qing": ["tv"], "mei": ["tv", "books"]})
	check(hl._keys.has("tv_bw_0_qing") and hl._keys.has("bookcase_mei") and hl._keys.has("floor_rich_mei"), "两家按各自的家境和东西摆")
	hl.set_items({"qing": ["tv", "fridge"], "mei": ["tv", "books"]})
	check(hl._keys.has("fridge_qing") and float(hl._born["fridge_qing"]) > -INF and float(hl._born["tv_bw_0_qing"]) == -INF, "新进门的东西印出来，原来就在的不重印")
	hl.queue_free()

	# 3. 长卷：kind "home" 不出错，记成纸边上的小记号
	var life := {"log": [
		{"kind": "home", "turn": 3, "age": 4, "text": "家里有电视了。", "home": {"role": "qing", "item": "tv", "name": "电视"}},
		{"kind": "home", "turn": 5, "age": 5, "text": "", "home": {"role": "mei", "item": "tape", "name": "复读机", "bought": true}},
		{"kind": "home", "turn": 6},
		{"kind": "day", "turn": 6, "label": "", "text": ""},
	]}
	var m: Dictionary = LifeScroll.build(life, {})
	check(m.get("homes", []).size() == 2 and int(m.homes[0].turn) == 3 and str(m.homes[1].role) == "mei", "长卷记下两家添东西的日子，形状不对的跳过")

	if fails == 0:
		print("✓ 家里的东西：菜单认 requires.home / buys、老服务器照常、三种家境的陈设、电视按年代换、新东西印出来、长卷记号")
	quit(1 if fails > 0 else 0)
