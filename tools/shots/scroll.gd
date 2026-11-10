extends SceneTree
## 把一条走完的人生画成长卷，存成一张 PNG（整张，不只是一屏）。
##   godot --path client --rendering-driver opengl3 --script ../tools/shots/scroll.gd -- --life=<life.json> --out=<长卷.png>
## life.json 是结局时服务器给客户端的那份 life（log / memories / persons / ending）。没有显示器的机器套一层 xvfb-run。

const LifeScroll := preload("res://scripts/ui/life_scroll.gd")


func _initialize() -> void:
	var life_path := ""
	var out := "scroll.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--life="):
			life_path = a.substr(7)
		elif a.begins_with("--out="):
			out = a.substr(6)
	var life: Variant = JSON.parse_string(FileAccess.get_file_as_string(life_path))
	var content: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	if not (life is Dictionary) or not (content is Dictionary):
		printerr("读不到 life 或内容表")
		quit(1)
		return
	var names := {}
	for r in ["qing", "mei"]:
		names[r] = str(life.get("persons", {}).get(r, {}).get("name", r))
	var scroll: Control = LifeScroll.new()
	scroll.setup(life, content, names)
	root.add_child(scroll)
	await process_frame
	var err: Error = await scroll.save_png(out)
	print("✓ " if err == OK else "✗ ", out, " ", scroll.custom_minimum_size)
	quit(0 if err == OK else 1)
