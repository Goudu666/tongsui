extends SceneTree
## 声音的单测（不需要服务器，也不需要声卡）：
##   - 清单里的文件都在，能被引擎当成音频读进来
##   - 每个人生阶段的八条分轨（bed qing mei he qing_b mei_b morn eve）一样长（差一个采样都会越放越错位）
##   - 关口揭晓和长大的高光文件都在
##   - 声景表引用的声音和地点都存在，五个阶段的密度都填了
##   - 地点权重：站在里面是 1，走远了归 0
##   - 配乐播放器：一段放完会歇，换阶段不报错；时段 / 天气的混音往对的方向走；A / B 曲轮着放；
##     高光压低配乐、rise 被 pass 淡掉、top 从 pass 接上；长大时这一段收掉、放完从新阶段开始
##   - 导演：揭晓一回只起一回 rise；观察者：揭晓接管了就不再叠「关口」乐句，阶段往后走才算长大
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
		var listed: Variant = manifest.stages.get(stage, {}).get("stems")
		_ok(listed is Array, "清单里 %s 没写 stems（分轨的名字）" % stage)
		var lens := []
		for stem in MusicPlayer.STEMS:
			_ok(listed is Array and stem in listed, "清单里 %s 的 stems 少了 %s" % [stage, stem])
			var rel := "music/%s_%s.ogg" % [stage, stem]
			_ok(manifest.files.has(rel), "缺分轨 " + rel)
			if manifest.files.has(rel):
				lens.append(float(manifest.files[rel].seconds))
				_ok(bool(manifest.files[rel].get("loop", false)), "分轨要标成循环：" + rel)
		if not lens.is_empty():
			_ok(lens.max() - lens.min() < 0.0005, "%s 的分轨不一样长：%s" % [stage, lens])
			_ok(absf(float(lens[0]) - float(manifest.stages.get(stage, {}).get("seconds", 0.0))) < 0.01, "%s 的分轨和 stages.seconds 对不上" % stage)
		# 关口揭晓的高光（数分时 rise、够线 pass、名次 top、差一点 miss）
		for kind in ["rise", "pass", "top", "miss"]:
			var rel := "music/%s_%s.ogg" % [stage, kind]
			_ok(manifest.files.has(rel), "缺揭晓的高光 " + rel)
			_ok(not bool(manifest.files.get(rel, {}).get("loop", false)), "高光不该循环：" + rel)
		if stage != "child":
			_ok(manifest.files.has("music/grow_%s.ogg" % stage), "缺长大的高光 grow_" + stage)
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
	var world_src := FileAccess.get_file_as_string("res://scripts/world/world_view.gd")
	var weather_src := FileAccess.get_file_as_string("res://scripts/world/weather.gd")
	var handlers := (Observer as Script).get_script_method_list().map(func(m): return m.name)
	for prop in Observer.WORLD_READS:
		_ok(_declares(world_src, "var", prop), "world_view.gd 里没有属性 %s 了（见 main_observer.gd 的 WORLD_READS）" % prop)
	for prop in Observer.WEATHER_READS:
		_ok(_declares(weather_src, "var", prop), "weather.gd 里没有属性 %s 了（见 main_observer.gd 的 WEATHER_READS）" % prop)
	for st in Observer.STAGE_ORDER:
		_ok(Director.STAGE_FILE.has(st), "STAGE_ORDER 里的阶段 %s 不在导演的 STAGE_FILE 里" % st)
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
	music.queue_free()

	_check_mix(manifest)
	_check_rotation(manifest)
	_check_highlight(manifest)
	_check_grow(manifest)
	_check_director()
	_check_observer()

	print("%s unit_audio.gd：%d 个声音文件、声景表、配乐播放器" % ["✓" if _failures == 0 else "✗", count])
	quit(1 if _failures > 0 else 0)


## 时段 / 天气：目标音量往对的方向走。只看 _target（每条分轨的目标 dB），不用声卡
func _check_mix(manifest: Dictionary) -> void:
	var m := MusicPlayer.new()
	m.manifest = manifest
	root.add_child(m)
	var at := func(minute: float, weather: String) -> Dictionary:
		m.set_mix("qing", 0.5, true, 40.0, minute, weather)
		return m._target.duplicate()
	var dawn: Dictionary = at.call(420.0, "")       # 早上 7 点
	var day: Dictionary = at.call(600.0, "")        # 上午 10 点
	var dusk: Dictionary = at.call(1020.0, "")      # 傍晚 5 点
	var night: Dictionary = at.call(1260.0, "")     # 晚上 9 点
	_ok(dawn.morn > night.morn + 20.0, "早上 morn 应该比晚上响：%.1f / %.1f" % [dawn.morn, night.morn])
	_ok(dawn.morn > -3.0 and dawn.bed < day.bed - 2.0, "早上 morn 浮着、bed 轻：morn %.1f bed %.1f（白天 %.1f）" % [dawn.morn, dawn.bed, day.bed])
	_ok(day.morn < -20.0 and day.eve < -20.0, "上午两层都退下去：morn %.1f eve %.1f" % [day.morn, day.eve])
	_ok(dusk.eve > day.eve + 15.0 and dusk.bed < day.bed - 3.0, "傍晚 eve 进、bed 退：eve %.1f bed %.1f" % [dusk.eve, dusk.bed])
	_ok(night.bed <= MusicPlayer.SILENT + 1.0 and night.eve > -1.0, "晚上 bed 静、eve 托着：bed %.1f eve %.1f" % [night.bed, night.eve])
	_ok(night.qing > -3.0, "晚上自己的旋律还在：%.1f" % night.qing)
	var rain_dawn: Dictionary = at.call(420.0, "rain")
	var rain_day: Dictionary = at.call(600.0, "rain")
	_ok(rain_day.eve > day.eve + 15.0, "下雨 eve 上去：%.1f → %.1f" % [day.eve, rain_day.eve])
	_ok(rain_dawn.morn < dawn.morn - 20.0, "下雨 morn 下来：%.1f → %.1f" % [dawn.morn, rain_dawn.morn])
	_ok(rain_day.bed < day.bed, "下雨 bed 让一点")
	var snow_day: Dictionary = at.call(600.0, "snow")
	_ok(snow_day.morn > day.morn + 15.0 and snow_day.bed < day.bed - 2.0, "下雪 morn 上、bed 退：morn %.1f bed %.1f" % [snow_day.morn, snow_day.bed])
	# 天气不碰两条旋律的远近
	_ok(is_equal_approx(rain_day.mei, day.mei) and is_equal_approx(snow_day.he, day.he), "天气不该改两条旋律和「合」")

	# Music 总线：下雨挂上低通和混响，慢慢变；天晴了关掉。效果器只建一次
	if AudioServer.get_bus_index(MusicPlayer.BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, MusicPlayer.BUS)
	var bus := AudioServer.get_bus_index(MusicPlayer.BUS)
	m._setup_fx()
	var n_fx := AudioServer.get_bus_effect_count(bus)
	_ok(m._lpf != null and m._rev != null, "Music 总线上应该挂了低通和混响")
	m.set_mix("qing", 0.5, true, 40.0, 600.0, "rain")
	m._step_fx(0.5)
	_ok(m._lpf.cutoff_hz > 8000.0, "低通不该一下子掉下来（要慢慢挪）：%.0f Hz" % m._lpf.cutoff_hz)
	for i in 120:
		m._step_fx(0.1)
	_ok(m._lpf.cutoff_hz < 4000.0 and AudioServer.is_bus_effect_enabled(bus, m._lpf_i), "下雨十几秒后低通应该落到 4 kHz 以下：%.0f" % m._lpf.cutoff_hz)
	_ok(m._rev.wet > 0.1 and AudioServer.is_bus_effect_enabled(bus, m._rev_i), "下雨混响多一点：wet %.2f" % m._rev.wet)
	m.set_mix("qing", 0.5, true, 40.0, 600.0, "")
	for i in 200:
		m._step_fx(0.1)
	_ok(not AudioServer.is_bus_effect_enabled(bus, m._lpf_i) and not AudioServer.is_bus_effect_enabled(bus, m._rev_i), "天晴了低通和混响都关掉")
	# 下着雨离开河畔里（走完一生进结局）：低通和混响拨回去
	m.set_mode("life")
	m.set_mix("qing", 0.5, true, 40.0, 600.0, "rain")
	for i in 60:
		m._step_fx(0.1)
	m.set_mode("ending")
	_ok(is_equal_approx(m._cut_target, 20000.0) and is_equal_approx(m._wet_target, 0.0), "离开河畔里低通和混响的目标要拨回去")
	for i in 200:
		m._step_fx(0.1)
	_ok(not AudioServer.is_bus_effect_enabled(bus, m._lpf_i) and not AudioServer.is_bus_effect_enabled(bus, m._rev_i), "结局那首不该带着雨天的低通")
	var m2 := MusicPlayer.new()
	root.add_child(m2)
	_ok(AudioServer.get_bus_effect_count(bus) == n_fx and m2._lpf == m._lpf, "再建一个播放器不该重复挂效果器")
	m.queue_free()
	m2.queue_free()


## A / B 曲轮着放，第五段只放伴奏
func _check_rotation(manifest: Dictionary) -> void:
	var m := MusicPlayer.new()
	m.manifest = manifest
	m.rest_range = Vector2(0.2, 0.3)
	root.add_child(m)
	m.set_mode("life")
	m.set_stage("child")
	m.set_mix("qing", 1.0, true, 40.0, 600.0)
	_ok(m._names.size() == MusicPlayer.STEMS.size(), "童年应该八条分轨都进了同步流：%s" % [m._names])
	var seen := []
	var was := false
	var checked := {}
	for i in 3000:
		m._process(0.1)
		if m.is_playing_piece() and not was:
			seen.append(m.variant())
		was = m.is_playing_piece()
		if was and not checked.has(m.variant()):
			checked[m.variant()] = true
			match m.variant():
				"a":
					_ok(m._stem_db("qing") == m._target.qing and m._stem_db("qing_b") <= MusicPlayer.SILENT, "A 曲：qing 响、qing_b 不响")
				"b":
					_ok(m._stem_db("mei_b") == m._target.mei and m._stem_db("mei") <= MusicPlayer.SILENT, "B 曲：mei_b 响、mei 不响")
				"bed":
					for k in ["qing", "mei", "qing_b", "mei_b"]:
						_ok(m._stem_db(k) <= MusicPlayer.SILENT, "只放伴奏那一段 %s 不该响" % k)
					_ok(m._stem_db("bed") == m._target.bed, "只放伴奏那一段 bed 照常")
		if seen.size() >= 6:
			break
	_ok(seen.slice(0, 6) == ["a", "b", "a", "b", "bed", "a"], "一段一段应该是 A B A B 伴奏 A：%s" % [seen])
	m.queue_free()


## 高光：压低配乐、rise 被 pass 淡掉、top 从 pass 接上、放完压低收回来
func _check_highlight(manifest: Dictionary) -> void:
	var m := MusicPlayer.new()
	m.manifest = manifest
	root.add_child(m)
	m.set_mode("life")
	m.set_stage("young")
	for i in 40:
		m._process(0.1)
	_ok(m.is_playing_piece(), "高光之前先放着一段")
	_ok(m.highlight("young_rise"), "young_rise 应该放得出来")
	m._process(0.05)
	_ok(m.highlight_playing("rise"), "rise 在响")
	for i in 10:
		m._process(0.05)
	_ok(m._duck_db < -11.0 and m._stems.volume_db < -11.0, "揭晓的高光响着，配乐压 12 dB：%.1f" % m._duck_db)
	_ok(m.highlight("young_pass"), "young_pass 应该放得出来")
	for i in 3:
		m._process(0.05)
	_ok(not m.highlight_playing("rise") and m.highlight_playing("pass"), "pass 来了 rise 0.12 秒内淡掉")
	var rise_on := false
	for h in m._hl:
		rise_on = rise_on or (h.kind == "rise" and h.p.playing)
	_ok(not rise_on, "rise 淡完了就停")
	m.highlight("young_top")
	for i in 3:
		m._process(0.05)
	_ok(m.highlight_playing("top") and not m.highlight_playing("pass"), "名次章来了：top 接上，pass 让开")
	for h in m._hl:  # 当作都放完了
		h.p.stop()
	for i in 30:
		m._process(0.1)
	_ok(m._duck_db > -0.5, "高光放完，配乐回来：%.1f" % m._duck_db)
	_ok(not m.highlight("young_nope"), "没有的高光不出声、不报错")
	m.queue_free()


## 长大：这一段收掉，长大那段放完，新阶段从头起（A 曲）
func _check_grow(manifest: Dictionary) -> void:
	var m := MusicPlayer.new()
	m.manifest = manifest
	root.add_child(m)
	m.set_mode("life")
	m.set_stage("child")
	for i in 40:
		m._process(0.1)
	_ok(m.is_playing_piece() and m.stage == "child", "长大之前童年在放")
	var grow_len := float(manifest.files.get("music/grow_teen.ogg", {}).get("seconds", 0.0))
	m.grow("teen")
	for i in 20:
		m._process(0.1)
	_ok(not m.is_playing_piece(), "长大：童年这一段两秒内收掉")
	var t := 2.0
	while t < grow_len - 0.5:
		m._process(0.1)
		t += 0.1
		_ok(not m.is_playing_piece(), "长大那段放完之前不起新的一段（%.1f 秒）" % t)
		if m.is_playing_piece():
			break
	for i in 10:
		m._process(0.1)
	_ok(m.is_playing_piece() and m.stage == "teen" and m.variant() == "a", "长大放完，少年的第一段（A 曲）接着起：%s %s" % [m.stage, m.variant()])
	m.queue_free()


## 导演：一回揭晓只起一回 rise；pass / miss / 名次章各起各的
func _check_director() -> void:
	var d := Director.new()
	root.add_child(d)
	d._stage = "middle"
	for i in 8:
		d.reveal_cue("bead", -2.0, 1.0 + 0.05 * i)
	var rises := 0
	for h in d.music._hl:
		rises += 1 if h.kind == "rise" and h.p.playing else 0
	_ok(rises == 1, "一回揭晓只起一回 rise：%d" % rises)
	_ok(d.reveal_active(), "刚揭晓过")
	d.reveal_cue("gain", -2.0, 1.5)
	d.reveal_cue("pass")
	d.music._process(0.2)
	_ok(d.music.highlight_playing("pass") and not d.music.highlight_playing("rise"), "够线：pass 起，rise 淡掉")
	d.reveal_cue("seal", -1.0, 1.0)
	d.music._process(0.05)
	_ok(not d.music.highlight_playing("top"), "普通的章（音高 1.0）不起 top")
	d.reveal_cue("seal", -1.0, Director.TOP_PITCH)
	d.music._process(0.2)
	_ok(d.music.highlight_playing("top"), "名次章（音高 1.12）起 top")
	d.reveal_cue("bead")
	rises = 0
	for h in d.music._hl:
		rises += 1 if h.kind == "rise" and h.p.playing else 0
	_ok(rises == 0, "同一回揭晓里再来算盘珠不再起 rise")
	d._reveal_at -= Director.REVEAL_GAP + 1.0  # 过了好一会儿：下一回揭晓
	d.reveal_cue("bead")
	_ok(d.music.highlight_playing("rise"), "下一回揭晓重新起 rise")
	d.reveal_cue("miss", -1.0)
	d.music._process(0.2)
	_ok(d.music.highlight_playing("miss") and not d.music.highlight_playing("rise"), "差一点：miss 起，rise 淡掉")
	d.grow("old")  # LifeTime 的名字也认
	_ok(d._stage == "old" and d.music._hold > 1.0, "grow(\"old\")：导演换到 old，配乐等长大那段放完")
	d.queue_free()


## 观察者：揭晓的尺子接管了，「关口」那句不再叠；阶段往后走才算长大
func _check_observer() -> void:
	var stub := GDScript.new()
	stub.source_code = "extends Node\nvar stings := []\nvar grows := []\nvar active := false\n" \
		+ "func sting(k, _db := 0.0):\n\tstings.append(k)\n" \
		+ "func reveal_active(_within := 4.0) -> bool:\n\treturn active\n" \
		+ "func grow(s):\n\tgrows.append(s)\n"
	stub.reload()
	var audio: Node = stub.new()
	var ob := Observer.new()
	ob.main = Node.new()
	ob.audio = audio
	var entry := {"entries": [{"kind": "milestone", "resonance": true}]}
	ob._on_log_entries(entry)
	ob._watch_milestone(0.5)
	_ok(audio.stings.is_empty(), "关口揭晓：先等一等，看尺子数不数")
	ob._watch_milestone(0.6)
	_ok(audio.stings == ["resonance"], "没有尺子接管：照旧响合上的那一句：%s" % [audio.stings])
	audio.stings.clear()
	audio.active = true
	ob._on_log_entries(entry)
	ob._watch_milestone(1.2)
	_ok(audio.stings.is_empty(), "揭晓的高光接管了：不再叠「关口」乐句")
	ob._watch_grow("childhood")
	_ok(audio.grows.is_empty(), "刚进河畔里不算长大")
	ob._watch_grow("childhood")
	ob._watch_grow("teen")
	_ok(audio.grows == ["teen"], "童年 → 少年：长大一回：%s" % [audio.grows])
	ob._watch_grow("childhood")
	_ok(audio.grows.size() == 1, "阶段往回拨（离线逛逛、重新投胎）不算长大")
	ob.main.free()
	ob.free()
	audio.free()


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
