extends SceneTree
## 3D 小人定妆照：两个主角五个岁数排一排（--pose=walk/idle/...），再拍一张近景。
##   xvfb-run -a godot --path client --rendering-driver opengl3 -s ../tools/shots/figures3d.gd -- --out=/tmp/fig [--pose=idle] [--close]
const Figure := preload("res://scripts/world3d/figure3d.gd")
var out := "/tmp/fig"
var pose := "idle"
var close := false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
		elif a.begins_with("--pose="): pose = a.trim_prefix("--pose=")
		elif a == "--close": close = true
	DirAccess.make_dir_recursive_absolute(out)
	_run()

func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#d9d2c4")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c9d4e0")
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	var we := WorldEnvironment.new(); we.environment = env; vp.add_child(we)
	var sun := DirectionalLight3D.new(); sun.shadow_enabled = true; sun.rotation_degrees = Vector3(-38, 35, 0); sun.light_color = Color("#fff1dc"); sun.light_energy = 0.9; vp.add_child(sun)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-10, -140, 0); fill.light_color = Color("#a9c4ff"); fill.light_energy = 0.35; vp.add_child(fill)
	var floor := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(30, 30); floor.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color("#9c917f"); fm.roughness = 0.9; floor.material_override = fm; vp.add_child(floor)
	var figs: Array = []
	var x := -4.5
	for st in ["childhood", "teen", "young", "middle", "old"]:
		for r in ["qing", "mei"]:
			var f := Figure.new()
			vp.add_child(f)
			f.build(r, st)
			f.position = Vector3(x, 0, 0)
			x += 1.0
			f.dir = 1 if r == "qing" else -1
			match pose:
				"walk": f.walking = true
				"idle": pass
				"sleep": f.asleep = true
				_:
					if pose in ["joy", "sad", "five", "shy", "wave"]: f.emote = pose
					else: f.loop = pose
			figs.append(f)
	var cam := Camera3D.new()
	vp.add_child(cam)
	if close:
		cam.fov = 22
		cam.look_at_from_position(Vector3(-4.0, 1.0, 3.6), Vector3(-4.0, 0.75, 0))
	else:
		cam.fov = 30
		cam.look_at_from_position(Vector3(0, 1.4, 10.5), Vector3(0, 0.8, 0))
	cam.make_current()
	for i in 40:
		for f in figs:
			f.phase = fmod(f.phase + 0.03, 1.0)
		await process_frame
	await RenderingServer.frame_post_draw
	var name := "%s%s" % [pose, "_close" if close else ""]
	vp.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)
	quit()
