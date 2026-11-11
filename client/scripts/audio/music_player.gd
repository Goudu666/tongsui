extends Node
## 配乐。一个主题，五个人生阶段，每个阶段八条同步的分轨（一样长）：
##   bed 伴奏 / qing 青的旋律 / mei 梅的旋律 / he 两人同框时才浮上来的和声
##   qing_b / mei_b 第二支曲子（B 曲）：同一套和弦、同一个长度，旋律是主题的变奏
##   morn 早上、下雪那一层（亮、稀、高）/ eve 傍晚、晚上、下雨那一层（暖、低、长音）
## 青和梅的旋律是一逗一捧，各说半句。自己的那条一直在；对方的那条随两人的距离变化：
## 隔着楼只剩一点影子，走近了才听得清。「合」这一条还要看默契值——默契越高，同框时和声越厚。
##
## 音乐不是一直响的。一遍主题（40~60 秒）算一段，放完歇一会儿，把地方让给环境音。
## 一段一段轮着来：A 曲、B 曲、A 曲、B 曲，第五段只放伴奏层歇口气（ROTATION），听一小时不是一首歌在转。
## 一天里的五段时间和天气调 bed / morn / eve 三层的分量；下雨天 Music 总线上再挂一层低通和混响。
##
## 高光（关口揭晓、长大）走自己的播放器（highlight）：揭晓时配乐压低，长大时这一段收掉，放完从新阶段开始。
## 素材由 tools/audio/build_audio.py 生成在 res://audio/music/。哪个阶段缺了哪条分轨，就跳过它（老素材也能放）。

const DIR := "res://audio/music/"
const STEMS := ["bed", "qing", "mei", "he", "qing_b", "mei_b", "morn", "eve"]
## 逻辑上的声部（_target 的键）。qing / mei 这一段放 A 曲还是 B 曲，由 _variant 决定落到哪条分轨上
const VOICES := ["bed", "qing", "mei", "he", "morn", "eve"]
## 一段一段轮着放：a = A 曲，b = B 曲，bed = 只放伴奏层（没有两条旋律）
const ROTATION := ["a", "b", "a", "b", "bed"]
const BUS := "Music"
const SILENT := -60.0
const FADE_RATE := 28.0   ## 分轨音量每秒最多变多少 dB
const LAYER_RATE := 10.0  ## morn / eve 两层慢一点（天气说变就变，耳朵里要慢慢变）
const REVEAL_DUCK := -12.0  ## 揭晓的高光响着，配乐压这么多
const HL_DB := 0.0        ## 高光文件本身是 -18 LUFS，比配乐全开（-20）响一点，不再加减
const RISE_FADE := 0.12   ## pass / top / miss 来了，rise 用多久淡掉
const GROW_TAIL := 0.2    ## 长大那段还剩这么多秒时，新阶段的第一段就起

enum { OFF, REST, PLAY }

var manifest: Dictionary = {}
var mode := ""       ## "" / title / roll / ending / life
var stage := ""      ## child / teen / young / middle / old
var rest_range := Vector2(14.0, 26.0)

var _stems: AudioStreamPlayer
var _sync: AudioStreamSynchronized
var _single: AudioStreamPlayer
var _stings: Array[AudioStreamPlayer] = []
var _sting_i := 0
var _cache: Dictionary = {}
var _names: Array = []     ## 这个阶段真有的分轨（_sync 里的顺序）
var _cur := {}             ## 分轨名 -> 现在的音量
var _target := {}          ## 声部名（VOICES）-> 目标音量
var _state := OFF
var _t := 0.0
var _len := 0.0
var _rest := 0.0
var _piece_db := 0.0       ## 这一段整体的淡入淡出
var _piece_target := 0.0
var _piece_n := 0          ## 这个阶段放到第几段了（ROTATION）
var _variant := "a"
var _duck := 0.0           ## 默契乐句响的时候把配乐压下去
var _duck_left := 0.0
var _duck_db := 0.0        ## 实际压了多少（平滑过的）
var _single_want := ""
var _single_now := ""
var _pending_stage := ""
var _hold := 0.0           ## 长大的那段还要放多久：放完之前不起新的一段

# 高光
var _hl: Array[Hl] = []

# Music 总线上的低通和混响（下雨）：只建一次，之后只挪参数
var _lpf: AudioEffectLowPassFilter
var _rev: AudioEffectReverb
var _bus_i := -1
var _lpf_i := -1
var _rev_i := -1
var _cut := 20000.0
var _cut_target := 20000.0
var _wet := 0.0
var _wet_target := 0.0


## 一个高光播放器：放的是哪个、往哪个音量淡、多快
class Hl:
	var p: AudioStreamPlayer
	var name := ""
	var kind := ""         ## rise / pass / top / miss / grow
	var to := 0.0          ## 淡到多少 dB（SILENT 就是要停）
	var rate := 0.0        ## 每秒多少 dB；0 是不淡

	func busy() -> bool:
		return p.playing and to > SILENT


func _init() -> void:
	_stems = _player()
	_single = _player()
	for i in 3:
		_stings.append(_player())
	for i in 3:
		var h := Hl.new()
		h.p = _player()
		_hl.append(h)
	_single.volume_db = SILENT
	for k in STEMS:
		_cur[k] = SILENT
	for k in VOICES:
		_target[k] = SILENT


func _ready() -> void:
	_setup_fx()


func _player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = BUS
	add_child(p)
	return p


func _load(file: String, loop := false) -> AudioStream:
	if _cache.has(file):
		return _cache[file]
	var path := DIR + file + ".ogg"
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	if s is AudioStreamOggVorbis:
		s.loop = loop
	_cache[file] = s
	return s


# ---------------------------------------------------------------- 外部接口 ----

## 切场景：title 标题和大厅 / roll 投胎 / life 河畔里 / ending 一生 / "" 不出声
func set_mode(m: String) -> void:
	if m == mode:
		return
	mode = m
	_single_want = m if m in ["title", "roll", "ending"] else ""
	if m == "life":
		_state = REST
		_rest = 3.0  # 先让环境音站住，音乐后进
	else:
		_stop_piece()


## 人生阶段变了：这一段放完（或淡掉）之后换编曲
func set_stage(s: String) -> void:
	if s == stage or s == "":
		return
	if stage == "" or _state != PLAY:
		_apply_stage(s)
	else:
		_pending_stage = s
		_stop_piece()


## 每帧喂一次混音参数。
##   near 0~1：两人离得多近；partner_live：对方真人在线（否则是影子）；
##   sync：默契值 0~100；minute：游戏里几点；weather：rain / snow / catkin / leaf / ""（屋里没有天气）
## 一天五段（world_view.gd 的 SLOTS）：早上 390–480、上午 480–720、下午 720–930、傍晚 930–1110、晚上 1110–1320
##   早上 morn 浮着、bed 轻；白天正常；傍晚 eve 进、bed 退；晚上 bed 撤、eve 托着两条旋律
##   下雨 eve 上、morn 撤，总线上低通 + 混响；下雪 morn 上、bed 退
func set_mix(my_role: String, near: float, partner_live: bool, sync: float, minute: float, weather := "") -> void:
	var other := "mei" if my_role == "qing" else "qing"
	var rain := 1.0 if weather == "rain" else 0.0
	var snow := 1.0 if weather == "snow" else 0.0
	var morning := 1.0 - smoothstep(450.0, 540.0, minute)  # 过了七点半慢慢收，九点收干净
	var noon := smoothstep(690.0, 750.0, minute)
	var dusk := smoothstep(900.0, 960.0, minute)
	var night := smoothstep(1100.0, 1160.0, minute)        # 六点半以后伴奏撤，只剩两个人的声音
	var bed := lerpf(0.0, -4.0, morning)
	bed = lerpf(bed, -2.0, noon)
	bed = lerpf(bed, -6.0, dusk)
	bed = lerpf(bed, SILENT, night)
	_target.bed = maxf(bed - 2.0 * rain - 4.0 * snow, SILENT)
	_target[my_role] = lerpf(0.0, -2.0, night)
	var p := lerpf(-17.0, 0.0, near)
	if not partner_live:
		p = minf(p, -9.0) - 3.0  # 影子：听得见，但始终隔着一层
	_target[other] = p + lerpf(0.0, -2.0, night)
	var warmth := near * near * (0.3 + 0.7 * (1.0 - exp(-sync / 12.0)))
	if not partner_live:
		warmth *= 0.3
	_target.he = linear_to_db(maxf(warmth, 0.001)) + 1.0
	# 两层：按分量（0~1）算，再换成 dB，淡进淡出才匀
	var morn := maxf(morning, 0.9 * snow)
	if weather == "catkin":
		morn = maxf(morn, 0.35)  # 柳絮：一点点亮
	morn *= 1.0 - rain
	var eve := maxf(maxf(0.7 * dusk, night), 0.85 * rain)
	if weather == "leaf":
		eve = maxf(eve, 0.35)    # 落叶：一点点暖
	_target.morn = _gain_db(morn)
	_target.eve = _gain_db(eve)
	# 总线：下雨像隔着窗户听，高频收掉、屋子大一点；夜里也稍微多一点余音
	_cut_target = 3200.0 if rain > 0.0 else 20000.0
	_wet_target = 0.14 * rain + 0.04 * night * (1.0 - rain)


## 默契乐句。kind：call_qing / call_mei / resonance / mismatch
func sting(kind: String, db := 0.0, duck_db := -9.0) -> void:
	var s := _load("%s_%s" % [stage if stage != "" else "child", kind])
	if s == null:
		return
	var p := _stings[_sting_i]
	_sting_i = (_sting_i + 1) % _stings.size()
	p.stream = s
	p.volume_db = db - 3.0
	p.play()
	if duck_db < 0.0:
		_duck = duck_db
		_duck_left = s.get_length() * 0.8


## 高光：<阶段>_rise / _pass / _top / _miss（关口揭晓）、grow_<阶段>（长大）。独立的播放器，叠在配乐上面。
##   揭晓：放着的时候配乐压 12 dB；pass / top / miss 来了，正在放的 rise 0.12 秒淡掉。
##   top（够着名次档）紧跟在 pass 后面来：top 就是 pass 再加一层，从 pass 放到的地方接着放，换过去听不出缝。
##   长大：这一段收掉，长大那段放完，新阶段的第一段接着起（grow 会顺手换阶段）。
## 文件不在就什么也不做，返回 false。
func highlight(hl_name: String, db := 0.0) -> bool:
	var s := _load(hl_name)
	if s == null:
		return false
	var kind := "grow" if hl_name.begins_with("grow_") else hl_name.get_slice("_", hl_name.get_slice_count("_") - 1)
	var from := -1.0
	if kind != "grow":
		for h in _hl:
			if h.busy() and h.kind == "rise":
				_fade(h, SILENT, RISE_FADE)
			elif h.busy() and kind == "top" and h.kind == "pass" and h.p.get_playback_position() < 2.0:
				from = h.p.get_playback_position()  # 从 pass 放到的地方接上 top
				_fade(h, SILENT, 0.08)
			elif h.busy() and h.kind == kind:
				_fade(h, SILENT, RISE_FADE)  # 同一种又来了（两回揭晓挨得太近）：旧的让开
	var h := _free_hl()
	h.p.stream = s
	h.name = hl_name
	h.kind = kind
	h.to = HL_DB + db
	h.rate = 0.0
	if from >= 0.0:
		h.p.volume_db = h.to - 24.0  # 和 pass 交叉着换过去
		h.rate = 24.0 / 0.06
	else:
		h.p.volume_db = h.to
	h.p.play(maxf(from, 0.0))
	if kind == "grow":
		_stop_piece()
		_hold = maxf(_hold, s.get_length() - GROW_TAIL)
	return true


## 长大：放 grow_<新阶段>，这一段收掉，放完从新阶段开始。没有长大的文件也照样换阶段
func grow(s: String) -> void:
	if not highlight("grow_" + s):
		set_stage(s)
		return
	if s != stage and s != "":
		if _state == PLAY:
			_pending_stage = s  # 这一段正在收（highlight 收的），收完了再换
		else:
			_apply_stage(s)
	if mode == "life" and _state != PLAY:
		_state = REST
		_rest = minf(_rest, 0.3)  # 别等「关口」那三十秒的静了：翻过一页，接着就是新的一章


## 一天结束、有人走了：音乐收住，歇得久一点
func hush(rest_seconds := 6.0) -> void:
	_stop_piece()
	if mode == "life":
		_rest = rest_seconds


func is_playing_piece() -> bool:
	return _state == PLAY


## 这一段放的是哪支：a / b / bed（只有伴奏）
func variant() -> String:
	return _variant


## 揭晓的高光是不是正在响（观察者拿它判断：日志里那句「关口」乐句还要不要响）
func highlight_playing(kind := "") -> bool:
	for h in _hl:
		if h.busy() and h.kind != "grow" and (kind == "" or h.kind == kind):
			return true
	return false


# ---------------------------------------------------------------- 内部 ----

static func _gain_db(g: float) -> float:
	return maxf(linear_to_db(maxf(g, 0.001)), SILENT)


## 这个阶段有哪几条分轨：清单里写了（stages[阶段].stems）就照它，没写就是全部；文件不在的跳过
func _stage_stems(s: String) -> Array:
	var listed: Variant = manifest.get("stages", {}).get(s, {}).get("stems")
	var want: Array = listed if listed is Array else STEMS
	var out := []
	for k in STEMS:
		if k in want and ResourceLoader.exists("%s%s_%s.ogg" % [DIR, s, k]):
			out.append(k)
	return out


func _apply_stage(s: String) -> void:
	stage = s
	_pending_stage = ""
	_names = _stage_stems(s)
	_sync = AudioStreamSynchronized.new()
	_sync.stream_count = _names.size()
	for i in _names.size():
		_sync.set_sync_stream(i, _load("%s_%s" % [s, _names[i]], true))
		_sync.set_sync_stream_volume(i, SILENT)
	for k in STEMS:
		_cur[k] = SILENT
	_stems.stop()
	_stems.stream = _sync
	_len = float(manifest.get("stages", {}).get(s, {}).get("seconds", 40.0))
	_piece_n = 0


## 一条分轨现在该多响：A 曲的时候 B 曲那两条不出声，反过来也一样；只放伴奏的那一段两条旋律都不出声
func _stem_db(k: String) -> float:
	match k:
		"qing", "mei":
			return _target[k] if _variant == "a" else SILENT
		"qing_b":
			return _target.qing if _variant == "b" else SILENT
		"mei_b":
			return _target.mei if _variant == "b" else SILENT
		"he":
			return _target.he - (4.0 if _variant == "bed" else 0.0)
	return _target.get(k, SILENT)


func _start_piece() -> void:
	if stage == "" or _sync == null:
		return
	_variant = ROTATION[_piece_n % ROTATION.size()]
	if _variant == "b" and not ("qing_b" in _names and "mei_b" in _names):
		_variant = "a"  # 老素材没有 B 曲
	_piece_n += 1
	for k in _names:  # 开头不做淡入：第一小节就是一个起音
		_cur[k] = _stem_db(k)
	_push_volumes()
	_piece_db = 0.0
	_piece_target = 0.0
	_t = 0.0
	_stems.volume_db = _duck_db
	_stems.play()
	_state = PLAY


func _stop_piece() -> void:
	if _state == PLAY:
		_piece_target = SILENT


func _push_volumes() -> void:
	for i in _names.size():
		_sync.set_sync_stream_volume(i, maxf(_cur[_names[i]], SILENT))


func _free_hl() -> Hl:
	for h in _hl:
		if not h.p.playing:
			return h
	var best := _hl[0]  # 都占着：挤掉最安静的那个
	for h in _hl:
		if h.p.volume_db < best.p.volume_db:
			best = h
	best.p.stop()
	return best


func _fade(h: Hl, to: float, seconds: float) -> void:
	h.to = to
	h.rate = absf(h.p.volume_db - to) / maxf(seconds, 0.01)


func _setup_fx() -> void:
	_bus_i = AudioServer.get_bus_index(BUS)
	if _bus_i < 0:
		return
	for i in AudioServer.get_bus_effect_count(_bus_i):  # 已经挂过（导演重进了一回）：接着用
		var fx := AudioServer.get_bus_effect(_bus_i, i)
		if fx is AudioEffectLowPassFilter and _lpf == null:
			_lpf = fx
			_lpf_i = i
		elif fx is AudioEffectReverb and _rev == null:
			_rev = fx
			_rev_i = i
	if _lpf == null:
		_lpf = AudioEffectLowPassFilter.new()
		_lpf.cutoff_hz = 20000.0
		_lpf.resonance = 0.5
		AudioServer.add_bus_effect(_bus_i, _lpf)
		_lpf_i = AudioServer.get_bus_effect_count(_bus_i) - 1
	if _rev == null:
		_rev = AudioEffectReverb.new()
		_rev.room_size = 0.7
		_rev.damping = 0.65
		_rev.spread = 0.8
		_rev.hipass = 0.15
		_rev.predelay_msec = 30.0
		_rev.dry = 1.0
		_rev.wet = 0.0
		AudioServer.add_bus_effect(_bus_i, _rev)
		_rev_i = AudioServer.get_bus_effect_count(_bus_i) - 1
	_cut = _lpf.cutoff_hz
	_wet = _rev.wet
	_apply_fx()


## 参数慢慢挪（低通按对数走，四五秒从全开到隔着窗户），不重建效果器；不用的时候整个关掉
func _step_fx(delta: float) -> void:
	if _lpf == null:
		return
	if is_equal_approx(_cut, _cut_target) and is_equal_approx(_wet, _wet_target):
		return
	_cut = exp(move_toward(log(_cut), log(_cut_target), 0.5 * delta))
	_wet = move_toward(_wet, _wet_target, 0.05 * delta)
	_apply_fx()


func _apply_fx() -> void:
	if _bus_i < 0 or _bus_i >= AudioServer.bus_count or maxi(_lpf_i, _rev_i) >= AudioServer.get_bus_effect_count(_bus_i) \
			or AudioServer.get_bus_effect(_bus_i, _lpf_i) != _lpf:
		return  # 总线被人动过了：不碰
	_lpf.cutoff_hz = _cut
	_rev.wet = _wet
	AudioServer.set_bus_effect_enabled(_bus_i, _lpf_i, _cut < 19000.0)
	AudioServer.set_bus_effect_enabled(_bus_i, _rev_i, _wet > 0.002)


func _process(delta: float) -> void:
	_step_fx(delta)
	if _hold > 0.0:
		_hold -= delta

	# 高光：各自往目标音量淡，淡没了就停
	var revealing := false
	for h in _hl:
		if not h.p.playing:
			continue
		if h.rate > 0.0:
			h.p.volume_db = move_toward(h.p.volume_db, h.to, h.rate * delta)
			if is_equal_approx(h.p.volume_db, h.to):
				h.rate = 0.0
		if h.to <= SILENT and h.p.volume_db <= SILENT + 0.5:
			h.p.stop()
		elif h.kind != "grow":
			revealing = true

	# 压低：默契乐句、揭晓的高光。压下去快，回来慢
	if _duck_left > 0.0:
		_duck_left -= delta
	var duck_want := minf(_duck if _duck_left > 0.0 else 0.0, REVEAL_DUCK if revealing else 0.0)
	_duck_db = move_toward(_duck_db, duck_want, (80.0 if duck_want < _duck_db else 10.0) * delta)

	# 单曲（标题 / 投胎 / 一生）：先把上一首淡掉，再换下一首
	if _single_now != _single_want:
		_single.volume_db = move_toward(_single.volume_db, SILENT, 50.0 * delta)
		if _single.volume_db <= SILENT + 0.5 or not _single.playing:
			_single.stop()
			_single_now = _single_want
			if _single_now != "":
				_single.stream = _load(_single_now, _single_now != "ending")
				if _single.stream != null:
					_single.volume_db = 0.0 if _single_now == "ending" else -24.0
					_single.play()
	elif _single_now != "":
		_single.volume_db = move_toward(_single.volume_db, 0.0, 16.0 * delta)

	# 分轨
	match _state:
		REST:
			if _stems.playing:
				_stems.stop()
			_rest -= delta
			if _rest <= 0.0 and _hold <= 0.0 and mode == "life":
				if _pending_stage != "":
					_apply_stage(_pending_stage)
				_start_piece()
		PLAY:
			_t += delta
			if _t >= _len - 0.7:
				_piece_target = SILENT  # 最后一个音已经放完了，把余音收掉，别绕回第一小节
			_piece_db = move_toward(_piece_db, _piece_target, 60.0 * delta if _piece_target < _piece_db else 30.0 * delta)
			for k in _names:
				var rate := LAYER_RATE if k == "morn" or k == "eve" else FADE_RATE
				_cur[k] = move_toward(_cur[k], _stem_db(k), rate * delta)
			_push_volumes()
			_stems.volume_db = _piece_db + _duck_db
			if _piece_db <= SILENT + 0.5 or _t >= _len:
				_stems.stop()
				_state = REST if mode == "life" else OFF
				if _hold > 0.0:
					_rest = 0.0  # 长大那段放完就接
				elif _pending_stage != "":
					_rest = 2.0
				else:
					_rest = maxf(_rest, randf_range(rest_range.x, rest_range.y))
		OFF:
			if _stems.playing:
				_stems.stop()
