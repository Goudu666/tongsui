extends Node
## 配乐。一个主题，五个人生阶段，每个阶段四条同步的分轨：
##   bed 伴奏 / qing 青的旋律 / mei 梅的旋律 / he 两人同框时才浮上来的和声
## 青和梅的旋律是一逗一捧，各说半句。自己的那条一直在；对方的那条随两人的距离变化：
## 隔着楼只剩一点影子，走近了才听得清。「合」这一条还要看默契值——默契越高，同框时和声越厚。
##
## 音乐不是一直响的。一遍主题（40~60 秒）算一段，放完歇一会儿，把地方让给环境音。
## 素材由 tools/audio/build_audio.py 生成在 res://audio/music/。

const DIR := "res://audio/music/"
const STEMS := ["bed", "qing", "mei", "he"]
const BUS := "Music"
const SILENT := -60.0
const FADE_RATE := 28.0  ## 分轨音量每秒最多变多少 dB

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
var _cur := {"bed": SILENT, "qing": SILENT, "mei": SILENT, "he": SILENT}
var _target := {"bed": SILENT, "qing": SILENT, "mei": SILENT, "he": SILENT}
var _state := OFF
var _t := 0.0
var _len := 0.0
var _rest := 0.0
var _piece_db := 0.0       ## 这一段整体的淡入淡出
var _piece_target := 0.0
var _duck := 0.0           ## 默契乐句响的时候把配乐压下去
var _duck_left := 0.0
var _single_want := ""
var _single_now := ""
var _pending_stage := ""


func _init() -> void:
	_stems = _player()
	_single = _player()
	for i in 3:
		_stings.append(_player())
	_single.volume_db = SILENT


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
##   sync：默契值 0~100；minute：游戏里几点
func set_mix(my_role: String, near: float, partner_live: bool, sync: float, minute: float) -> void:
	var other := "mei" if my_role == "qing" else "qing"
	var night := smoothstep(1170.0, 1230.0, minute)       # 八点以后只剩两个人的声音
	var dusk := smoothstep(1050.0, 1110.0, minute)
	var noon := smoothstep(570.0, 630.0, minute)
	_target.bed = lerpf(lerpf(lerpf(0.0, -3.0, noon), -5.0, dusk), SILENT, night)
	_target[my_role] = lerpf(0.0, -2.0, night)
	var p := lerpf(-17.0, 0.0, near)
	if not partner_live:
		p = minf(p, -9.0) - 3.0  # 影子：听得见，但始终隔着一层
	_target[other] = p + lerpf(0.0, -2.0, night)
	var warmth := near * near * (0.3 + 0.7 * (1.0 - exp(-sync / 12.0)))
	if not partner_live:
		warmth *= 0.3
	_target.he = linear_to_db(maxf(warmth, 0.001)) + 1.0


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


## 一天结束、有人走了：音乐收住，歇得久一点
func hush(rest_seconds := 6.0) -> void:
	_stop_piece()
	if mode == "life":
		_rest = rest_seconds


func is_playing_piece() -> bool:
	return _state == PLAY


# ---------------------------------------------------------------- 内部 ----

func _apply_stage(s: String) -> void:
	stage = s
	_pending_stage = ""
	_sync = AudioStreamSynchronized.new()
	_sync.stream_count = STEMS.size()
	for i in STEMS.size():
		_sync.set_sync_stream(i, _load("%s_%s" % [s, STEMS[i]], true))
		_sync.set_sync_stream_volume(i, SILENT)
		_cur[STEMS[i]] = SILENT
	_stems.stop()
	_stems.stream = _sync
	_len = float(manifest.get("stages", {}).get(s, {}).get("seconds", 40.0))


func _start_piece() -> void:
	if stage == "" or _sync == null:
		return
	for k in STEMS:  # 开头不做淡入：第一小节就是一个起音
		_cur[k] = _target[k]
	_push_volumes()
	_piece_db = 0.0
	_piece_target = 0.0
	_t = 0.0
	_stems.volume_db = 0.0
	_stems.play()
	_state = PLAY


func _stop_piece() -> void:
	if _state == PLAY:
		_piece_target = SILENT


func _push_volumes() -> void:
	for i in STEMS.size():
		_sync.set_sync_stream_volume(i, maxf(_cur[STEMS[i]], SILENT))


func _process(delta: float) -> void:
	# 压低
	if _duck_left > 0.0:
		_duck_left -= delta
	var duck_now := _duck if _duck_left > 0.0 else 0.0

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
			if _rest <= 0.0 and mode == "life":
				if _pending_stage != "":
					_apply_stage(_pending_stage)
				_start_piece()
		PLAY:
			_t += delta
			if _t >= _len - 0.7:
				_piece_target = SILENT  # 最后一个音已经放完了，把余音收掉，别绕回第一小节
			_piece_db = move_toward(_piece_db, _piece_target, 60.0 * delta if _piece_target < _piece_db else 30.0 * delta)
			for k in STEMS:
				_cur[k] = move_toward(_cur[k], _target[k], FADE_RATE * delta)
			_push_volumes()
			_stems.volume_db = _piece_db + duck_now
			if _piece_db <= SILENT + 0.5 or _t >= _len:
				_stems.stop()
				_state = REST if mode == "life" else OFF
				_rest = maxf(_rest, randf_range(rest_range.x, rest_range.y)) if _pending_stage == "" else 2.0
		OFF:
			if _stems.playing:
				_stems.stop()
