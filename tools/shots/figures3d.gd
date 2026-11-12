extends SceneTree
## 3D 小人定妆照：两个主角五个岁数排一排（--pose=walk/idle/...），再拍一张近景。
##   xvfb-run -a godot --path client --rendering-driver opengl3 -s ../tools/shots/figures3d.gd -- --out=/tmp/fig [--pose=idle] [--close]
const Figure := preload("res://scripts/world3d/figure3d.gd")
var out := "/tmp/fig"
var pose := "idle"
var close := false
var cx := -4.0
var cy := 0.75
var fov := 22.0
var tag := ""
var portrait := ""  ## qing:young —— 只拍一个人的近景（头和肩），正脸偏一点、背后一道逆光

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
		elif a.begins_with("--pose="): pose = a.trim_prefix("--pose=")
		elif a == "--close": close = true
		elif a.begins_with("--style="): Figure.style = a.trim_prefix("--style=")
		elif a.begins_with("--cx="): cx = float(a.trim_prefix("--cx="))
		elif a.begins_with("--cy="): cy = float(a.trim_prefix("--cy="))
		elif a.begins_with("--fov="): fov = float(a.trim_prefix("--fov="))
		elif a.begins_with("--tag="): tag = a.trim_prefix("--tag=")
		elif a.begins_with("--portrait="): portrait = a.trim_prefix("--portrait=")
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
	env.background_color = Color("#cfc8bb")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b9c8dc")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 6.0  # 光和调色跟街上（stage3d 白天）一样
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new(); we.environment = env; vp.add_child(we)
	var sun := DirectionalLight3D.new(); sun.shadow_enabled = true; sun.rotation_degrees = Vector3(-38, 35, 0); sun.light_color = Color(1.0, 0.96, 0.9); sun.light_energy = 0.75; vp.add_child(sun)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-10, -140, 0); fill.light_color = Color(1.0, 0.93, 0.85); fill.light_energy = 0.25; vp.add_child(fill)
	var floor := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(30, 30); floor.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color("#6f685d"); fm.roughness = 0.9; floor.material_override = fm; vp.add_child(floor)
	var figs: Array = []
	var x := -4.5
	var who := [["qing", "childhood"], ["mei", "childhood"], ["qing", "teen"], ["mei", "teen"], ["qing", "young"], ["mei", "young"], ["qing", "middle"], ["mei", "middle"], ["qing", "old"], ["mei", "old"]]
	if portrait != "":
		who = [portrait.split(":")]
		var back := DirectionalLight3D.new(); back.rotation_degrees = Vector3(-25, 160, 0); back.light_color = Color(1.0, 0.86, 0.7); back.light_energy = 0.6; vp.add_child(back)
	for pair in who:
		if true:
			var r: String = pair[0]
			var st: String = pair[1]
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
		cam.fov = fov
		cam.look_at_from_position(Vector3(cx, cy + 0.25, 3.6), Vector3(cx, cy, 0))
	else:
		cam.fov = 30
		cam.look_at_from_position(Vector3(0, 1.4, 10.5), Vector3(0, 0.8, 0))
	cam.make_current()
	for i in 40:
		for f in figs:
			f.phase = fmod(f.phase + 0.03, 1.0)
		await process_frame
	if portrait != "":
		var f: Node3D = figs[0]
		var hd: Node3D = f.j.head
		var hp: Vector3 = hd.global_position + Vector3(0, f._spec.hr * 0.75, 0)
		var fwd: Vector3 = (f.j.root as Node3D).global_transform.basis.z.normalized()
		fwd = fwd.rotated(Vector3.UP, -0.3 if f.dir > 0 else 0.3)
		cam.fov = 21.0
		var dist: float = 1.35 + float(f._spec.hr) * 2.0
		cam.look_at_from_position(hp + fwd * dist + Vector3(0, 0.06, 0), hp - Vector3(0, f._spec.hr * 0.55, 0))
		for i in 3:
			await process_frame
	await RenderingServer.frame_post_draw
	var name := "%s%s%s%s" % [pose, "_close" if close else "", ("_" + portrait.replace(":", "_")) if portrait != "" else "", tag]
	vp.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)
	quit()
