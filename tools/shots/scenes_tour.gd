extends SceneTree
## 十一张侧视图巡拍：每张图按几个镜位、钟点、年纪、季节各拍一张，做美术前后对比用。
##   bash tools/shots/tour.sh <输出目录> [--only=street,river] [--clean]
## --clean：把 HUD 和提示条收起来，只看画。
## 不联网：走 main 的「先逛逛」，再直接把人挪到各张图上。

var out_dir := "user://tour"
var only: Array = []
var clean := false
var main: Node

## [名字, 图, 横坐标, 第几层, 几点（分钟）, 人生阶段, 季节, 回合（可选，挑下雨下雪的日子）]
const SHOTS := [
	["building_home_morning", "building", 520, 1, 430, "childhood", "spring"],
	["building_hall_dusk", "building", 1650, 1, 1090, "childhood", "autumn"],
	["building_roof_day", "building", 2300, 0, 700, "teen", "summer"],
	["street_morning", "street", 600, 0, 420, "childhood", "spring"],
	["street_alley_day", "street", 1750, 0, 760, "childhood", "summer"],
	["street_dusk", "street", 2800, 0, 1100, "teen", "autumn"],
	["street_night", "street", 1600, 0, 1290, "young", "winter"],
	["river_day", "river", 900, 0, 700, "childhood", "summer"],
	["river_dusk", "river", 2200, 0, 1095, "young", "autumn"],
	["river_night", "river", 3000, 0, 1260, "middle", "winter"],
	["primary_day", "primary", 1200, 0, 600, "childhood", "spring"],
	["middle_day", "middle", 1400, 0, 800, "teen", "autumn"],
	["across_day", "across", 1500, 0, 700, "young", "summer"],
	["across_night", "across", 3800, 0, 1250, "middle", "summer"],
	["away_dusk", "away", 1500, 0, 1080, "young", "winter"],
	["rental_night", "rental", 900, 0, 1230, "young", "winter"],
	["newhome_morning", "newhome", 1300, 0, 450, "middle", "spring"],
	["park_day", "park", 1500, 0, 660, "old", "autumn"],
	["park_dusk", "park", 2400, 0, 1100, "old", "spring"],
	["hospital_day", "hospital", 1200, 0, 720, "old", "winter"],
	# 下雨的日子（第 8 个参数是回合：weather._pick 按它决定这天下不下）
	["street_rain_day", "street", 2200, 0, 820, "teen", "summer", 2],
	["street_rain_night", "street", 2600, 0, 1240, "young", "summer", 2],
	# 门外的三个世界（家境不同，夏天去的地方不同）和两处出口
	["market_dawn_a", "market", 800, 0, 400, "childhood", "summer"],
	["market_dawn_b", "market", 2400, 0, 420, "childhood", "summer"],
	["market_day", "market", 1500, 0, 660, "teen", "autumn"],
	["market_night", "market", 900, 0, 1280, "young", "winter"],
	["seaside_day_a", "seaside", 800, 0, 700, "childhood", "summer"],
	["seaside_day_b", "seaside", 2000, 0, 760, "childhood", "summer"],
	["seaside_day_c", "seaside", 3000, 0, 820, "childhood", "summer"],
	["seaside_dusk", "seaside", 2900, 0, 1100, "childhood", "summer"],
	["seaside_night", "seaside", 3200, 0, 1270, "childhood", "summer"],
	["village_day_a", "village", 800, 0, 700, "childhood", "summer"],
	["village_day_b", "village", 2000, 0, 760, "childhood", "summer"],
	["village_day_c", "village", 3000, 0, 820, "childhood", "summer"],
	["village_night", "village", 1000, 0, 1270, "childhood", "summer"],
	["village_stars", "village", 3200, 0, 1290, "childhood", "summer"],
	["street_lane_market", "street", 1390, 0, 430, "childhood", "summer"],
	["street_bus_hospital", "street", 3150, 0, 700, "childhood", "winter"],
	["hospital_door", "hospital", 500, 0, 600, "childhood", "winter"],
	# 整幅（RES 宽 = 图宽 × 1.2，一屏装下整张图）：RES=3840x1080 --only=market_full_dawn,market_full_night 之类
	["market_full_dawn", "market", 1600, 0, 420, "childhood", "summer"],
	["market_full_night", "market", 1600, 0, 1280, "childhood", "summer"],
	["seaside_full_day", "seaside", 1900, 0, 720, "childhood", "summer"],
	["seaside_full_night", "seaside", 1900, 0, 1280, "childhood", "summer"],
	["village_full_day", "village", 1800, 0, 720, "childhood", "summer"],
	["village_full_night", "village", 1800, 0, 1280, "childhood", "summer"],
]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
		elif a == "--clean":
			clean = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name, " ", img.get_size())


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.6)
	main = current_scene
	await _wait(0.8)
	main._start_preview()
	main.names = {"qing": "小满", "mei": "阿蘅"}
	var w: Node = main.world
	for r in ["qing", "mei"]:
		w.actors[r].display_name = main.names[r]
	await _wait(2.2)
	if clean:
		main.hud.visible = false
		for n in ["toast", "action_btn", "slot_btn", "goal_panel"]:
			var c = main.get(n)
			if c is CanvasItem:
				c.visible = false
	for s in SHOTS:
		if not only.is_empty() and not str(s[1]) in only and not str(s[0]) in only:
			continue
		var sc: Dictionary = w.scenes.get(str(s[1]), {})
		if sc.is_empty():
			continue
		var y := float(sc.floors[int(s[3])])
		var me: Node2D = w.me()
		me.position = Vector2(float(s[2]), y)
		me.walk_target = me.position
		# 对门站在旁边，看两个人同框
		var other: Node2D = w.actors.mei
		other.visible = true
		other.position = Vector2(float(s[2]) + 150.0, y)
		other.net_target = other.position
		other.walk_target = other.position
		w.set_stage(str(s[5]))
		if w.has_method("set_season"):
			w.set_season(str(s[6]), int(s[7]) if s.size() > 7 else 0)
		main._preview_minute = float(s[4])
		await _wait(0.4)
		# 走两步，镜头和走路的样子都拍进去
		me.walk_target = me.position + Vector2(60.0, 0.0)
		await _wait(1.0)
		main._preview_minute = float(s[4])
		await _wait(0.25)
		await _snap(str(s[0]))
	quit()
