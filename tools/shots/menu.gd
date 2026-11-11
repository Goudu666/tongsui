extends SceneTree
## 点位菜单截图：行动按钮上头那排小牌子（茶社里听一段 / 跑堂；公园里写字 / 广场舞）。
##   node tools/shots/menu_dump.mjs <json>   先从真服务器取几帧状态
##   xvfb-run -a godot --path client --rendering-driver opengl3 --resolution 1920x1080 --script res://../tools/shots/menu.gd -- --out=<目录> --frames=<json> [--only=park]

var out_dir := "user://shots"
var frames_path := ""
var only := ""  ## --only=park：只截这一帧（换了年纪会弹出章首卡，所以一个年纪跑一回）
var main: Node
var frames: Dictionary = {}
var _feed: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		if a.begins_with("--frames="):
			frames_path = a.trim_prefix("--frames=")
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	frames = JSON.parse_string(FileAccess.get_file_as_string(frames_path))
	_run()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name, " ", img.get_size())


func _pump() -> void:
	while true:
		await create_timer(0.2).timeout
		if not _feed.is_empty() and main.world != null:
			main._on_world_state(_feed.duplicate(true))


func _frame(name: String) -> void:
	var f: Dictionary = frames[name]
	main._on_snapshot(f.snapshot)
	_feed = f.world
	main._on_world_state(_feed.duplicate(true))


func _run() -> void:
	var cfg := ConfigFile.new()
	for k in ["walk", "story", "slot", "wait", "together", "gate", "need", "night", "day", "goal"]:
		cfg.set_value("tips", k, true)
	cfg.save("user://guide.cfg")
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(0.6)
	main = current_scene
	main.menu_always = true  # 不联网：当连着认菜单的服务器
	await _wait(1.0)
	_pump()
	var name := only if only != "" else "teahouse"
	_frame(name)
	await _wait(2.5)
	if main.guide != null and main.guide.has_method("_hide_tip"):
		main.guide._hide_tip()
	await _wait(0.6)
	await _snap("m_%s" % name)
	# 点一下菜单上的第一块（换一件），大按钮跟着换
	if main.menu_box.get_child_count() > 0:
		main.menu_box.get_child(0).emit_signal("pressed")
	await _wait(0.6)
	await _snap("m_%s_pick" % name)
	quit()
