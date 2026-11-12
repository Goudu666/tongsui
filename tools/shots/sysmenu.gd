extends SceneTree
## 菜单（ui/system_menu.gd）的截图：标题页、河畔里（联机的 HUD）、离线逛逛各开一回菜单。
##   xvfb-run -a godot --path client --rendering-driver opengl3 --resolution 1920x1080 \
##     --script tools/shots/sysmenu.gd -- --out=<输出目录> [--notch=96]
## 不联网：往 main.gd 里喂假数据（和 ui.gd 一样的结构）。

var out_dir := "user://shots"
var main: Node
const Menu := preload("res://scripts/ui/system_menu.gd")


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		if a.begins_with("--notch=") and float(a.trim_prefix("--notch=")) > 0.0:
			var n := float(a.trim_prefix("--notch="))
			load("res://scripts/ui/kit.gd").safe_override = Vector2(n, n)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name, " ", img.get_size())


func _open() -> void:
	main.sysmenu._toggled_at = -1.0
	main.sysmenu.open()
	await _wait(1.0)


func _close() -> void:
	main.sysmenu.close()
	await _wait(0.6)


func _run() -> void:
	var cfg := ConfigFile.new()
	for k in ["walk", "story", "slot", "wait", "together", "gate", "need", "night", "day", "goal"]:
		cfg.set_value("tips", k, true)
	cfg.save("user://guide.cfg")
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.6)
	main = current_scene
	await _wait(1.2)
	await _snap("m01_title_button")
	await _open()
	await _snap("m02_title_menu")
	await _close()

	main.guide.process_mode = Node.PROCESS_MODE_DISABLED
	main._start_preview()
	main.names = {"qing": "小满", "mei": "阿蘅"}
	for r in ["qing", "mei"]:
		main.world.actors[r].display_name = main.names[r]
	await _wait(2.5)
	# 联机时的 HUD（假装服务器发来了状态）
	main.offline_preview = false
	main.life = {"turn": 17}
	var junior := {"id": "m_junior", "title": "小升初", "age": 12, "turns": 14, "lines": [
		{"id": "key", "text": "去重点班", "by": "心智", "unit": "分", "have": 58, "need": 64, "ok": false}]}
	main.last_world = {"minute": 390.0, "slot": 0, "ready": {"qing": false, "mei": true}, "playing": false, "rest": false,
		"needs": {"qing": {"hunger": 22, "energy": 81, "mood": 64, "clean": 47}},
		"money": {"qing": 12}, "bond": {"sync": 14, "close": 46},
		"goals": {"qing": junior, "mei": junior},
		"stats": {"qing": {"body": 6.2, "mind": 5.8, "charm": 4.1, "luck": 5.0}, "mei": {"body": 4.4, "mind": 6.6, "charm": 6.9, "luck": 3.0}},
		"eff": {"qing": 1.1, "mei": 0.9},
		"tracks": {"qing": {"id": "primary", "label": "上小学"}, "mei": {"id": "primary", "label": "上小学"}}}
	main._stage_shown = "childhood"
	main.world.set_stage("childhood")
	main.world.set_minute(462.0)
	main._partner_online = true
	main._refresh_hud()
	await _wait(1.5)
	await _snap("m03_world_button")
	await _open()
	await _snap("m04_world_menu")
	print("sheet ", main.sysmenu._sheet.get_rect(), " body min ", main.sysmenu._body.get_combined_minimum_size())
	# 拖一下音量：音乐拉到一半、动静关掉
	var sliders: Array = main.sysmenu._body.get_children().filter(func(c): return c is Menu.InkSlider)
	if sliders.size() == 3:
		var t: Rect2 = sliders[0]._track()
		sliders[0]._set_from(t.position.x + t.size.x * 0.55, false)
		sliders[2]._set_from(t.position.x - 20.0, false)
		await _wait(0.3)
		await _snap("m05_world_menu_volume")
		sliders[0]._set_from(t.end.x + 20.0, true)
		sliders[2]._set_from(t.end.x + 20.0, true)
	await _close()
	await _snap("m06_closed")
	print("done")
	quit()
