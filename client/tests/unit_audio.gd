extends SceneTree
## 声音的单测（不需要服务器，也不需要声卡）：
##   - 清单里的文件都在，能被引擎当成音频读进来
##   - 每个人生阶段的四条分轨一样长（差一个采样都会越放越错位）
##   - 声景表引用的声音和地点都存在，五个阶段的密度都填了
##   - 地点权重：站在里面是 1，走远了归 0
##   - 配乐播放器：一段放完会歇，换阶段不报错
##   - 观察者依赖的主场景属性、联机信号、按钮字样都还在
## 跑法：godot --headless --path client -s res://tests/unit_audio.gd

const Soundscape := preload("res://scripts/audio/soundscape.gd")
const MusicPlayer := preload("res://scripts/audio/music_player.gd")
const Director := preload("res://scripts/audio/audio_director.gd")
const Observer := preload("res://scripts/audio/main_observer.gd")

var _failures := 0


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)  # 等场景树转起来，播放器才能真的 play


func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://audio/manifest.json"))
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://audio/soundscape.json"))

	# 文件
	var count := 0
	for rel in manifest.files:
		var s: Variant = load("res://audio/" + rel)
		_ok(s is AudioStream, "读不进来：" + rel)
		if s is AudioStream:
			_ok(absf(s.get_length() - float(manifest.files[rel].seconds)) < 0.05, "长度对不上：" + rel)
			count += 1
	print("[audio] %d 个声音文件" % count)

	# 分轨等长
	for stage in ["child", "teen", "young", "middle", "old"]:
		_ok(manifest.stages.has(stage), "清单里没有阶段 " + stage)
		var lens := []
		for stem in MusicPlayer.STEMS:
			lens.append(float(manifest.files["music/%s_%s.ogg" % [stage, stem]].seconds))
		_ok(lens.max() - lens.min() < 0.0005, "%s 的分轨不一样长：%s" % [stage, lens])
		for kind in ["call_qing", "call_mei", "resonance", "mismatch"]:
			_ok(manifest.files.has("music/%s_%s.ogg" % [stage, kind]), "缺默契乐句 %s_%s" % [stage, kind])
	for stage in Director.STAGE_FILE.values():
		_ok(manifest.stages.has(stage), "STAGE_FILE 指向不存在的阶段 " + stage)

	# 声景表
	var zone_ids := ["in", "out"]
	for z in content.map.zones:
		zone_ids.append(str(z.id))
	for z in table.indoor:
		_ok(z in zone_ids, "indoor 里的地点不存在：" + str(z))
	for cfg in table.beds:
		_ok(manifest.files.has("amb/%s.ogg" % cfg.file), "声景表引用了不存在的循环：" + str(cfg.file))
		_ok(bool(manifest.files.get("amb/%s.ogg" % cfg.file, {}).get("loop", false)), "不是循环素材：" + str(cfg.file))
		_check_cfg(cfg, zone_ids)
	for cfg in table.shots:
		for f in cfg.files:
			_ok(manifest.files.has("amb/%s.ogg" % f), "声景表引用了不存在的单发声：" + str(f))
		_ok(cfg.has("every") or cfg.has("at"), "单发声要有 every 或 at：" + str(cfg.files))
		_check_cfg(cfg, zone_ids)

	# 行动音：地图上的每个行动，在每个阶段都落在一条真有的声音上（按导演的映射查：duty 分上学 / 上班，没有自己声音的借一条近的）
	for a in content.map.actions:
		for stage in Director.STAGE_FILE.values():
			var cue_name: String = Director.act_cue(str(a.id), stage)
			_ok(manifest.files.has("sfx/%s.ogg" % cue_name), "行动没有声音：%s（%s 阶段落在 %s）" % [a.id, stage, cue_name])
	for from in Director.ACT_ALIAS:
		_ok(manifest.files.has("sfx/act_%s.ogg" % Director.ACT_ALIAS[from]), "ACT_ALIAS 把 %s 指到了不存在的声音" % from)

	# 观察者的依赖：它读的属性、听的信号、认的按钮字样都还在。
	# 观察者对不上就不出声、不报错，所以改名要在这里变成红的，不能等人发现游戏哑了一块
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	var net_src := FileAccess.get_file_as_string("res://scripts/net/lifeline_client.gd")
	var handlers := (Observer as Script).get_script_method_list().map(func(m): return m.name)
	for prop in Observer.READS:
		_ok(_declares(main_src, "var", prop), "main.gd 里没有属性 %s 了（见 main_observer.gd 的 READS）" % prop)
	for sig in Observer.SIGNALS:
		_ok(_declares(net_src, "signal", sig), "lifeline_client.gd 里没有信号 %s 了（见 main_observer.gd 的 SIGNALS）" % sig)
		_ok(handlers.has("_on_" + sig), "main_observer.gd 少了 _on_%s" % sig)
	for page in Observer.PAGE_SCENE:
		_ok(main_src.contains("\"%s\"" % page), "main.gd 里没有叫 %s 的页面了（见 main_observer.gd 的 PAGE_SCENE）" % page)
	for pair in Observer.TEXT_KINDS:
		_ok(main_src.contains(pair[0]), "main.gd 里没有带「%s」的按钮了（见 main_observer.gd 的 TEXT_KINDS）" % pair[0])

	# 地点权重
	var scape := Soundscape.new()
	root.add_child(scape)
	scape.setup(content.map)
	var river: Variant = null
	for z in content.map.zones:
		if z.id == "river":
			river = Rect2(z.rect[0], z.rect[1], z.rect[2], z.rect[3])
	var w: Dictionary = scape.zone_weights(river.get_center(), 420.0)
	_ok(is_equal_approx(w.river, 1.0) and is_equal_approx(w.out, 1.0), "站在河边，河的分量应该是 1")
	w = scape.zone_weights(river.position - Vector2(2000, 0), 420.0)
	_ok(is_zero_approx(w.river), "离河两千像素，河的分量应该是 0")
	_ok(scape.is_indoor(Vector2(740, 470)) and not scape.is_indoor(river.get_center()), "楼道是室内，河边是室外")
	_ok(is_equal_approx(Soundscape._hours({"hours": [[390, 610]]}, 500.0), 1.0), "时段里面应该是 1")
	_ok(is_zero_approx(Soundscape._hours({"hours": [[390, 610]]}, 700.0)), "时段外面应该是 0")
	# 跑一整天：各种地点、各个阶段，不能报错
	scape.active = true
	for stage in Soundscape.STAGES:
		var minute := 390.0
		while minute < 1320.0:
			scape.update(0.25, Vector2(randf() * 2400.0, randf() * 1600.0), minute, stage, ["spring", "summer", "autumn", "winter"][int(minute) % 4], true)
			minute += 7.0

	# 配乐播放器
	var music := MusicPlayer.new()
	music.manifest = manifest
	root.add_child(music)
	music.set_mode("title")
	music._process(0.1)
	music.set_mode("life")
	music.set_stage("child")
	music.set_mix("qing", 1.0, true, 40.0, 500.0)
	for i in 40:
		music._process(0.1)
	_ok(music.is_playing_piece(), "进了河畔里几秒之后应该开始放一段")
	_ok(music._target.mei > -1.0 and music._target.he > -6.0, "两人同框、默契 40：梅的旋律和「合」都应该出来")
	music.set_mix("qing", 0.0, true, 40.0, 500.0)
	_ok(music._target.mei < -12.0 and music._target.he < -40.0, "两人离得远：梅的旋律退到背景，「合」听不见")
	music.set_mix("qing", 1.0, true, 40.0, 1290.0)
	_ok(music._target.bed <= -59.0, "夜里伴奏撤掉，只剩两个人的旋律")
	music.sting("resonance")
	music.set_stage("old")
	for i in 700:
		music._process(0.1)
	_ok(music.stage == "old", "这一段放完之后应该换成老年的编曲")
	music.set_mode("ending")
	for i in 30:
		music._process(0.1)
	_ok(not music.is_playing_piece(), "到了结局，分轨应该停下")

	print("%s unit_audio.gd：%d 个声音文件、声景表、配乐播放器" % ["✓" if _failures == 0 else "✗", count])
	quit(1 if _failures > 0 else 0)


func _check_cfg(cfg: Dictionary, zone_ids: Array) -> void:
	_ok((cfg.get("stages", []) as Array).size() == 5, "stages 要填五个阶段：" + str(cfg))
	for zid in cfg.get("zones", {}):
		_ok(zid in zone_ids, "声景表里的地点不存在：" + str(zid))
	for win in cfg.get("hours", []):
		_ok(float(win[0]) < float(win[1]), "时段写反了：" + str(win))


## 源码里有没有在行首声明 var / signal <name>
func _declares(src: String, keyword: String, ident: String) -> bool:
	var re := RegEx.create_from_string("(?m)^%s\\s+%s\\b" % [keyword, ident])
	return re.search(src) != null


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("[audio] ✗ " + msg)
